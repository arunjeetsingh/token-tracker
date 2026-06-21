package studio.maximumimpact.tokencounter.features.dashboard

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import studio.maximumimpact.tokencounter.core.DemoData
import studio.maximumimpact.tokencounter.credentials.AnthropicKeyValidation
import studio.maximumimpact.tokencounter.credentials.CredentialStore
import studio.maximumimpact.tokencounter.data.DemoModeStore
import studio.maximumimpact.tokencounter.data.NotificationPrefsStore
import studio.maximumimpact.tokencounter.data.ReportCache
import studio.maximumimpact.tokencounter.data.SpendLimitStore
import studio.maximumimpact.tokencounter.providers.CostProvider
import studio.maximumimpact.tokencounter.providers.isProviderAuthError

/** Result of a [DashboardViewModel.connect] attempt, surfaced to onboarding. */
sealed interface ConnectResult {
    data object Success : ConnectResult
    data class Failure(val message: String) : ConnectResult
}

/**
 * Owns the whole-app [DashboardState] machine. Kotlin sibling of the iOS
 * `DashboardViewModel`. Orchestrates three collaborators — the cost API
 * ([CostProvider]), the Keystore-backed [CredentialStore], and the on-device
 * [ReportCache] — plus the persisted [DemoModeStore] for the review-key path.
 *
 * Transitions mirror iOS:
 *  - bootstrap: demo → snapshot; else load key → cached report then refresh;
 *    no key → onboarding.
 *  - connect: review key → demo; else whoami (verify before saving) → save key
 *    → fetch report; 401/403 or error → back to onboarding with a message.
 *  - refresh: keeps loaded data on screen (isRefreshing) while fetching; 401/403
 *    wipes the key and re-onboards; transient errors keep stale data.
 *  - disconnect: clears demo flag, cache, and key → onboarding.
 */
