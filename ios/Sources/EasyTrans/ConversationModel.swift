import Foundation
import NaturalLanguage
import Observation
import Translation
import UIKit

/// Listens to both languages at once, decides per utterance who is speaking, and keeps the
/// translated conversation for each side.
@MainActor
@Observable
final class ConversationModel {
    enum Phase: Equatable {
        case idle
        case preparing(String)
        case listening
        case paused
        case failed(String)
    }

    struct Turn: Identifiable, Equatable {
        var id = UUID()
        /// Language the speaker used. The turn is shown, translated, on the *other* side.
        var sourceID: String
        var original: String
        var translation: String
        /// Still being spoken; text and translation may change.
        var isLive: Bool
    }

    private(set) var top: AppLanguage
    private(set) var bottom: AppLanguage
    private(set) var availableLanguages = AppLanguage.all
    private(set) var turns: [Turn] = []
    private(set) var live: Turn?
    private(set) var phase: Phase = .idle
    /// Set when translation models must be downloaded; the view runs `prepareTranslation()`.
    private(set) var translationPreparation: TranslationSession.Configuration?

    @ObservationIgnored private let pipeline = SpeechPipeline()
    @ObservationIgnored private let translator = Translator()
    @ObservationIgnored private var tracks: [String: Track] = [:]
    /// Audio before this time (seconds) is already committed to a turn.
    @ObservationIgnored private var committedUntil = 0.0
    @ObservationIgnored private var commitTask: Task<Void, Never>?
    @ObservationIgnored private var liveTranslationTask: Task<Void, Never>?
    @ObservationIgnored private var liveTranslationPending = false
    @ObservationIgnored private var isStarting = false

    init() {
        let defaults = UserDefaults.standard
        top = defaults.string(forKey: "topLanguage").flatMap(AppLanguage.with(id:)) ?? AppLanguage.with(id: "de-DE")!
        bottom = defaults.string(forKey: "bottomLanguage").flatMap(AppLanguage.with(id:)) ?? AppLanguage.with(id: "es-ES")!
    }

    // MARK: - Reading

    func language(of side: Side) -> AppLanguage {
        side == .top ? top : bottom
    }

    /// What `side` reads: everything the other side said, translated, oldest first.
    func items(for side: Side) -> [Turn] {
        let reader = language(of: side).id
        var items = turns.filter { $0.sourceID != reader }
        if let live, live.sourceID != reader {
            items.append(live)
        }
        return items
    }

    // MARK: - Lifecycle

    func loadAvailableLanguages() async {
        var supported: [AppLanguage] = []
        for language in AppLanguage.all {
            if await SpeechPipeline.supports(language) {
                supported.append(language)
            }
        }
        if !supported.isEmpty {
            availableLanguages = supported
        }
    }

    func start() async {
        guard !isStarting, !pipeline.isRunning else { return }
        phase = .preparing("Lade Übersetzung …")
        let status = await LanguageAvailability().status(from: top.language, to: bottom.language)
        switch status {
        case .installed:
            await startListening()
        case .supported:
            translationPreparation = TranslationSession.Configuration(source: top.language, target: bottom.language)
        case .unsupported:
            phase = .failed("\(top.shortName) ↔ \(bottom.shortName) wird nicht unterstützt.")
        @unknown default:
            await startListening()
        }
    }

    /// Called by the view after `prepareTranslation()` finished.
    func translationPrepared(success: Bool) async {
        translationPreparation = nil
        if success {
            await startListening()
        } else {
            phase = .failed("Übersetzung konnte nicht geladen werden.")
        }
    }

    func toggleListening() {
        switch phase {
        case .listening:
            Task { await pause() }
        case .paused, .idle, .failed:
            Task { await start() }
        case .preparing:
            break
        }
    }

