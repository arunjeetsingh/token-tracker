package studio.maximumimpact.tokencounter.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable

/**
 * Material 3 theme tuned to match the iOS sibling. Per ADR-013 we deliberately
 * do NOT use dynamic color / Material You — visuals stay locked to the iOS
 * palette so the two platforms read as one product.
 *
 * iOS relies on system semantic colors that adapt to light/dark; we mirror that
 * by following [isSystemInDarkTheme].
 */
private val LightColors = lightColorScheme(
    primary = AccentBlue,
    onPrimary = SurfaceLight,
    background = SurfaceLight,
    onBackground = InkPrimary,
    surface = SurfaceLight,
    onSurface = InkPrimary,
    surfaceVariant = SurfaceLight,
    onSurfaceVariant = InkSecondary
)

private val DarkColors = darkColorScheme(
    primary = AccentBlue,
    onPrimary = SurfaceLight,
    background = SurfaceDark,
    onBackground = InkPrimaryDark,
    surface = SurfaceDark,
    onSurface = InkPrimaryDark,
    surfaceVariant = SurfaceDarkElevated,
    onSurfaceVariant = InkSecondaryDark
)

@Composable
fun TokenCounterTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit
) {
    MaterialTheme(
        colorScheme = if (darkTheme) DarkColors else LightColors,
        typography = TokenCounterTypography,
        content = content
    )
}
