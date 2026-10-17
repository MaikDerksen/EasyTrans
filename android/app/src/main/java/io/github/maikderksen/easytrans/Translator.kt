package io.github.maikderksen.easytrans

import com.google.mlkit.common.model.DownloadConditions
import com.google.mlkit.nl.translate.Translation
import com.google.mlkit.nl.translate.TranslatorOptions
import kotlinx.coroutines.tasks.await
import com.google.mlkit.nl.translate.Translator as MlKitTranslator

/** On-device translation (ML Kit) with one cached client per direction. */
class Translator {
    private val clients = mutableMapOf<String, MlKitTranslator>()

    private fun client(source: AppLanguage, target: AppLanguage): MlKitTranslator {
        val from = requireNotNull(source.translateCode) { "${source.shortName} wird nicht unterstützt" }
        val to = requireNotNull(target.translateCode) { "${target.shortName} wird nicht unterstützt" }
        return clients.getOrPut("$from>$to") {
            Translation.getClient(
                TranslatorOptions.Builder().setSourceLanguage(from).setTargetLanguage(to).build()
            )
        }
    }

    /** Downloads both languages' models (once, about 30 MB each). */
    suspend fun prepare(a: AppLanguage, b: AppLanguage) {
        val conditions = DownloadConditions.Builder().build()
        client(a, b).downloadModelIfNeeded(conditions).await()
        client(b, a).downloadModelIfNeeded(conditions).await()
    }

    suspend fun translate(text: String, source: AppLanguage, target: AppLanguage): String =
        client(source, target).translate(text).await()

    fun close() {
        clients.values.forEach { it.close() }
        clients.clear()
    }
}
