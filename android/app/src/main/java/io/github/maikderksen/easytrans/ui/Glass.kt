package io.github.maikderksen.easytrans.ui

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * Stand-in for iOS Liquid Glass: a translucent fill, a bright top rim fading downwards, and a
 * soft shadow. Presses shrink slightly like interactive glass.
 */
@Composable
fun Modifier.glass(shape: Shape, interaction: MutableInteractionSource? = null): Modifier {
    val palette = LocalPalette.current
    val pressed by (interaction ?: remember { MutableInteractionSource() }).collectIsPressedAsState()
    return this
        .scale(if (pressed) 0.94f else 1f)
        .shadow(14.dp, shape, ambientColor = palette.glassShadow, spotColor = palette.glassShadow)
        .clip(shape)
        .background(palette.glassFill)
        .background(Brush.verticalGradient(listOf(palette.glassEdge.copy(alpha = 0.35f), Color.Transparent)))
        .border(1.dp, Brush.verticalGradient(listOf(palette.glassEdge, palette.glassEdge.copy(alpha = 0.08f))), shape)
}

/** Counter-clockwise arrow, like SF Symbols "arrow.counterclockwise". */
@Composable
fun ResetIcon(color: Color, size: Dp = 20.dp) {
    Canvas(Modifier.size(size)) {
        val stroke = this.size.width * 0.1f
        val inset = stroke / 2 + this.size.width * 0.08f
        drawArc(
            color = color,
            startAngle = -60f,
            sweepAngle = 300f,
            useCenter = false,
            topLeft = Offset(inset, inset),
            size = Size(this.size.width - 2 * inset, this.size.height - 2 * inset),
            style = Stroke(stroke, cap = StrokeCap.Round),
        )
        val tip = Offset(this.size.width * 0.12f, this.size.height * 0.08f)
        val path = Path().apply {
            moveTo(tip.x, tip.y)
            lineTo(tip.x + this@Canvas.size.width * 0.34f, tip.y + this@Canvas.size.height * 0.06f)
            lineTo(tip.x + this@Canvas.size.width * 0.06f, tip.y + this@Canvas.size.height * 0.34f)
            close()
        }
        drawPath(path, color)
    }
}

/** Up and down arrows side by side, like "arrow.up.arrow.down". */
@Composable
fun SwapIcon(color: Color, size: Dp = 16.dp) {
    Canvas(Modifier.size(size)) {
        val w = this.size.width
        val h = this.size.height
        val stroke = Stroke(w * 0.11f, cap = StrokeCap.Round)
        fun arrow(x: Float, up: Boolean) {
            val tipY = if (up) h * 0.08f else h * 0.92f
            val tailY = if (up) h * 0.92f else h * 0.08f
            val head = if (up) h * 0.22f else -h * 0.22f
            val path = Path().apply {
                moveTo(x, tailY); lineTo(x, tipY)
                moveTo(x - w * 0.18f, tipY + head); lineTo(x, tipY); lineTo(x + w * 0.18f, tipY + head)
            }
            drawPath(path, color, style = stroke)
        }
        arrow(w * 0.28f, up = true)
        arrow(w * 0.72f, up = false)
    }
}

/** Five bars; animated while listening, dimmed and still otherwise ("waveform"). */
@Composable
fun WaveformIcon(color: Color, active: Boolean, size: Dp = 22.dp) {
    val transition = rememberInfiniteTransition(label = "waveform")
    val phase by transition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(1000), RepeatMode.Restart),
        label = "phase",
    )
    val heights = listOf(0.3f, 0.65f, 1f, 0.55f, 0.3f)
    Canvas(Modifier.size(size)) {
        val barWidth = this.size.width / 9f
        heights.forEachIndexed { index, height ->
            val alpha = if (active) {
                val local = ((phase - index * 0.15f) % 1f + 1f) % 1f
                0.35f + 0.65f * (1f - kotlin.math.abs(local * 2f - 1f))
            } else {
                0.35f
            }
            val barHeight = this.size.height * height
            drawRoundRect(
                color = color.copy(alpha = alpha),
                topLeft = Offset(barWidth * (index * 2), (this.size.height - barHeight) / 2),
                size = Size(barWidth, barHeight),
                cornerRadius = CornerRadius(barWidth / 2),
            )
        }
    }
}