    func pause() async {
        commit(force: true)
        await pipeline.stop()
        resetTracks()
        phase = .paused
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func startListening() async {
        guard !isStarting, !pipeline.isRunning else { return }
        isStarting = true
        defer { isStarting = false }
        phase = .preparing("Starte Spracherkennung …")
        resetTracks()
        do {
            try await pipeline.start(
                languages: [top, bottom],
                onStatus: { [weak self] in self?.phase = .preparing($0) },
                onEvent: { [weak self] in self?.handle($0) }
            )
            phase = .listening
            UIApplication.shared.isIdleTimerDisabled = true
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: - Settings

    func swapSides() {
        let oldTop = top
        top = bottom
        bottom = oldTop
        save()
    }

    func setLanguage(_ language: AppLanguage, for side: Side) {
        guard language != self.language(of: side) else { return }
        // Picking the other side's language just swaps the sides.
        if language.code == self.language(of: side == .top ? .bottom : .top).code {
            swapSides()
            return
        }
        if side == .top { top = language } else { bottom = language }
        save()
        clear()
        translator.reset()
        let wasActive = phase != .paused
        Task {
            await pipeline.stop()
            phase = .idle
            if wasActive { await start() }
        }
    }

    func clear() {
        turns = []
        live = nil
        resetTracks()
    }

    private func save() {
        UserDefaults.standard.set(top.id, forKey: "topLanguage")
        UserDefaults.standard.set(bottom.id, forKey: "bottomLanguage")
    }

    // MARK: - Speaker detection

    private struct Segment {
        var text: String
        var confidence: Double?
        var start: Double
        var end: Double
    }

    /// Recent output of one language's recognizer that is not committed yet.
    private struct Track {
        var finals: [Segment] = []
        var volatile: Segment?

        var segments: [Segment] { finals + (volatile.map { [$0] } ?? []) }
        var text: String { Self.join(segments) }
        var finalText: String { Self.join(finals) }
        var isEmpty: Bool { text.isEmpty }

        static func join(_ segments: [Segment]) -> String {
            segments.map(\.text).filter { !$0.isEmpty }.joined(separator: " ")
        }
    }

    private func handle(_ event: TranscriptEvent) {
        guard phase == .listening else { return }
        let middle = (event.start + event.end) / 2
        // The losing recognizer often finishes late; drop results for audio we already used.
        if middle.isFinite, middle < committedUntil { return }

        let segment = Segment(
            text: event.text.trimmingCharacters(in: .whitespacesAndNewlines),
            confidence: event.confidence,
            start: event.start,
            end: event.end
        )
        var track = tracks[event.languageID, default: Track()]
        if event.isFinal {
            track.volatile = nil
            if !segment.text.isEmpty { track.finals.append(segment) }
        } else {
            track.volatile = segment.text.isEmpty ? nil : segment
        }
        tracks[event.languageID] = track

        updateLive()
        scheduleCommit()
    }

    /// The language whose recognizer currently explains the audio best.
    private func leader() -> String? {
        let candidates = tracks.filter { !$0.value.isEmpty }
        guard candidates.count > 1 else { return candidates.first?.key }
        return candidates.max { score($0.key, $0.value) < score($1.key, $1.value) }?.key
    }

    /// Mostly the recognizer's own confidence, plus whether the text reads like that language.
    /// A recognizer listening to the wrong language produces low-confidence guesses.
    private func score(_ languageID: String, _ track: Track) -> Double {
        var weighted = 0.0
        var total = 0.0
        for segment in track.segments {
            guard let confidence = segment.confidence else { continue }
            let length = Double(segment.text.count)
            weighted += confidence * length
            total += length
        }
        let confidence = total > 0 ? weighted / total : 0.5

        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [top.nlLanguage, bottom.nlLanguage]
        recognizer.processString(track.text)
        let ownLanguage = languageID == top.id ? top.nlLanguage : bottom.nlLanguage
        let plausibility = recognizer.languageHypotheses(withMaximum: 2)[ownLanguage] ?? 0

        // Small bias towards the current speaker so the live text doesn't flicker sides.
        let stickiness = live?.sourceID == languageID ? 0.04 : 0
        return 0.7 * confidence + 0.3 * plausibility + stickiness
    }

    private func updateLive() {
        guard let speaker = leader(), let track = tracks[speaker] else {
            if live != nil {
                live = nil
                liveTranslationPending = false
            }
            return
        }
        if var current = live, current.sourceID == speaker {
            guard current.original != track.text else { return }
            current.original = track.text
            live = current
        } else {
            live = Turn(sourceID: speaker, original: track.text, translation: "", isLive: true)
        }
        requestLiveTranslation()
    }

    /// Commits quickly once both recognizers have finalized, or after a longer pause if one
    /// of them keeps a volatile result hanging.
    private func scheduleCommit() {
        commitTask?.cancel()
        let settled = isSettled
        commitTask = Task { [weak self] in
            try? await Task.sleep(for: settled ? .milliseconds(350) : .milliseconds(1500))
            guard !Task.isCancelled else { return }
            self?.commit(force: !settled)
        }
    }

    private var isSettled: Bool {
        tracks.values.allSatisfy { $0.volatile == nil } && tracks.values.contains { !$0.finals.isEmpty }
    }

    /// Moves the leader's finalized text into the conversation.
    private func commit(force: Bool) {
        guard force || isSettled, let speaker = leader(), var track = tracks[speaker], !track.finals.isEmpty else {
            return
        }
        let text = track.finalText
        let end = track.finals.map(\.end).filter(\.isFinite).max() ?? committedUntil
        committedUntil = max(committedUntil, end)

        let carried = live?.sourceID == speaker ? live : nil
        let turn = Turn(
            id: carried?.id ?? UUID(),
            sourceID: speaker,
            original: text,
            translation: carried?.translation ?? "",
            isLive: false
        )
        turns.append(turn)

        track.finals = []
        tracks[speaker] = track
        for (id, other) in tracks where id != speaker {
            var pruned = other
            pruned.finals.removeAll { ($0.start + $0.end) / 2 < committedUntil }
            if let volatile = pruned.volatile, (volatile.start + volatile.end) / 2 < committedUntil {
                pruned.volatile = nil
            }
            tracks[id] = pruned
        }

        live = nil
        updateLive()
        translateTurn(id: turn.id)
    }

    private func resetTracks() {
        commitTask?.cancel()
        tracks = [:]
        committedUntil = 0
        live = nil
    }

    // MARK: - Translation

    private func direction(for sourceID: String) -> (source: AppLanguage, target: AppLanguage) {
        sourceID == top.id ? (top, bottom) : (bottom, top)
    }

    /// Keeps at most one live translation in flight; always translates the newest text.
    private func requestLiveTranslation() {
        guard liveTranslationTask == nil else {
            liveTranslationPending = true
            return
        }
        liveTranslationTask = Task { [weak self] in
            guard let self else { return }
            repeat {
                liveTranslationPending = false
                guard let snapshot = live else { break }
                let languages = direction(for: snapshot.sourceID)
                if let translated = try? await translator.translate(
                    snapshot.original, from: languages.source, to: languages.target
                ),
                   var current = live, current.id == snapshot.id {
                    current.translation = translated
                    live = current
                }
            } while liveTranslationPending
            liveTranslationTask = nil
        }
    }

    private func translateTurn(id: UUID) {
        guard let turn = turns.first(where: { $0.id == id }) else { return }
        let languages = direction(for: turn.sourceID)
        Task {
            guard let translated = try? await translator.translate(
                turn.original, from: languages.source, to: languages.target
            ),
                  let index = turns.firstIndex(where: { $0.id == id }) else { return }
            turns[index].translation = translated
        }
    }
}
