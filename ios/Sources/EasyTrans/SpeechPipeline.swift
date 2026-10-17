import AVFoundation
import CoreMedia
import Speech

/// One transcription update from one language's recognizer.
struct TranscriptEvent: Sendable {
    let languageID: String
    let text: String
    /// Mean word confidence (0–1), weighted by length. Nil if the recognizer gave none.
    let confidence: Double?
    let start: Double
    let end: Double
    let isFinal: Bool
}

enum PipelineError: LocalizedError {
    case microphoneDenied
    case unsupported(String)
    case noAudioFormat
    case noMicrophone

    var errorDescription: String? {
        switch self {
        case .microphoneDenied: "Kein Mikrofonzugriff. Bitte in den Einstellungen erlauben."
        case .unsupported(let name): "\(name) wird von der Spracherkennung nicht unterstützt."
        case .noAudioFormat: "Spracherkennung ist nicht bereit."
        case .noMicrophone: "Kein Mikrofon verfügbar."
        }
    }
}

/// Feeds the microphone into one on-device `SpeechTranscriber` per language at the same
/// time. Both see identical audio, so their results can be compared per time range to
/// work out who is speaking.
@MainActor
final class SpeechPipeline {
    private let engine = AVAudioEngine()
    private var analyzers: [SpeechAnalyzer] = []
    private var inputs: [AsyncStream<AnalyzerInput>.Continuation] = []
    private var resultTasks: [Task<Void, Never>] = []
    private(set) var isRunning = false

    nonisolated static func supports(_ language: AppLanguage) async -> Bool {
        await SpeechTranscriber.supportedLocale(equivalentTo: language.locale) != nil
    }

    func start(
        languages: [AppLanguage],
        onStatus: @MainActor (String) -> Void,
        onEvent: @escaping @MainActor (TranscriptEvent) -> Void
    ) async throws {
        guard !isRunning else { return }
        guard await AVAudioApplication.requestRecordPermission() else {
            throw PipelineError.microphoneDenied
        }

        var transcribers: [(id: String, transcriber: SpeechTranscriber)] = []
        var locales: [Locale] = []
        for language in languages {
            guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: language.locale) else {
                throw PipelineError.unsupported(language.shortName)
            }
            let transcriber = SpeechTranscriber(
                locale: locale,
                transcriptionOptions: [],
                reportingOptions: [.volatileResults, .fastResults],
                attributeOptions: [.transcriptionConfidence]
            )
            transcribers.append((language.id, transcriber))
            locales.append(locale)
        }
        let modules: [any SpeechModule] = transcribers.map(\.transcriber)

        await releaseUnusedLocales(keeping: locales)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: modules) {
            onStatus("Lade Spracherkennung …")
            try await request.downloadAndInstall()
        }
        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules) else {
            throw PipelineError.noAudioFormat
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement)
        try session.setActive(true)

        do {
            for (id, transcriber) in transcribers {
                let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
                let analyzer = SpeechAnalyzer(modules: [transcriber])
                try await analyzer.prepareToAnalyze(in: analyzerFormat)
                try await analyzer.start(inputSequence: stream)
                analyzers.append(analyzer)
                inputs.append(continuation)
                resultTasks.append(Task {
                    do {
                        for try await result in transcriber.results {
                            onEvent(Self.event(from: result, languageID: id))
                        }
                    } catch {
                        // Analysis was cancelled or finished.
                    }
                })
            }

            let inputNode = engine.inputNode
            let hardwareFormat = inputNode.outputFormat(forBus: 0)
            guard hardwareFormat.sampleRate > 0 else { throw PipelineError.noMicrophone }
            let feeder = AudioFeeder(from: hardwareFormat, to: analyzerFormat, continuations: inputs)
            feeder.attach(to: inputNode, format: hardwareFormat)
            engine.prepare()
            try engine.start()
            isRunning = true
        } catch {
            isRunning = true
            await stop()
            throw error
        }
    }

    func stop() async {
        guard isRunning else { return }
        isRunning = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        inputs.forEach { $0.finish() }
        inputs = []
        for analyzer in analyzers {
            await analyzer.cancelAndFinishNow()
        }
        analyzers = []
        resultTasks.forEach { $0.cancel() }
        resultTasks = []
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Asset reservations are limited, so drop languages we no longer use.
    private func releaseUnusedLocales(keeping locales: [Locale]) async {
        let keep = Set(locales.map(\.identifier))
        for reserved in await AssetInventory.reservedLocales where !keep.contains(reserved.identifier) {
            await AssetInventory.release(reservedLocale: reserved)
        }
    }

    private static func event(from result: SpeechTranscriber.Result, languageID: String) -> TranscriptEvent {
        var weighted = 0.0
        var total = 0.0
        for run in result.text.runs {
            guard let confidence = run[AttributeScopes.SpeechAttributes.ConfidenceAttribute.self] else { continue }
            let length = Double(result.text[run.range].characters.count)
            weighted += Double(confidence) * length
            total += length
        }
        return TranscriptEvent(
            languageID: languageID,
            text: String(result.text.characters),
            confidence: total > 0 ? weighted / total : nil,
            start: result.range.start.seconds,
            end: result.range.end.seconds,
            isFinal: result.isFinal
        )
    }
}

/// Runs on the audio render thread: converts mic buffers to the analyzer format and hands
/// each analyzer its own copy.
private final class AudioFeeder: @unchecked Sendable {
    private let converter: AVAudioConverter?
    private let outputFormat: AVAudioFormat
    private let continuations: [AsyncStream<AnalyzerInput>.Continuation]

    init(from inputFormat: AVAudioFormat, to outputFormat: AVAudioFormat,
         continuations: [AsyncStream<AnalyzerInput>.Continuation]) {
        self.converter = inputFormat == outputFormat ? nil : AVAudioConverter(from: inputFormat, to: outputFormat)
        self.outputFormat = outputFormat
        self.continuations = continuations
    }

    /// Installed from a nonisolated context so the tap block isn't bound to the main actor.
    func attach(to node: AVAudioInputNode, format: AVAudioFormat) {
        node.installTap(onBus: 0, bufferSize: 2048, format: format) { [self] buffer, _ in
            feed(buffer)
        }
    }

    private func feed(_ buffer: AVAudioPCMBuffer) {
        guard let converted = convert(buffer) else { return }
        for continuation in continuations {
            guard let copy = Self.copy(converted) else { continue }
            continuation.yield(AnalyzerInput(buffer: copy))
        }
    }

    private func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter else { return buffer }
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return nil }
        var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, output.frameLength > 0 else { return nil }
        return output
    }

    private static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else {
            return nil
        }
        copy.frameLength = buffer.frameLength
        let source = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: buffer.audioBufferList))
        let destination = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for (from, to) in zip(source, destination) {
            guard let fromData = from.mData, let toData = to.mData else { continue }
            memcpy(toData, fromData, Int(from.mDataByteSize))
        }
        for index in 0..<destination.count {
            destination[index].mDataByteSize = source[index].mDataByteSize
        }
        return copy
    }
}
