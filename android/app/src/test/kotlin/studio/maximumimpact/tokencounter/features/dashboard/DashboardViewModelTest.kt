package studio.maximumimpact.tokencounter.features.dashboard

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import retrofit2.HttpException
import retrofit2.Response
import studio.maximumimpact.tokencounter.core.DemoData
import studio.maximumimpact.tokencounter.core.MtdCost
import studio.maximumimpact.tokencounter.credentials.CredentialStore
import studio.maximumimpact.tokencounter.data.CachedReport
import studio.maximumimpact.tokencounter.data.DemoModeStore
import studio.maximumimpact.tokencounter.data.NotificationPrefsStore
import studio.maximumimpact.tokencounter.data.ReportCache
import studio.maximumimpact.tokencounter.data.SpendLimitStore
import studio.maximumimpact.tokencounter.providers.CostProvider
import studio.maximumimpact.tokencounter.providers.anthropic.OrgIdentity

private class FakeCostProvider(
    var org: OrgIdentity = OrgIdentity("org_1", "organization", "Acme"),
    var report: MtdCost? = null,
    var whoamiError: Throwable? = null,
    var reportError: Throwable? = null
) : CostProvider {
    override suspend fun whoami(apiKey: String): OrgIdentity {
        whoamiError?.let { throw it }
        return org
    }

    override suspend fun monthToDateCost(apiKey: String): MtdCost {
        reportError?.let { throw it }
        return report ?: error("no report configured")
    }
}

private class FakeCredentialStore(var stored: String? = null) : CredentialStore {
    override suspend fun save(key: String) { stored = key }
    override suspend fun load(): String? = stored
    override suspend fun delete() { stored = null }
}

private class FakeReportCache(var cached: CachedReport? = null) : ReportCache {
    override suspend fun load(): CachedReport? = cached
    override suspend fun save(report: MtdCost, orgName: String) { cached = CachedReport(report, orgName) }
    override suspend fun clear() { cached = null }
}

private class FakeDemoModeStore(var active: Boolean = false) : DemoModeStore {
    override suspend fun isActive(): Boolean = active
    override suspend fun setActive(active: Boolean) { this.active = active }
}

private class FakeSpendLimitStore(initial: Long? = null) : SpendLimitStore {
    private val flow = MutableStateFlow(initial)
    override val limitCents: Flow<Long?> = flow
    override suspend fun setLimitCents(cents: Long?) { flow.value = cents }
}

private class FakeNotificationPrefsStore(initial: Boolean = false) : NotificationPrefsStore {
    private val flow = MutableStateFlow(initial)
    private var lastMonth: String? = null
    override val alertEnabled: Flow<Boolean> = flow
    override suspend fun setAlertEnabled(enabled: Boolean) { flow.value = enabled }
    override suspend fun getLastAlertedMonth(): String? = lastMonth
    override suspend fun setLastAlertedMonth(month: String?) { lastMonth = month }
}

@OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
class DashboardViewModelTest {

    private val dispatcher = StandardTestDispatcher()
    private val sampleReport = DemoData.snapshot().report

    private lateinit var cost: FakeCostProvider
    private lateinit var creds: FakeCredentialStore
    private lateinit var cache: FakeReportCache
    private lateinit var demo: FakeDemoModeStore
    private lateinit var spendLimit: FakeSpendLimitStore
    private lateinit var notificationPrefs: FakeNotificationPrefsStore

