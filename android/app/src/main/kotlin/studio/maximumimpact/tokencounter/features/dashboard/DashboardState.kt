package studio.maximumimpact.tokencounter.features.dashboard

import studio.maximumimpact.tokencounter.core.MtdCost
import studio.maximumimpact.tokencounter.providers.ProviderKind

/** One provider's contribution to a loaded dashboard. */
data class ProviderReport(
    val provider: ProviderKind,
    val orgName: String,
    val report: MtdCost
)

/**
 * Mirror of the iOS `DashboardView.DashboardState` enum. The whole app is a
 * single state machine driven off this value; [studio.maximumimpact.tokencounter.TokenCounterApp]
 * switches the rendered screen on the case.
 */
sealed interface DashboardState {
    data object Loading : DashboardState
    data object NeedsCredentials : DashboardState
    data class Loaded(
        val orgName: String,
        val report: MtdCost,
        val providerReports: List<ProviderReport> = emptyList(),
        val selectedProvider: ProviderKind? = null
    ) : DashboardState
    data class Failed(val message: String) : DashboardState
}