class DashboardViewModel(
    private val cost: CostProvider,
    private val credentialStore: CredentialStore,
    private val cache: ReportCache,
    private val demoMode: DemoModeStore,
    private val spendLimitStore: SpendLimitStore,
    private val notificationPrefs: NotificationPrefsStore
) : ViewModel() {

    private val _state = MutableStateFlow<DashboardState>(DashboardState.Loading)
    val state: StateFlow<DashboardState> = _state.asStateFlow()

    /** True while a real network refresh is in flight with data already on screen. */
    private val _isRefreshing = MutableStateFlow(false)
    val isRefreshing: StateFlow<Boolean> = _isRefreshing.asStateFlow()

    /** Masked form of the connected key, for the Settings sheet. */
    private val _maskedKey = MutableStateFlow<String?>(null)
    val maskedKey: StateFlow<String?> = _maskedKey.asStateFlow()

    /** Whether the canned demo data (review-key path) is being shown. */
    private val _isDemo = MutableStateFlow(false)
    val isDemo: StateFlow<Boolean> = _isDemo.asStateFlow()

    /**
     * The user's on-device monthly spend limit in cents (null = unset). Local
     * tracking target only — see [SpendLimitStore].
     */
    val spendLimitCents: StateFlow<Long?> =
        spendLimitStore.limitCents.stateIn(viewModelScope, SharingStarted.Eagerly, null)

    /**
     * Persist (or clear, when null) the local spend-limit target. Clearing the
     * limit also turns off the 90% alert: there's nothing to compare against, so
     * leaving it on would strand a scheduled background check and a
     * disabled-but-on switch in Settings. The host's `LaunchedEffect(alertEnabled)`
     * then cancels the worker.
     */
    fun setSpendLimit(cents: Long?) {
        viewModelScope.launch {
            spendLimitStore.setLimitCents(cents)
            if (cents == null) notificationPrefs.setAlertEnabled(false)
        }
    }

    /** Whether the user opted into the "90% of limit" spend alert. */
    val alertEnabled: StateFlow<Boolean> =
        notificationPrefs.alertEnabled.stateIn(viewModelScope, SharingStarted.Eagerly, false)

    /**
     * Persist the spend-alert opt-in. The UI only calls this with `true` after
     * notification permission is granted; scheduling the background check is
     * driven off this flag by the host.
     */
    fun setAlertEnabled(enabled: Boolean) {
        viewModelScope.launch { notificationPrefs.setAlertEnabled(enabled) }
    }

    fun bootstrap() {
        viewModelScope.launch {
            if (demoMode.isActive()) {
                loadDemo()
                return@launch
            }
            val key = credentialStore.load()
            if (key.isNullOrEmpty()) {
                _state.value = DashboardState.NeedsCredentials
                return@launch
            }
            _isDemo.value = false
            _maskedKey.value = AnthropicKeyValidation.masked(key)
            // Show cached data immediately so launch isn't an empty screen; the
            // refresh below replaces it (or, on auth failure, wipes it).
            cache.load()?.let { _state.value = DashboardState.Loaded(it.orgName, it.report) }
            refreshUsing(key)
        }
    }

    /**
     * Verifies the key against the API *before* persisting it, so we never
     * store junk we'd have to surface as a generic failure next launch.
     */
    suspend fun connect(rawKey: String): ConnectResult {
        val trimmed = rawKey.trim()
        if (trimmed.isEmpty()) {
            return ConnectResult.Failure("Paste your admin key to continue.")
        }
        // Review magic key: short-circuit before any network call or key write.
        if (DemoData.isReviewKey(trimmed)) {
            demoMode.setActive(true)
            loadDemo()
            return ConnectResult.Success
        }
        _state.value = DashboardState.Loading
        return try {
            val identity = cost.whoami(trimmed)
            // Real key authenticated — leave demo mode and persist the key.
            demoMode.setActive(false)
            _isDemo.value = false
            credentialStore.save(trimmed)
            _maskedKey.value = AnthropicKeyValidation.masked(trimmed)
            // The cost fetch: whoami already auth'd, so a *transient* failure
            // keeps the saved key and shows a dashboard error. But a 401/403
            // here means the key is bad after all — wipe it and route back to
            // onboarding, same as refreshUsing().
            try {
                val report = cost.monthToDateCost(trimmed)
                cache.save(report, identity.name)
                _state.value = DashboardState.Loaded(identity.name, report)
                ConnectResult.Success
            } catch (e: Exception) {
                if (e.isProviderAuthError()) {
                    wipeCredentialsAndReOnboard()
                    ConnectResult.Failure(REJECTED_KEY_MESSAGE)
                } else {
                    _state.value = DashboardState.Failed(e.message ?: "Couldn't load your usage.")
                    ConnectResult.Success
                }
            }
        } catch (e: Exception) {
            _state.value = DashboardState.NeedsCredentials
            if (e.isProviderAuthError()) {
                ConnectResult.Failure(REJECTED_KEY_MESSAGE)
            } else {
                ConnectResult.Failure(e.message ?: "Couldn't connect. Check your connection and try again.")
            }
        }
    }

    fun refresh() {
        viewModelScope.launch {
            if (demoMode.isActive()) {
                loadDemo()
                return@launch
            }
            val key = credentialStore.load()
            if (key == null) {
                _maskedKey.value = null
                _state.value = DashboardState.NeedsCredentials
                return@launch
            }
            refreshUsing(key)
        }
    }

    fun disconnect() {
        viewModelScope.launch {
            demoMode.setActive(false)
            cache.clear()
            credentialStore.delete()
            _isDemo.value = false
            _maskedKey.value = null
            _state.value = DashboardState.NeedsCredentials
        }
    }

    private suspend fun refreshUsing(key: String) {
        val hasSomethingToShow = _state.value is DashboardState.Loaded
        if (hasSomethingToShow) {
            _isRefreshing.value = true
        } else {
            _state.value = DashboardState.Loading
        }
        try {
            coroutineScope {
                val identity = async { cost.whoami(key) }
                val report = async { cost.monthToDateCost(key) }
                val org = identity.await()
                val mtd = report.await()
                _maskedKey.value = AnthropicKeyValidation.masked(key)
                cache.save(mtd, org.name)
                _isDemo.value = false
                _state.value = DashboardState.Loaded(org.name, mtd)
            }
        } catch (e: Exception) {
            if (e.isProviderAuthError()) {
                // Token went bad — wipe it (and the cache) and force re-onboarding.
                wipeCredentialsAndReOnboard()
            } else if (!hasSomethingToShow) {
                // Transient failure with nothing else to show.
                _state.value = DashboardState.Failed(e.message ?: "Couldn't load your usage.")
            }
            // else: keep the stale data on screen (user sees the "as of" time).
        } finally {
            _isRefreshing.value = false
        }
    }

    /** Clears the stored key, cache, and demo flag and returns to onboarding. */
    private suspend fun wipeCredentialsAndReOnboard() {
        credentialStore.delete()
        cache.clear()
        _isDemo.value = false
        _maskedKey.value = null
        _state.value = DashboardState.NeedsCredentials
    }

    private fun loadDemo() {
        val snapshot = DemoData.snapshot()
        _isDemo.value = true
        _maskedKey.value = AnthropicKeyValidation.masked(DemoData.REVIEW_KEY)
        _state.value = DashboardState.Loaded(snapshot.orgName, snapshot.report)
    }

    companion object {
        private const val REJECTED_KEY_MESSAGE =
            "Your provider rejected this key. Double-check that you copied the right " +
                "admin/project key and try again."

        /** Builds a factory wiring the live collaborators from app dependencies. */
        fun factory(
            cost: CostProvider,
            credentialStore: CredentialStore,
            cache: ReportCache,
            demoMode: DemoModeStore,
            spendLimitStore: SpendLimitStore,
            notificationPrefs: NotificationPrefsStore
        ): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                DashboardViewModel(cost, credentialStore, cache, demoMode, spendLimitStore, notificationPrefs)
            }
        }
    }
}
