package studio.maximumimpact.tokencounter.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable

/**
 * Single-mode (light) Material 3 theme tuned to match the iOS sibling.
 *
 * Per ADR-013 we deliberately do NOT use [dynamicLightColorScheme] /
 * Material You — visuals stay locked to the iOS palette so the two
 * platforms read as one product. We can revisit dynamic color post-launch.
 */
private val TokenCounterColorScheme = lightColorScheme(
    primary = AccentBlue,
    onPrimary = Surface,
    background = Surface,
    onBackground = InkPrimary,
    surface = Surface,
    onSurface = InkPrimary,
    onSurfaceVariant = InkSecondary
)

@Composable
fun TokenCounterTheme(
    content: @Composable () -> Unit
) {
    MaterialTheme(
        colorScheme = TokenCounterColorScheme,
        typography = TokenCounterTypography,
        content = content
    )
}
