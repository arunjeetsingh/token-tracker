package studio.maximumimpact.tokencounter

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.launch
import studio.maximumimpact.tokencounter.credentials.KeystoreCredentialStore
import studio.maximumimpact.tokencounter.data.DataStoreDemoModeStore
import studio.maximumimpact.tokencounter.data.DataStoreNotificationPrefsStore
import studio.maximumimpact.tokencounter.data.DataStoreReportCache
import studio.maximumimpact.tokencounter.data.DataStoreSpendLimitStore
import studio.maximumimpact.tokencounter.features.dashboard.ConnectResult
import studio.maximumimpact.tokencounter.features.dashboard.DashboardScreen
import studio.maximumimpact.tokencounter.features.dashboard.DashboardState
import studio.maximumimpact.tokencounter.features.dashboard.DashboardViewModel
import studio.maximumimpact.tokencounter.features.dashboard.ErrorView
import studio.maximumimpact.tokencounter.features.dashboard.SpendLimitDialog
import studio.maximumimpact.tokencounter.features.onboarding.OnboardingScreen
import studio.maximumimpact.tokencounter.features.settings.SettingsSheet
import studio.maximumimpact.tokencounter.notifications.SpendAlertScheduler
import studio.maximumimpact.tokencounter.providers.LiveCostProvider
import studio.maximumimpact.tokencounter.ui.theme.TokenCounterTheme

private const val APP_VERSION = "1.0"

/**
 * Root composable. Builds the live data-layer collaborators, hosts the
 * [DashboardViewModel], and renders the screen for the current
 * [DashboardState]. The whole app is driven off that single state machine
 * (mirrors the iOS `DashboardView`).
 */
@Composable
fun TokenCounterApp() {
    TokenCounterTheme {
        val context = LocalContext.current
        val factory = remember(context) {
            val app = context.applicationContext
            DashboardViewModel.factory(
                cost = LiveCostProvider(),
                credentialStore = KeystoreCredentialStore.create(app),
                cache = DataStoreReportCache.create(app),
                demoMode = DataStoreDemoModeStore.create(app),
                spendLimitStore = DataStoreSpendLimitStore.create(app),
                notificationPrefs = DataStoreNotificationPrefsStore.create(app)
            )
        }
        val viewModel: DashboardViewModel = viewModel(factory = factory)

        LaunchedEffect(Unit) { viewModel.bootstrap() }

        val state by viewModel.state.collectAsState()
        val isRefreshing by viewModel.isRefreshing.collectAsState()
        val isDemo by viewModel.isDemo.collectAsState()
        val maskedKey by viewModel.maskedKey.collectAsState()
        val spendLimitCents by viewModel.spendLimitCents.collectAsState()
        val alertEnabled by viewModel.alertEnabled.collectAsState()

        // Schedule / cancel the background spend-alert check to follow the opt-in.
        LaunchedEffect(alertEnabled) {
            val app = context.applicationContext
            if (alertEnabled) SpendAlertScheduler.enable(app) else SpendAlertScheduler.disable(app)
        }

        val scope = rememberCoroutineScope()
        var showSettings by remember { mutableStateOf(false) }
        var showLimitDialog by remember { mutableStateOf(false) }
        var isConnecting by remember { mutableStateOf(false) }
        var submitError by remember { mutableStateOf<String?>(null) }

        when (val current = state) {
            is DashboardState.Loading -> LoadingScreen()

            is DashboardState.NeedsCredentials -> OnboardingScreen(
                isConnecting = isConnecting,
                submitError = submitError,
                onConnect = { key ->
                    scope.launch {
                        isConnecting = true
                        submitError = null
                        val result = viewModel.connect(key)
                        isConnecting = false
                        if (result is ConnectResult.Failure) submitError = result.message
                    }
                }
            )

            is DashboardState.Loaded -> DashboardScreen(
                orgName = current.orgName,
                report = current.report,
                isDemo = isDemo,
                isRefreshing = isRefreshing,
                spendLimitCents = spendLimitCents,
                onAdjustLimit = { showLimitDialog = true },
                onRefresh = { viewModel.refresh() },
                onOpenSettings = { showSettings = true }
            )

            is DashboardState.Failed -> ErrorView(
                message = current.message,
                onRetry = { viewModel.refresh() },
                onDisconnect = { viewModel.disconnect() }
            )
        }

        if (showSettings && state is DashboardState.Loaded) {
            SettingsSheet(
                orgName = (state as DashboardState.Loaded).orgName,
                maskedKey = maskedKey ?: "—",
                appVersion = APP_VERSION,
                spendLimitCents = spendLimitCents,
                alertEnabled = alertEnabled,
                onEditLimit = {
                    showSettings = false
                    showLimitDialog = true
                },
                onAlertEnabledChange = { viewModel.setAlertEnabled(it) },
                onDisconnect = {
                    showSettings = false
                    viewModel.disconnect()
                },
                onDismiss = { showSettings = false }
            )
        }

        if (showLimitDialog) {
            SpendLimitDialog(
                currentCents = spendLimitCents,
                onConfirm = {
                    viewModel.setSpendLimit(it)
                    showLimitDialog = false
                },
                onClear = {
                    viewModel.setSpendLimit(null)
                    showLimitDialog = false
                },
                onDismiss = { showLimitDialog = false }
            )
        }
    }
}

@Composable
private fun LoadingScreen() {
    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center
    ) {
        CircularProgressIndicator(
            modifier = Modifier.size(40.dp),
            color = MaterialTheme.colorScheme.primary
        )
    }
}
