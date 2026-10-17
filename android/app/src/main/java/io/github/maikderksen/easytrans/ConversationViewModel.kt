package io.github.maikderksen.easytrans

import android.app.Application
import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Keeps the translated conversation for both sides. Each utterance is attributed to the
 * language the recognizer detected; it is shown, translated, on the other side.
 */
class ConversationViewModel(application: Application) : AndroidViewModel(application) {

    sealed interface Phase {
        data object Idle : Phase
        data class Preparing(val message: String) : Phase
        data object Listening : Phase
        data object Paused : Phase
        data class Failed(val message: String) : Phase
    }

    data class Turn(
        val id: Long,
        /** Tag of the language the speaker used. */
        val source: String,
        val original: String,
        val translation: String,
        /** Still being spoken; text and translation may change. */
        val isLive: Boolean,
    )

    private val prefs = application.getSharedPreferences("easytrans", Context.MODE_PRIVATE)

    var top by mutableStateOf(AppLanguage.withTag(prefs.getString("top", null)) ?: AppLanguage("de-DE"))
        private set
    var bottom by mutableStateOf(AppLanguage.withTag(prefs.getString("bottom", null)) ?: AppLanguage("es-ES"))
        private set
    var phase by mutableStateOf<Phase>(Phase.Idle)
        private set
    var live by mutableStateOf<Turn?>(null)
        private set
    val turns = mutableStateListOf<Turn>()

    private val translator = Translator()
    private val engine = SpeechEngine(application, object : SpeechEngine.Listener {
        override fun onPartial(text: String, languageTag: String?) = handlePartial(text, languageTag)
        override fun onFinal(text: String, languageTag: String?) = handleFinal(text, languageTag)
        override fun onFailure(message: String) {
            phase = Phase.Failed(message)
        }
        override fun onNotice(message: String) {
            notice = message
            noticeTimeout?.cancel()
            noticeTimeout = viewModelScope.launch {
                delay(6000)
                notice = null
            }
        }
    })

    /** Short status shown while listening, e.g. while language packs download. */
    var notice by mutableStateOf<String?>(null)
        private set
    private var noticeTimeout: Job? = null

    private var nextID = 0L
    private var preparation: Job? = null
    private var liveTranslation: Job? = null
    private var liveTranslationPending = false

    fun language(side: Side) = if (side == Side.Top) top else bottom

    /** What [side] reads: everything the other side said, translated, oldest first. */
    fun items(side: Side): List<Turn> {
        val reader = language(side).tag
        return turns.filter { it.source != reader } + listOfNotNull(live?.takeIf { it.source != reader })
    }

    // Lifecycle

    fun start() {
        if (phase == Phase.Listening || preparation?.isActive == true) return
        if (!engine.isAvailable) {
            phase = Phase.Failed("Keine Spracherkennung auf diesem Gerät.")
            return
        }
        preparation = viewModelScope.launch {
            phase = Phase.Preparing("Lade Übersetzung …")
            try {
                translator.prepare(top, bottom)
            } catch (e: Exception) {
                phase = Phase.Failed("Übersetzung konnte nicht geladen werden: ${e.message}")
                return@launch
            }
            engine.start(listOf(top, bottom))
            phase = Phase.Listening
        }
    }

    fun pause() {
        preparation?.cancel()
        engine.stop()
        live = null
        if (phase != Phase.Idle) phase = Phase.Paused
    }

    fun toggleListening() {
        when (phase) {
            Phase.Listening -> pause()
            Phase.Paused, Phase.Idle, is Phase.Failed -> start()
            is Phase.Preparing -> Unit
        }
    }

    /** Tapping a side means "this person speaks next". Helps where detection is unavailable. */
    fun speakerHint(side: Side) {
        engine.primary = language(side)
    }

    // Settings

    fun swapSides() {
        val oldTop = top
        top = bottom
        bottom = oldTop
        save()
    }

    fun setLanguage(language: AppLanguage, side: Side) {
        if (language == language(side)) return
        val other = language(if (side == Side.Top) Side.Bottom else Side.Top)
        // Picking the other side's language just swaps the sides.
        if (language.code == other.code) {
            swapSides()
            return
        }
        if (side == Side.Top) top = language else bottom = language
        save()
        clear()
        translator.close()
        val wasActive = phase != Phase.Paused
        engine.stop()
        phase = Phase.Idle
        if (wasActive) start()
    }

    fun clear() {
        turns.clear()
        live = null
    }

    private fun save() {
        prefs.edit().putString("top", top.tag).putString("bottom", bottom.tag).apply()
    }

    // Recognition

    private fun speaker(languageTag: String?): AppLanguage {
        val code = languageTag?.let { java.util.Locale.forLanguageTag(it).language }
        return when (code) {
            top.code -> top
            bottom.code -> bottom
            else -> live?.let { current -> if (current.source == top.tag) top else bottom }
                ?: engine.primary ?: top
        }
    }

    private fun other(language: AppLanguage) = if (language == top) bottom else top

    private fun handlePartial(text: String, languageTag: String?) {
        if (phase != Phase.Listening) return
        val speaker = speaker(languageTag)
        val current = live
        live = if (current != null && current.source == speaker.tag) {
            if (current.original == text) return
            current.copy(original = text)
        } else {
            Turn(nextID++, speaker.tag, text, "", isLive = true)
        }
        requestLiveTranslation()
    }

    private fun handleFinal(text: String, languageTag: String?) {
        if (phase != Phase.Listening) return
        val carried = live
        live = null
        if (text.isEmpty()) return
        val speaker = speaker(languageTag)
        val turn = Turn(
            id = carried?.takeIf { it.source == speaker.tag }?.id ?: nextID++,
            source = speaker.tag,
            original = text,
            translation = carried?.takeIf { it.source == speaker.tag }?.translation.orEmpty(),
            isLive = false,
        )
        turns += turn
        // Conversations alternate, so expect the other person next.
        engine.primary = other(speaker)
        translateTurn(turn)
    }

    /** Keeps at most one live translation in flight; always translates the newest text. */
    private fun requestLiveTranslation() {
        if (liveTranslation?.isActive == true) {
            liveTranslationPending = true
            return
        }
        liveTranslation = viewModelScope.launch {
            do {
                liveTranslationPending = false
                val snapshot = live ?: break
                val source = if (snapshot.source == top.tag) top else bottom
                val translated = runCatching { translator.translate(snapshot.original, source, other(source)) }
                    .getOrNull() ?: continue
                val current = live
                if (current != null && current.id == snapshot.id) {
                    live = current.copy(translation = translated)
                } else {
                    // The utterance was committed meanwhile; give the turn this text until the
                    // final translation arrives.
                    val index = turns.indexOfFirst { it.id == snapshot.id }
                    if (index >= 0 && turns[index].translation.isEmpty()) {
                        turns[index] = turns[index].copy(translation = translated)
                    }
                }
            } while (liveTranslationPending)
        }
    }

    private fun translateTurn(turn: Turn) {
        val source = if (turn.source == top.tag) top else bottom
        val target = other(source)
        viewModelScope.launch {
            val translated = runCatching { translator.translate(turn.original, source, target) }
                .getOrNull() ?: return@launch
            val index = turns.indexOfFirst { it.id == turn.id }
            if (index >= 0) turns[index] = turns[index].copy(translation = translated)
        }
    }

    override fun onCleared() {
        engine.stop()
        translator.close()
    }
}
