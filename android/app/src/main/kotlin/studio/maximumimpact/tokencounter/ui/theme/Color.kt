package studio.maximumimpact.tokencounter.ui.theme

import androidx.compose.ui.graphics.Color

// Palette intentionally mirrors the iOS sibling app. See ADR-013.
// We do NOT use Material You / dynamic color — the visual language is locked
// to the same look as iOS so the two apps feel like the same product.
// iOS uses system semantic colors that auto-adapt to light/dark, so we define
// both a light and a dark scheme and follow the device setting.

// --- Light (iOS light appearance) ---

/** Near-black, matches iOS body/headline text in light mode. */
val InkPrimary = Color(0xFF0A0A0A)

/** Soft gray for secondary copy (e.g. "~$X estimated for today"). */
val InkSecondary = Color(0xFF8E8E93)

/** White app background. */
val SurfaceLight = Color(0xFFFFFFFF)

// --- Dark (iOS dark appearance) ---

/** True black background, matches iOS `systemBackground` in dark mode. */
val SurfaceDark = Color(0xFF000000)

/** Slightly elevated dark surface (iOS `secondarySystemBackground`). */
val SurfaceDarkElevated = Color(0xFF1C1C1E)

/** White primary text in dark mode. */
val InkPrimaryDark = Color(0xFFFFFFFF)

/** Secondary gray reads well on both light and dark (iOS systemGray). */
val InkSecondaryDark = Color(0xFF8E8E93)

// --- Shared accent ---

/** iOS system blue. Used for accents/links/CTAs in both modes. */
val AccentBlue = Color(0xFF007AFF)

/** Always-dark splash background, matches the iOS launch screen. */
val SplashBackground = Color(0xFF12141A)
