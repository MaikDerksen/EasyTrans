package io.github.maikderksen.easytrans

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer

/**
 * Continuous listening on top of [SpeechRecognizer]. Android ends a session after each pause,
 * so the engine restarts it right away. The recognizer detects which of the two languages is
 * spoken and switches to it mid-utterance (Android 14+).
 */
class SpeechEngine(
    private val context: Context,
    private val listener: Listener,
) {
    interface Listener {
        /** [languageTag] is the detected language, or null if the recognizer gave none. */
        fun onPartial(text: String, languageTag: String?)
        fun onFinal(text: String, languageTag: String?)
        fun onFailure(message: String)
        /** Informational status while still listening. */
        fun onNotice(message: String)
    }

    private val handler = Handler(Looper.getMainLooper())
    private var recognizer: SpeechRecognizer? = null
    private var languages: List<AppLanguage> = emptyList()
    private var detectedTag: String? = null
    private var running = false
    /** Falls back to the online recognizer while on-device language packs are missing. */
    private var useOnDevice = SpeechRecognizer.isOnDeviceRecognitionAvailable(context)

    /** The language the next session starts in; detection switches away from it if needed. */
    var primary: AppLanguage? = null

    val isAvailable: Boolean
        get() = SpeechRecognizer.isRecognitionAvailable(context)

    fun start(languages: List<AppLanguage>) {
        this.languages = languages
        if (primary !in languages) primary = languages.first()
        running = true
        listen()
    }

    fun stop() {
        running = false
        handler.removeCallbacksAndMessages(null)
        recognizer?.cancel()
        recognizer?.destroy()
        recognizer = null
    }

    private fun listen() {
        if (!running) return
        val recognizer = recognizer ?: create().also { recognizer = it }
        detectedTag = null
        recognizer.startListening(intent(primary ?: languages.first()))
    }

    private fun intent(language: AppLanguage): Intent {
        val tags = ArrayList(languages.map { it.tag })
        return Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, language.tag)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, useOnDevice)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            putExtra(RecognizerIntent.EXTRA_ENABLE_LANGUAGE_DETECTION, true)
            putStringArrayListExtra(RecognizerIntent.EXTRA_LANGUAGE_DETECTION_ALLOWED_LANGUAGES, tags)
            putExtra(RecognizerIntent.EXTRA_ENABLE_LANGUAGE_SWITCH, RecognizerIntent.LANGUAGE_SWITCH_QUICK_RESPONSE)
            putStringArrayListExtra(RecognizerIntent.EXTRA_LANGUAGE_SWITCH_ALLOWED_LANGUAGES, tags)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 800L)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, 600L)
        }
    }

    /**
     * Asks the system to download the on-device packs for both languages, and keeps listening
     * with the online recognizer meanwhile. The next app start uses the packs.
     */
    private fun fallBackToOnline() {
        recognizer?.let { onDevice ->
            languages.forEach { onDevice.triggerModelDownload(intent(it)) }
            onDevice.destroy()
        }
        recognizer = null
        useOnDevice = false
        listener.onNotice("Lade Offline-Spracherkennung … bis dahin online.")
        restart(300)
    }

    private fun create(): SpeechRecognizer {
        val recognizer = if (useOnDevice) {
            SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
        } else {
            SpeechRecognizer.createSpeechRecognizer(context)
        }
        recognizer.setRecognitionListener(callbacks)
        return recognizer
    }

    private fun restart(delayMillis: Long = 0) {
        handler.removeCallbacksAndMessages(null)
        handler.postDelayed(::listen, delayMillis)
    }

    private fun Bundle.firstResult(): String? =
        getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()?.trim()

    private val callbacks = object : RecognitionListener {
        override fun onPartialResults(partialResults: Bundle) {
            val text = partialResults.firstResult().orEmpty()
            if (text.isNotEmpty()) listener.onPartial(text, detectedTag)
        }

        override fun onResults(results: Bundle) {
            listener.onFinal(results.firstResult().orEmpty(), detectedTag)
            restart()
        }

        override fun onLanguageDetection(results: Bundle) {
            val level = results.getInt(SpeechRecognizer.LANGUAGE_DETECTION_CONFIDENCE_LEVEL)
            if (level == SpeechRecognizer.LANGUAGE_DETECTION_CONFIDENCE_LEVEL_UNKNOWN) return
            results.getString(SpeechRecognizer.DETECTED_LANGUAGE)?.let { detectedTag = it }
        }

        override fun onError(error: Int) {
            when (error) {
                // Silence or nothing understood: just keep listening.
                SpeechRecognizer.ERROR_NO_MATCH,
                SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> {
                    listener.onFinal("", detectedTag)
                    restart()
                }
                SpeechRecognizer.ERROR_RECOGNIZER_BUSY,
                SpeechRecognizer.ERROR_SERVER_DISCONNECTED,
                SpeechRecognizer.ERROR_TOO_MANY_REQUESTS -> restart(400)
                SpeechRecognizer.ERROR_CLIENT -> {
                    recognizer?.destroy()
                    recognizer = null
                    restart(300)
                }
                SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> {
                    running = false
                    listener.onFailure("Kein Mikrofonzugriff. Bitte in den Einstellungen erlauben.")
                }
                SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED,
                SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE -> if (useOnDevice) {
                    fallBackToOnline()
                } else {
                    running = false
                    listener.onFailure("Diese Sprache wird von der Spracherkennung nicht unterstützt.")
                }
                else -> restart(500)
            }
        }

        override fun onReadyForSpeech(params: Bundle?) = Unit
        override fun onBeginningOfSpeech() = Unit
        override fun onRmsChanged(rmsdB: Float) = Unit
        override fun onBufferReceived(buffer: ByteArray?) = Unit
        override fun onEndOfSpeech() = Unit
        override fun onEvent(eventType: Int, params: Bundle?) = Unit
    }
}
