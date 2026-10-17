package io.github.maikderksen.easytrans.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.maikderksen.easytrans.AppLanguage
import io.github.maikderksen.easytrans.ConversationViewModel
import io.github.maikderksen.easytrans.ConversationViewModel.Phase
import io.github.maikderksen.easytrans.Side

@Composable
fun ConversationScreen(model: ConversationViewModel) {
    val palette = LocalPalette.current
    Column(
        Modifier
            .fillMaxSize()
            .background(palette.background)
            .safeDrawingPadding()
    ) {
        // Faces the person across the table.
        TranscriptPane(
            items = model.items(Side.Top),
            language = model.top,
            onTap = { model.speakerHint(Side.Top) },
            modifier = Modifier.weight(1f).rotate(180f),
        )
        ControlBar(model)
        TranscriptPane(
            items = model.items(Side.Bottom),
            language = model.bottom,
            onTap = { model.speakerHint(Side.Bottom) },
            modifier = Modifier.weight(1f),
        )
    }
}

/** Plain text, newest at the bottom (towards the middle of the phone). */
@Composable
private fun TranscriptPane(
    items: List<ConversationViewModel.Turn>,
    language: AppLanguage,
    onTap: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = LocalPalette.current
    Box(
        modifier
            .fillMaxWidth()
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, onClick = onTap)
    ) {
        if (items.isEmpty()) {
            Text(
                language.listeningHint,
                color = palette.tertiary,
                fontSize = 20.sp,
                modifier = Modifier.align(Alignment.Center),
            )
        }
        // Reversed so the newest line sits at the bottom and new lines push older ones up.
        LazyColumn(
            reverseLayout = true,
            verticalArrangement = Arrangement.spacedBy(22.dp, Alignment.Bottom),
            contentPadding = PaddingValues(horizontal = 28.dp, vertical = 24.dp),
            modifier = Modifier.fillMaxSize(),
        ) {
            val newest = items.lastOrNull()?.id
            items(items.asReversed(), key = { it.id }) { item ->
                val isNewest = item.id == newest
                val alpha by animateFloatAsState(if (item.isLive) 0.6f else 1f, label = "live")
                Text(
                    text = item.translation.ifEmpty { "…" },
                    color = if (isNewest) palette.primary else palette.secondary,
                    fontSize = if (isNewest) 28.sp else 20.sp,
                    lineHeight = if (isNewest) 34.sp else 26.sp,
                    fontWeight = if (isNewest) FontWeight.SemiBold else FontWeight.Normal,
                    modifier = Modifier
                        .fillMaxWidth()
                        .alpha(alpha)
                        .animateContentSize()
                        .animateItem(),
                )
            }
        }
    }
}

/** The only chrome: reset, language pair with swap, and listening state. */
@Composable
private fun ControlBar(model: ConversationViewModel) {
    val palette = LocalPalette.current
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier.fillMaxWidth().padding(vertical = 10.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            GlassCircle(onClick = model::clear) { ResetIcon(palette.primary) }

            val capsuleInteraction = remember { MutableInteractionSource() }
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .height(48.dp)
                    .glass(RoundedCornerShape(24.dp), capsuleInteraction)
                    .padding(horizontal = 12.dp),
            ) {
                LanguageMenu(model, Side.Top)
                Box(
                    contentAlignment = Alignment.Center,
                    modifier = Modifier
                        .width(32.dp)
                        .height(48.dp)
                        .clickable(interactionSource = capsuleInteraction, indication = null, onClick = model::swapSides),
                ) { SwapIcon(palette.primary) }
                LanguageMenu(model, Side.Bottom)
            }

            GlassCircle(onClick = model::toggleListening) {
                when (model.phase) {
                    Phase.Listening -> WaveformIcon(palette.primary, active = true)
                    is Phase.Preparing -> CircularProgressIndicator(
                        color = palette.primary,
                        strokeWidth = 2.dp,
                        modifier = Modifier.size(18.dp),
                    )
                    is Phase.Failed -> Text("!", color = palette.primary, fontSize = 20.sp, fontWeight = FontWeight.Bold)
                    Phase.Paused, Phase.Idle -> WaveformIcon(palette.primary, active = false)
                }
            }
        }

        val status = when (val phase = model.phase) {
            is Phase.Preparing -> phase.message
            is Phase.Failed -> phase.message
            Phase.Paused -> "Pausiert"
            Phase.Listening -> model.notice
            Phase.Idle -> null
        }
        AnimatedVisibility(visible = status != null, enter = fadeIn(), exit = fadeOut()) {
            Text(
                status.orEmpty(),
                color = palette.secondary,
                fontSize = 13.sp,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(top = 8.dp, start = 32.dp, end = 32.dp),
            )
        }
    }
}

@Composable
private fun GlassCircle(onClick: () -> Unit, content: @Composable () -> Unit) {
    val interaction = remember { MutableInteractionSource() }
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .size(48.dp)
            .glass(CircleShape, interaction)
            .clickable(interactionSource = interaction, indication = null, onClick = onClick),
    ) { content() }
}

@Composable
private fun LanguageMenu(model: ConversationViewModel, side: Side) {
    val palette = LocalPalette.current
    var expanded by remember { mutableStateOf(false) }
    Box {
        Text(
            model.language(side).shortName,
            color = palette.primary,
            fontSize = 17.sp,
            fontWeight = FontWeight.Medium,
            modifier = Modifier
                .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { expanded = true }
                .padding(horizontal = 6.dp, vertical = 13.dp),
        )
        DropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false },
            shape = RoundedCornerShape(18.dp),
        ) {
            AppLanguage.all.forEach { language ->
                val selected = language == model.language(side)
                DropdownMenuItem(
                    text = { Text(language.fullName + if (selected) "  ✓" else "") },
                    onClick = {
                        expanded = false
                        model.setLanguage(language, side)
                    },
                )
            }
        }
    }
}
