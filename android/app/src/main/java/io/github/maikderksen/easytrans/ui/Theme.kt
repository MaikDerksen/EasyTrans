package io.github.maikderksen.easytrans.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color

/** iOS-like system colors: plain black/white with label-style greys. */
@Immutable
data class Palette(
    val background: Color,
    val primary: Color,
    val secondary: Color,
    val tertiary: Color,
    val glassFill: Color,
    val glassEdge: Color,
    val glassShadow: Color,
)

private val Light = Palette(
    background = Color.White,
    primary = Color.Black,
    secondary = Color(0x993C3C43),
    tertiary = Color(0x4D3C3C43),
    glassFill = Color(0xB8F7F7F9),
    glassEdge = Color(0xE6FFFFFF),
    glassShadow = Color(0x26000000),
)

private val Dark = Palette(
    background = Color.Black,
    primary = Color.White,
    secondary = Color(0x99EBEBF5),
    tertiary = Color(0x4DEBEBF5),
    glassFill = Color(0x733C3C43),
    glassEdge = Color(0x2EFFFFFF),
    glassShadow = Color(0x80000000),
)

val LocalPalette = staticCompositionLocalOf { Light }

@Composable
fun EasyTransTheme(content: @Composable () -> Unit) {
    val dark = isSystemInDarkTheme()
    val palette = if (dark) Dark else Light
    MaterialTheme(
        colorScheme = if (dark) {
            darkColorScheme(background = palette.background, surface = Color(0xFF1C1C1E), onSurface = palette.primary)
        } else {
            lightColorScheme(background = palette.background, surface = Color(0xFFF2F2F7), onSurface = palette.primary)
        },
    ) {
        CompositionLocalProvider(LocalPalette provides palette, content = content)
    }
}
