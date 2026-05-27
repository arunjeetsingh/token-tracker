package studio.maximumimpact.tokencounter

import androidx.compose.runtime.Composable
import studio.maximumimpact.tokencounter.features.dashboard.DashboardScreen
import studio.maximumimpact.tokencounter.ui.theme.TokenCounterTheme

/**
 * Root composable. Wraps the app in [TokenCounterTheme] and renders the
 * top-level destination. We will route between multiple screens here once
 * onboarding / settings exist; for v1 this just shows the dashboard.
 */
@Composable
fun TokenCounterApp() {
    TokenCounterTheme {
        DashboardScreen()
    }
}
