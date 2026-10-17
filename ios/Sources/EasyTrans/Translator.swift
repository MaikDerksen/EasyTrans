import Foundation
import Translation

/// On-device translation with one cached session per direction.
@MainActor
final class Translator {
    private var sessions: [String: TranslationSession] = [:]

    func translate(_ text: String, from source: AppLanguage, to target: AppLanguage) async throws -> String {
        let key = "\(source.id)>\(target.id)"
        let session: TranslationSession
        if let cached = sessions[key] {
            session = cached
        } else {
            session = TranslationSession(installedSource: source.language, target: target.language)
            sessions[key] = session
        }
        return try await session.translate(text).targetText
    }

    func reset() {
        sessions = [:]
    }
}
