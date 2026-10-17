package io.github.maikderksen.easytrans

import com.google.mlkit.nl.translate.TranslateLanguage
import java.util.Locale

/** A language one side of the conversation speaks and reads. */
data class AppLanguage(val tag: String) {
    val locale: Locale = Locale.forLanguageTag(tag)
    val code: String = locale.language

    /** Native language name without region, e.g. "Deutsch", "Español". */
    val shortName: String
        get() = locale.getDisplayLanguage(locale).replaceFirstChar { it.titlecase(locale) }

    /** Native name, with region when the language is offered in several variants. */
    val fullName: String
        get() = if (all.count { it.code == code } > 1) {
            locale.getDisplayName(locale).replaceFirstChar { it.titlecase(locale) }
        } else {
            shortName
        }

    /** ML Kit translation code, e.g. "de". */
    val translateCode: String? = TranslateLanguage.fromLanguageTag(code)

    /** Shown on an empty side, in that side's language. */
    val listeningHint: String
        get() = when (code) {
            "de" -> "Ich höre zu …"
            "es" -> "Te escucho …"
            "fr" -> "J’écoute …"
            "it" -> "Ti ascolto …"
            "pt" -> "Estou ouvindo …"
            "ja" -> "聞いています…"
            "ko" -> "듣고 있어요…"
            "zh" -> "正在聆听…"
            else -> "Listening …"
        }

    companion object {
        val all: List<AppLanguage> = listOf(
            "de-DE", "en-US", "en-GB", "es-ES", "es-MX", "fr-FR", "it-IT",
            "pt-BR", "pt-PT", "ja-JP", "ko-KR", "zh-CN",
        ).map(::AppLanguage)

        fun withTag(tag: String?): AppLanguage? = all.firstOrNull { it.tag == tag }
    }
}

enum class Side { Top, Bottom }
