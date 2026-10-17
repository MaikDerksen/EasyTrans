import Foundation
import XKit
import ArgumentParser
import Dependencies
import XUtils

/// Signs an app for a device that isn't connected to this machine. The device gets registered
/// with the Apple ID, and the signed ipa can be pushed by any installer (e.g. Sideloadly's
/// "normal install" mode) from another computer.
struct SignCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sign",
        abstract: "Sign an app/ipa for a device that isn't connected"
    )

    @Option(name: .shortAndLong, help: "UDID of the target device")
    var udid: String

    @Option(help: "Name to register the device under")
    var deviceName = "iPhone"

    @Option(name: .shortAndLong, help: "Where to write the signed .ipa")
    var output: String

    @Argument(help: "The .app or .ipa to sign")
    var path: String

    func run() async throws {
        let token = try AuthToken.saved()
        @Dependency(\.zipCompressor) var compressor

        let tempDir = try TemporaryDirectory(name: "sign")
        defer { withExtendedLifetime(tempDir) {} }
        let payload = tempDir.url.appendingPathComponent("Payload")
        let input = URL(fileURLWithPath: path)
        switch input.pathExtension {
        case "ipa":
            try await compressor.decompress(file: input, in: tempDir.url, progress: { _ in })
        case "app":
            try FileManager.default.createDirectory(at: payload, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: input, to: payload.appendingPathComponent(input.lastPathComponent))
        default:
            throw Console.Error("Expected an .app or .ipa, got \(input.lastPathComponent)")
        }
        guard let app = try FileManager.default
            .contentsOfDirectory(at: payload, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" })
        else {
            throw Console.Error("No .app found in Payload")
        }

        let installer = IntegratedInstaller(auth: token.authData(), delegate: XToolInstallerDelegate())
        do {
            defer { print() }
            let bundleID = try await installer.signInPlace(
                app: app,
                targetDevice: .init(udid: udid, name: deviceName)
            )
            print("\nSigned \(bundleID) for \(udid)")
        } catch let error as CancellationError {
            throw error
        } catch {
            print("\nError: \(error)")
            throw ExitCode.failure
        }

        let ipa = try await compressor.compress(directory: payload, progress: { _ in })
        let outputURL = URL(fileURLWithPath: output)
        try? FileManager.default.removeItem(at: outputURL)
        try FileManager.default.copyItem(at: ipa, to: outputURL)
        print("Wrote to \(outputURL.path)")
    }
}