    @Before
    fun setUp() {
        Dispatchers.setMain(dispatcher)
        cost = FakeCostProvider(report = sampleReport)
        creds = FakeCredentialStore()
        cache = FakeReportCache()
        demo = FakeDemoModeStore()
        spendLimit = FakeSpendLimitStore()
        notificationPrefs = FakeNotificationPrefsStore()
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    private fun viewModel() =
        DashboardViewModel(cost, creds, cache, demo, spendLimit, notificationPrefs)

    private fun authError(): HttpException =
        HttpException(Response.error<Any>(401, "".toResponseBody(null)))

    @Test
    fun connect_withReviewKey_entersDemoWithoutSavingKey() = runTest(dispatcher) {
        val vm = viewModel()
        val result = vm.connect(DemoData.REVIEW_KEY)

        assertEquals(ConnectResult.Success, result)
        val state = vm.state.value
        assertTrue(state is DashboardState.Loaded && state.orgName == "Personal")
        assertTrue(vm.isDemo.value)
        assertTrue(demo.active)
        assertNull("review key must not be persisted", creds.stored)
    }

    @Test
    fun connect_blankKey_returnsFailure() = runTest(dispatcher) {
        val result = viewModel().connect("   ")
        assertTrue(result is ConnectResult.Failure)
    }

    @Test
    fun connect_realKey_verifiesSavesAndLoads() = runTest(dispatcher) {
        cost.org = OrgIdentity("org_9", "organization", "Globex")
        val vm = viewModel()

        val result = vm.connect("sk-ant-admin01-realrealrealrealrealreal")

        assertEquals(ConnectResult.Success, result)
        val state = vm.state.value
        assertTrue(state is DashboardState.Loaded && state.orgName == "Globex")
        assertEquals("sk-ant-admin01-realrealrealrealrealreal", creds.stored)
        assertFalse(vm.isDemo.value)
        assertEquals(CachedReport(sampleReport, "Globex"), cache.cached)
    }

    @Test
    fun connect_authError_returnsToOnboardingWithoutSaving() = runTest(dispatcher) {
        cost.whoamiError = authError()
        val vm = viewModel()

        val result = vm.connect("sk-ant-admin01-badbadbadbadbadbadbad")

        assertTrue(result is ConnectResult.Failure)
        assertEquals(DashboardState.NeedsCredentials, vm.state.value)
        assertNull(creds.stored)
    }

    @Test
    fun connect_authErrorOnCostFetchAfterSave_wipesKeyAndReOnboards() = runTest(dispatcher) {
        // whoami succeeds (key gets saved), then the cost fetch returns 401/403.
        cost.reportError = authError()
        val vm = viewModel()

        val result = vm.connect("sk-ant-admin01-realrealrealrealrealreal")

        assertTrue(result is ConnectResult.Failure)
        assertEquals(DashboardState.NeedsCredentials, vm.state.value)
        assertNull("rejected key must not linger in storage", creds.stored)
        assertNull(cache.cached)
    }

    @Test
    fun bootstrap_noStoredKey_goesToOnboarding() = runTest(dispatcher) {
        val vm = viewModel()
        vm.bootstrap()
        advanceUntilIdle()
        assertEquals(DashboardState.NeedsCredentials, vm.state.value)
    }

    @Test
    fun bootstrap_withKey_refreshesToLoaded() = runTest(dispatcher) {
        creds.stored = "sk-ant-admin01-stored"
        cache.cached = CachedReport(sampleReport, "Cached Org")
        cost.org = OrgIdentity("org_2", "organization", "Fresh Org")
        val vm = viewModel()

        vm.bootstrap()
        advanceUntilIdle()

        val state = vm.state.value
        assertTrue(state is DashboardState.Loaded && state.orgName == "Fresh Org")
    }

    @Test
    fun refresh_authError_wipesKeyAndReOnboards() = runTest(dispatcher) {
        creds.stored = "sk-ant-admin01-stored"
        cost.whoamiError = authError()
        val vm = viewModel()

        vm.refresh()
        advanceUntilIdle()

        assertEquals(DashboardState.NeedsCredentials, vm.state.value)
        assertNull(creds.stored)
        assertNull(cache.cached)
    }

    @Test
    fun setSpendLimit_persistsAndClears() = runTest(dispatcher) {
        val vm = viewModel()
        advanceUntilIdle()
        assertNull(vm.spendLimitCents.value)

        vm.setSpendLimit(140_000)
        advanceUntilIdle()
        assertEquals(140_000L, vm.spendLimitCents.value)

        vm.setSpendLimit(null)
        advanceUntilIdle()
        assertNull(vm.spendLimitCents.value)
    }

    @Test
    fun setAlertEnabled_persists() = runTest(dispatcher) {
        val vm = viewModel()
        advanceUntilIdle()
        assertFalse(vm.alertEnabled.value)

        vm.setAlertEnabled(true)
        advanceUntilIdle()
        assertTrue(vm.alertEnabled.value)

        vm.setAlertEnabled(false)
        advanceUntilIdle()
        assertFalse(vm.alertEnabled.value)
    }

    @Test
    fun setSpendLimit_null_alsoDisablesAlert() = runTest(dispatcher) {
        val vm = viewModel()
        vm.setSpendLimit(140_000)
        vm.setAlertEnabled(true)
        advanceUntilIdle()
        assertTrue(vm.alertEnabled.value)

        // Clearing the limit must turn the alert off (nothing to compare against).
        vm.setSpendLimit(null)
        advanceUntilIdle()
        assertNull(vm.spendLimitCents.value)
        assertFalse(vm.alertEnabled.value)
    }

    @Test
    fun disconnect_clearsKeyCacheAndDemoFlag() = runTest(dispatcher) {
        creds.stored = "sk-ant-admin01-stored"
        cache.cached = CachedReport(sampleReport, "Org")
        demo.active = true
        val vm = viewModel()

        vm.disconnect()
        advanceUntilIdle()

        assertEquals(DashboardState.NeedsCredentials, vm.state.value)
        assertNull(creds.stored)
        assertNull(cache.cached)
        assertFalse(demo.active)
        assertNull(vm.maskedKey.value)
    }
}
