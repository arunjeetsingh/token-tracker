package studio.maximumimpact.tokencounter

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import studio.maximumimpact.tokencounter.core.DemoData
import studio.maximumimpact.tokencounter.features.dashboard.DashboardScreen
import studio.maximumimpact.tokencounter.features.dashboard.DashboardState
import studio.maximumimpact.tokencounter.features.onboarding.OnboardingScreen
import studio.maximumimpact.tokencounter.features.settings.SettingsSheet
import studio.maximumimpact.tokencounter.ui.theme.TokenCounterTheme

private const val APP_VERSION = "1.0"

/**
 * Root composable and the app's single state machine. Mirrors the iOS
 * `DashboardView` which drives the whole UI off one [DashboardState] enum:
 *
 *  - starts in [DashboardState.NeedsCredentials] → [OnboardingScreen]
 *  - "Save & Connect" briefly shows [DashboardState.Loading] then lands on
 *    [DashboardState.Loaded] with the canned demo report
 *  - the gear opens the [SettingsSheet]; "Disconnect" returns to onboarding
 *
 * There's no real data layer in this PR (see ADR-013) — every "load" just
 * resolves to [DemoData.snapshot].
 */
@Composable
fun TokenCounterApp() {
    TokenCounterTheme {
        var state by remember { mutableStateOf<DashboardState>(DashboardState.NeedsCredentials) }
        var connectedKey by remember { mutableStateOf<String?>(null) }
        var showSettings by remember { mutableStateOf(false) }

        fun loadDemo() {
            val snapshot = DemoData.snapshot()
            state = DashboardState.Loaded(snapshot.orgName, snapshot.report)
        }

        when (val current = state) {
            is DashboardState.Loading -> LoadingScreen()

            is DashboardState.NeedsCredentials -> OnboardingScreen(
                onConnect = { key ->
                    connectedKey = key
                    loadDemo()
                }
            )

            is DashboardState.Loaded -> DashboardScreen(
                orgName = current.orgName,
                report = current.report,
                isDemo = true,
                isRefreshing = false,
                onRefresh = { loadDemo() },
                onOpenSettings = { showSettings = true }
            )

            is DashboardState.Failed -> DashboardScreen(
                // No dedicated error screen in this UI-only port; loaded view
                // is the only rich screen. (Reserved for the data-layer PR.)
                orgName = "",
                report = DemoData.snapshot().report,
                isDemo = true,
                isRefreshing = false,
                onRefresh = { loadDemo() },
                onOpenSettings = { showSettings = true }
            )
        }

        if (showSettings) {
            SettingsSheet(
                orgName = (state as? DashboardState.Loaded)?.orgName ?: "Personal",
                maskedKey = maskKey(connectedKey),
                appVersion = APP_VERSION,
                onDisconnect = {
                    showSettings = false
                    connectedKey = null
                    state = DashboardState.NeedsCredentials
                },
                onDismiss = { showSettings = false }
            )
        }
    }
}

@Composable
private fun LoadingScreen() {
    Box(
        modifier = Modifier
            .fillMaxSize(),
        contentAlignment = Alignment.Center
    ) {
        CircularProgressIndicator(
            modifier = Modifier.size(40.dp),
            color = MaterialTheme.colorScheme.primary
        )
    }
}

/** "sk-ant-admin01-abcd…wxyz" → "sk-ant-a…wxyz". Null/short keys mask fully. */
private fun maskKey(key: String?): String {
    if (key.isNullOrBlank()) return "—"
    if (key.length <= 12) return "•".repeat(key.length)
    return key.take(8) + "…" + key.takeLast(4)
}
