package studio.maximumimpact.tokencounter.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

/**
 * Type scale mapped onto iOS Dynamic Type styles so the two apps read the
 * same. iOS uses the SF system font; we use the platform default (Roboto).
 *
 *  - displayLarge   → hero MTD figure (iOS .system(size:64,.semibold,.rounded))
 *  - headlineMedium → onboarding title (iOS .largeTitle.bold)
 *  - titleLarge     → "TokenCounter" wordmark / nav title (iOS large nav title)
 *  - titleMedium    → section + step + error headlines (iOS .headline)
 *  - bodyLarge      → model row name, body copy (iOS .body)
 *  - bodyMedium     → callout / secondary copy (iOS .callout/.subheadline)
 *  - bodySmall      → footnotes (iOS .footnote)
 *  - labelMedium    → captions (iOS .caption)
 *  - labelSmall     → small captions / DEMO pill (iOS .caption2)
 */
val TokenCounterTypography = Typography(
    displayLarge = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.SemiBold,
        fontSize = 64.sp,
        lineHeight = 72.sp,
        letterSpacing = (-1).sp
    ),
    headlineMedium = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Bold,
        fontSize = 34.sp,
        lineHeight = 40.sp
    ),
    titleLarge = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Bold,
        fontSize = 22.sp,
        lineHeight = 28.sp
    ),
    titleMedium = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.SemiBold,
        fontSize = 17.sp,
        lineHeight = 22.sp
    ),
    bodyLarge = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Normal,
        fontSize = 17.sp,
        lineHeight = 22.sp
    ),
    bodyMedium = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Normal,
        fontSize = 15.sp,
        lineHeight = 20.sp
    ),
    bodySmall = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Normal,
        fontSize = 13.sp,
        lineHeight = 18.sp
    ),
    labelMedium = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Normal,
        fontSize = 12.sp,
        lineHeight = 16.sp
    ),
    labelSmall = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Medium,
        fontSize = 11.sp,
        lineHeight = 14.sp
    )
)
