package studio.maximumimpact.tokencounter.ui.theme

import androidx.compose.ui.graphics.Color

// Palette intentionally mirrors the iOS sibling app. See ADR-013.
// We do NOT use Material You / dynamic color for v1 — the visual language
// is locked to the same look as iOS so the two apps feel like the same
// product across platforms.

/** Near-black, matches iOS body/headline text. */
val InkPrimary = Color(0xFF0A0A0A)

/** Soft gray for secondary copy (e.g. "~$X estimated for today"). */
val InkSecondary = Color(0xFF8E8E93)

/** White app background. */
val Surface = Color(0xFFFFFFFF)

/** iOS system blue. Used for accents/links/CTAs. */
val AccentBlue = Color(0xFF007AFF)
