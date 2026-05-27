package studio.maximumimpact.tokencounter.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

/**
 * Type scale tuned to match the iOS dashboard's hero composition:
 *  - displayLarge → the giant MTD dollar figure (~64sp, bold).
 *  - titleLarge   → "TokenCounter" header.
 *  - bodyMedium   → secondary copy under the hero number.
 *
 * Uses the platform default font family. We may swap in a custom font
 * later, but for v1 staying on system fonts keeps the build small and
 * the rendering consistent with OEM expectations.
 */
val TokenCounterTypography = Typography(
    displayLarge = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Bold,
        fontSize = 64.sp,
        lineHeight = 72.sp,
        letterSpacing = (-1).sp
    ),
    titleLarge = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Bold,
        fontSize = 20.sp,
        lineHeight = 24.sp
    ),
    bodyMedium = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Normal,
        fontSize = 14.sp,
        lineHeight = 20.sp
    )
)
