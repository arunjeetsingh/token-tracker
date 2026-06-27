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
import studio.maximumimpact.tokencounter.core.combineMtdCosts
import studio.maximumimpact.tokencounter.credentials.AnthropicKeyValidation
import studio.maximumimpact.tokencounter.credentials.CredentialStore
import studio.maximumimpact.tokencounter.data.CachedReport
import studio.maximumimpact.tokencounter.data.DemoModeStore
import studio.maximumimpact.tokencounter.data.NotificationPrefsStore
import studio.maximumimpact.tokencounter.data.ReportCache
import studio.maximumimpact.tokencounter.data.SpendLimitStore
import studio.maximumimpact.tokencounter.providers.CostProvider
import studio.maximumimpact.tokencounter.providers.ProviderKind
import studio.maximumimpact.tokencounter.providers.isProviderAuthError
import studio.maximumimpact.tokencounter.providers.providerKindFor

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

    /** Masked form of the connected key(s), for the Settings sheet. */
    private val _maskedKey = MutableStateFlow<String?>(null)
    val maskedKey: StateFlow<String?> = _maskedKey.asStateFlow()

    /** Whether the canned demo data (review-key path) is being shown. */
    private val _isDemo = MutableStateFlow(false)
    val isDemo: StateFlow<Boolean> = _isDemo.asStateFlow()

    val spendLimitCents: StateFlow<Long?> =
        spendLimitStore.limitCents.stateIn(viewModelScope, SharingStarted.Eagerly, null)

    fun setSpendLimit(cents: Long?) {
        viewModelScope.launch {
            spendLimitStore.setLimitCents(cents)
            if (cents == null) notificationPrefs.setAlertEnabled(false)
        }
    }

    val alertEnabled: StateFlow<Boolean> =
        notificationPrefs.alertEnabled.stateIn(viewModelScope, SharingStarted.Eagerly, false)

    fun setAlertEnabled(enabled: Boolean) {
        viewModelScope.launch { notificationPrefs.setAlertEnabled(enabled) }
    }

    fun bootstrap() {
        viewModelScope.launch {
            if (demoMode.isActive()) {
                loadDemo()
                return@launch
            }
            val keys = credentialStore.loadAll()
            if (keys.isEmpty()) {
                _maskedKey.value = null
                _state.value = DashboardState.NeedsCredentials
                return@launch
            }
            _isDemo.value = false
            _maskedKey.value = maskedKeys(keys)
            val cachedReports = cache.loadAll().toProviderReports()
            if (cachedReports.isNotEmpty()) {
                _state.value = loadedState(cachedReports, selectedProvider())
            } else {
                cache.load()?.let { _state.value = DashboardState.Loaded(it.orgName, it.report) }
            }
            refreshUsing(keys)
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
        if (DemoData.isReviewKey(trimmed)) {
            demoMode.setActive(true)
            loadDemo()
            return ConnectResult.Success
        }
        _state.value = DashboardState.Loading
        return verifyAndSave(trimmed, preserveExistingOnFailure = false)
    }

    /**
     * Verifies and saves a replacement/additional key without tearing down the
     * current dashboard first. Used by Settings' "Add or replace API key" flow.
     */
    suspend fun replaceCredential(rawKey: String): ConnectResult {
        val trimmed = rawKey.trim()
        if (trimmed.isEmpty()) {
            return ConnectResult.Failure("Paste your admin key to continue.")
        }
        if (DemoData.isReviewKey(trimmed)) {
            demoMode.setActive(true)
            loadDemo()
            return ConnectResult.Success
        }

        val hadLoadedDashboard = _state.value is DashboardState.Loaded
        if (hadLoadedDashboard) _isRefreshing.value = true
        return try {
            verifyAndSave(trimmed, preserveExistingOnFailure = true)
        } finally {
            if (hadLoadedDashboard) _isRefreshing.value = false
        }
    }

    fun refresh() {
        viewModelScope.launch {
            if (demoMode.isActive()) {
                loadDemo()
                return@launch
            }
            val keys = credentialStore.loadAll()
            if (keys.isEmpty()) {
                _maskedKey.value = null
                _state.value = DashboardState.NeedsCredentials
                return@launch
            }
            refreshUsing(keys)
        }
    }

    fun selectProviderFilter(provider: ProviderKind?) {
        val loaded = _state.value as? DashboardState.Loaded ?: return
        _state.value = loadedState(loaded.providerReports, provider)
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

    private suspend fun verifyAndSave(trimmed: String, preserveExistingOnFailure: Boolean): ConnectResult {
        val provider = providerKindFor(trimmed)
        return try {
            val identity = cost.whoami(trimmed)
            val report = cost.monthToDateCost(trimmed)

            demoMode.setActive(false)
            _isDemo.value = false
            credentialStore.save(provider, trimmed)
            val keys = credentialStore.loadAll()
            _maskedKey.value = maskedKeys(keys.ifEmpty { mapOf(provider to trimmed) })
            cache.save(provider, report, identity.name)
            val providerReports = cache.loadAll().toProviderReports().ifEmpty {
                listOf(ProviderReport(provider, identity.name, report))
            }
            _state.value = loadedState(providerReports, selectedProvider())
            ConnectResult.Success
        } catch (e: Exception) {
            if (!preserveExistingOnFailure) {
                _state.value = DashboardState.NeedsCredentials
            }
            if (e.isProviderAuthError()) {
                ConnectResult.Failure(REJECTED_KEY_MESSAGE)
            } else {
                ConnectResult.Failure(e.message ?: "Couldn't connect. Check your connection and try again.")
            }
        }
    }

    private suspend fun refreshUsing(keys: Map<ProviderKind, String>) {
        val hasSomethingToShow = _state.value is DashboardState.Loaded
        if (hasSomethingToShow) {
            _isRefreshing.value = true
        } else {
            _state.value = DashboardState.Loading
        }

        val freshReports = mutableListOf<ProviderReport>()
        var transientFailure: Exception? = null

        try {
            keys.forEach { (provider, key) ->
                try {
                    coroutineScope {
                        val identity = async { cost.whoami(key) }
                        val report = async { cost.monthToDateCost(key) }
                        val org = identity.await()
                        val mtd = report.await()
                        cache.save(provider, mtd, org.name)
                        freshReports += ProviderReport(provider, org.name, mtd)
                    }
                } catch (e: Exception) {
                    if (e.isProviderAuthError()) {
                        credentialStore.delete(provider)
                        cache.clear(provider)
                    } else {
                        transientFailure = e
                    }
                }
            }

            val remainingKeys = credentialStore.loadAll()
            _maskedKey.value = maskedKeys(remainingKeys)
            _isDemo.value = false

            val reports = if (freshReports.isNotEmpty()) {
                freshReports
            } else {
                cache.loadAll().toProviderReports()
            }

            if (reports.isNotEmpty()) {
                _state.value = loadedState(reports, selectedProvider())
            } else if (remainingKeys.isEmpty()) {
                _maskedKey.value = null
                _state.value = DashboardState.NeedsCredentials
            } else if (!hasSomethingToShow) {
                _state.value = DashboardState.Failed(
                    transientFailure?.message ?: "Couldn't load your usage."
                )
            }
        } finally {
            _isRefreshing.value = false
        }
    }

    private fun Map<ProviderKind, CachedReport>.toProviderReports(): List<ProviderReport> =
        entries.sortedBy { it.key.ordinal }.map { (provider, cached) ->
            ProviderReport(provider, cached.orgName, cached.report)
        }

    private fun loadedState(
        providerReports: List<ProviderReport>,
        selectedProvider: ProviderKind?
    ): DashboardState.Loaded {
        val effectiveSelection = selectedProvider?.takeIf { selected ->
            providerReports.any { it.provider == selected }
        }
        val visibleReports = effectiveSelection?.let { selected ->
            providerReports.filter { it.provider == selected }
        } ?: providerReports
        val report = if (visibleReports.size == 1) {
            visibleReports.single().report
        } else {
            combineMtdCosts(visibleReports.map { it.report })
        }
        val orgName = when {
            effectiveSelection != null -> visibleReports.first().orgName
            providerReports.size == 1 -> providerReports.single().orgName
            else -> "All providers"
        }
        return DashboardState.Loaded(
            orgName = orgName,
            report = report,
            providerReports = providerReports,
            selectedProvider = effectiveSelection
        )
    }

    private fun selectedProvider(): ProviderKind? =
        (_state.value as? DashboardState.Loaded)?.selectedProvider

    private fun maskedKeys(keys: Map<ProviderKind, String>): String? {
        if (keys.isEmpty()) return null
        return keys.entries.sortedBy { it.key.ordinal }.joinToString(" · ") { (provider, key) ->
            "${provider.displayName}: ${AnthropicKeyValidation.masked(key)}"
        }
    }

    private val ProviderKind.displayName: String
        get() = when (this) {
            ProviderKind.ANTHROPIC -> "Anthropic"
            ProviderKind.OPENAI -> "OpenAI"
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
