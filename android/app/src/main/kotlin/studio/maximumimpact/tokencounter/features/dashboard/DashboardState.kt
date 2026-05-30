package studio.maximumimpact.tokencounter.features.dashboard

import studio.maximumimpact.tokencounter.core.MtdCost

/**
 * Mirror of the iOS `DashboardView.DashboardState` enum. The whole app is a
 * single state machine driven off this value; [studio.maximumimpact.tokencounter.TokenCounterApp]
 * switches the rendered screen on the case.
 *
 *  - [Loading]          → spinner (initial / refreshing with no prior data)
 *  - [NeedsCredentials] → onboarding flow
 *  - [Loaded]           → the dashboard with a month-to-date report + org name
 *  - [Failed]           → error view with retry / disconnect
 */
sealed interface DashboardState {
    data object Loading : DashboardState
    data object NeedsCredentials : DashboardState
    data class Loaded(val orgName: String, val report: MtdCost) : DashboardState
    data class Failed(val message: String) : DashboardState
}
