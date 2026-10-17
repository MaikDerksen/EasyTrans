import Foundation
import NaturalLanguage

/// A language one side of the conversation speaks and reads.
struct AppLanguage: Identifiable, Hashable, Sendable {
    /// BCP 47 identifier, e.g. "de-DE".
    let id: String

    var locale: Locale { Locale(identifier: id) }
    var language: Locale.Language { Locale.Language(identifier: id) }
    var code: String { locale.language.languageCode?.identifier ?? id }

    /// Native language name without region, e.g. "Deutsch", "Español".
    var shortName: String {
        let name = locale.localizedString(forLanguageCode: code) ?? id
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    /// Native name, with region when the language is offered in several variants.
    var fullName: String {
        guard Self.all.filter({ $0.code == code }).count > 1,
              let name = locale.localizedString(forIdentifier: id) else { return shortName }
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    var nlLanguage: NLLanguage {
        code == "zh" ? .simplifiedChinese : NLLanguage(rawValue: code)
    }

    /// Shown on an empty side, in that side's language.
    var listeningHint: String {
        switch code {
        case "de": "Ich höre zu …"
        case "es": "Te escucho …"
        case "fr": "J’écoute …"
        case "it": "Ti ascolto …"
        case "pt": "Estou ouvindo …"
        case "ja": "聞いています…"
        case "ko": "듣고 있어요…"
        case "zh": "正在聆听…"
        default: "Listening …"
        }
    }

    static let all: [AppLanguage] = [
        "de-DE", "en-US", "en-GB", "es-ES", "es-MX", "fr-FR", "it-IT",
        "pt-BR", "pt-PT", "ja-JP", "ko-KR", "zh-CN",
    ].map(AppLanguage.init(id:))

    static func with(id: String) -> AppLanguage? {
        all.first { $0.id == id }
    }
}

enum Side: CaseIterable {
    case top, bottom
}
