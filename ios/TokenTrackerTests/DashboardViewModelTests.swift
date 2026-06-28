import XCTest
@testable import TokenTracker

/// State-machine tests for `DashboardViewModel`. The view model's collaborators
/// (Anthropic API, Keychain, report cache) are injected as protocols, so these
/// tests drive every branch — auth failure, transient network failure with and
/// without cached data, demo short-circuits — without any network or Keychain.
///
/// Everything runs on the main actor (the view model is `@MainActor`), so the
/// plain-class mocks below are only ever touched from one isolation domain.
@MainActor
final class DashboardViewModelTests: XCTestCase {
    /// A real-length, admin-looking key (>= `AnthropicKeyValidation.minLength`,
    /// and distinct from the demo review key) for the real-credential paths.
    private let validKey = "sk-ant-" + String(repeating: "A", count: 40)
    private let openAIKey = "sk-proj-" + String(repeating: "B", count: 40)

    /// Throwaway defaults suite so DemoMode persistence never leaks into

    private let suiteName = "ai.openclaw.tokentracker.DashboardViewModelTests"

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: suiteName)
        DemoMode.defaultsOverride = UserDefaults(suiteName: suiteName)
        DemoMode.isPersistedActive = false
    }

    override func tearDown() {
        DemoMode.isPersistedActive = false
        DemoMode.defaultsOverride = nil
        UserDefaults().removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - bootstrap

    func testBootstrap_noStoredKey_goesToNeedsCredentials() async {
        let cost = MockCostProvider()
        let vm = makeVM(cost: cost, keychain: MockCredentialStore(stored: nil))

        await vm.bootstrap()

        XCTAssertEqual(vm.state, .needsCredentials)
        XCTAssertEqual(cost.whoamiCount, 0, "No key → no network call")
    }

    func testBootstrap_storedKey_noCache_loadsFresh() async {
        let report = TestFixtures.report(finalizedCents: 5_000)
        let cost = MockCostProvider(whoami: .success(org("Acme")), cost: .success(report))
        let cache = MockReportCache(cached: nil)
        let vm = makeVM(cost: cost, keychain: MockCredentialStore(stored: validKey), cache: cache)

        await vm.bootstrap()

        guard case .loaded(let loaded, let org) = vm.state else {
            return XCTFail("expected .loaded, got \(vm.state)")
        }
        XCTAssertEqual(loaded, report)
        XCTAssertEqual(org, "Acme")
        XCTAssertEqual(cache.saveCount, 1, "Fresh report should be cached")
        XCTAssertNotNil(vm.maskedKey)
        XCTAssertFalse(vm.isRefreshing)
    }

    func testBootstrap_storedKey_withCache_freshReplacesCached() async {
        let cached = TestFixtures.report(finalizedCents: 100)
        let fresh = TestFixtures.report(finalizedCents: 9_999)
        let cost = MockCostProvider(whoami: .success(org("Fresh Org")), cost: .success(fresh))
        let cache = MockReportCache(cached: (cached, "Cached Org"))
        let vm = makeVM(cost: cost, keychain: MockCredentialStore(stored: validKey), cache: cache)

        await vm.bootstrap()

        guard case .loaded(let loaded, let org) = vm.state else {
            return XCTFail("expected .loaded, got \(vm.state)")
        }
        XCTAssertEqual(loaded, fresh, "Fresh fetch must replace the cached snapshot")
        XCTAssertEqual(org, "Fresh Org")
    }

    func testBootstrap_multipleStoredKeys_combinesProviderSpend() async {
        let anthropicReport = TestFixtures.report(finalizedCents: 1_200, todayCents: 34)
        let openAIReport = TestFixtures.report(finalizedCents: 2_300, todayCents: 56)
        let cost = MockCostProvider(
            whoamiByKey: [validKey: .success(org("Anthropic Org")), openAIKey: .success(org("OpenAI Org"))],
            costByKey: [validKey: .success(anthropicReport), openAIKey: .success(openAIReport)]
        )
        let keychain = MockCredentialStore(storedByProvider: [ProviderKind.anthropic: validKey, ProviderKind.openAI: openAIKey])
        let cache = MockReportCache()
        let vm = makeVM(cost: cost, keychain: keychain, cache: cache)

        await vm.bootstrap()

        guard case .loaded(let loaded, let org) = vm.state else {
            return XCTFail("expected .loaded, got \(vm.state)")
        }
        XCTAssertEqual(org, "All providers")
        XCTAssertEqual(loaded.finalizedCost.cents, 3_500)
        XCTAssertEqual(loaded.todayEstimatedCost.cents, 90)
        XCTAssertEqual(vm.providerReports.map { $0.provider }, [ProviderKind.anthropic, ProviderKind.openAI])
        XCTAssertNil(vm.selectedProvider)
        XCTAssertEqual(cache.saveCount, 2)
    }

    func testProviderFilter_showsSelectedProviderSpendThenAllProviders() async {
        let anthropicReport = TestFixtures.report(finalizedCents: 1_200)
        let openAIReport = TestFixtures.report(finalizedCents: 2_300)
        let cost = MockCostProvider(
            whoamiByKey: [validKey: .success(org("Anthropic Org")), openAIKey: .success(org("OpenAI Org"))],
            costByKey: [validKey: .success(anthropicReport), openAIKey: .success(openAIReport)]
        )
        let vm = makeVM(
            cost: cost,
            keychain: MockCredentialStore(storedByProvider: [ProviderKind.anthropic: validKey, ProviderKind.openAI: openAIKey])
        )

        await vm.bootstrap()
        vm.selectProviderFilter(ProviderKind.openAI)

        guard case .loaded(let filtered, let filteredOrg) = vm.state else {
            return XCTFail("expected .loaded after filter, got \(vm.state)")
        }
        XCTAssertEqual(filteredOrg, "OpenAI Org")
        XCTAssertEqual(filtered.finalizedCost.cents, 2_300)
        XCTAssertEqual(vm.selectedProvider, ProviderKind.openAI)

        vm.selectProviderFilter(nil as ProviderKind?)
        guard case .loaded(let combined, let combinedOrg) = vm.state else {
            return XCTFail("expected .loaded after clearing filter, got \(vm.state)")
        }
        XCTAssertEqual(combinedOrg, "All providers")
        XCTAssertEqual(combined.finalizedCost.cents, 3_500)
        XCTAssertNil(vm.selectedProvider)
    }

    func testRefresh_authFailureForOneProvider_preservesOtherProviderCredentialAndCache() async {
        let cachedAnthropic = TestFixtures.report(finalizedCents: 1_111)
        let freshOpenAI = TestFixtures.report(finalizedCents: 2_222)
        let cost = MockCostProvider(
            whoamiByKey: [validKey: .failure(TestFixtures.httpError(401)), openAIKey: .success(org("OpenAI Org"))],
            costByKey: [openAIKey: .success(freshOpenAI)]
        )
        let keychain = MockCredentialStore(storedByProvider: [ProviderKind.anthropic: validKey, ProviderKind.openAI: openAIKey])
        let cache = MockReportCache(cachedByProvider: [
            ProviderKind.anthropic: (cachedAnthropic, "Old Anthropic"),
            ProviderKind.openAI: (TestFixtures.report(finalizedCents: 999), "Old OpenAI")
        ])
        let vm = makeVM(cost: cost, keychain: keychain, cache: cache)

        await vm.refresh()

        XCTAssertNil(keychain.storedByProvider[ProviderKind.anthropic], "Rejected provider credential is removed")
        XCTAssertEqual(keychain.storedByProvider[ProviderKind.openAI], openAIKey, "Unaffected provider credential remains")
        XCTAssertNil(cache.cachedByProvider[ProviderKind.anthropic], "Rejected provider cache is cleared")
        XCTAssertEqual(cache.cachedByProvider[ProviderKind.openAI]?.report, freshOpenAI, "Unaffected provider refresh/cache remains")
        guard case .loaded(let loaded, let org) = vm.state else {
            return XCTFail("expected .loaded with remaining provider, got \(vm.state)")
        }
        XCTAssertEqual(org, "OpenAI Org")
        XCTAssertEqual(loaded.finalizedCost.cents, 2_222)
        XCTAssertEqual(vm.providerReports.map { $0.provider }, [ProviderKind.openAI])
    }

    func testBootstrap_keychainThrows_goesToFailed() async {
        let keychain = MockCredentialStore(stored: validKey)
        keychain.loadError = TestFixtures.httpError(500)
        let vm = makeVM(keychain: keychain)

        await vm.bootstrap()

        guard case .failed(let message) = vm.state else {
            return XCTFail("expected .failed, got \(vm.state)")
        }
        XCTAssertTrue(message.contains("Keychain"))
    }

    // MARK: - connect

    func testConnect_emptyKey_returnsFailureWithoutNetwork() async {
        let cost = MockCostProvider()
        let vm = makeVM(cost: cost)

        let result = await vm.connect(using: "   ")

        XCTAssertTrue(isFailure(result))
        XCTAssertEqual(cost.whoamiCount, 0)
    }

    func testConnect_demoReviewKey_loadsSnapshotWithoutNetworkOrKeychain() async {
        let cost = MockCostProvider()
        let keychain = MockCredentialStore()
        let vm = makeVM(cost: cost, keychain: keychain)

        let result = await vm.connect(using: DemoMode.appReviewKey)

        XCTAssertTrue(isSuccess(result))
        guard case .loaded(_, let org) = vm.state else {
            return XCTFail("expected .loaded, got \(vm.state)")
        }
        XCTAssertEqual(org, "Personal", "Demo snapshot org name")
        XCTAssertTrue(DemoMode.isPersistedActive, "Pasting the review key persists demo mode")
        XCTAssertEqual(cost.whoamiCount, 0, "Demo key must short-circuit before any network call")
        XCTAssertEqual(keychain.saveCount, 0, "Demo key must never be written to the Keychain")
    }

    func testConnect_validKey_savesKeyAndLoadsReport() async {
        let report = TestFixtures.report(finalizedCents: 4_242)
        let cost = MockCostProvider(whoami: .success(org("Acme")), cost: .success(report))
        let keychain = MockCredentialStore()
        let cache = MockReportCache()
        let vm = makeVM(cost: cost, keychain: keychain, cache: cache)

        let result = await vm.connect(using: validKey)

        XCTAssertTrue(isSuccess(result))
        XCTAssertEqual(keychain.savedValue, validKey, "Key is persisted only after it authenticates")
        guard case .loaded(let loaded, let org) = vm.state else {
            return XCTFail("expected .loaded, got \(vm.state)")
        }
        XCTAssertEqual(loaded, report)
        XCTAssertEqual(org, "Acme")
        XCTAssertEqual(cache.saveCount, 1)
    }

    func testConnect_validKey_clearsPersistedDemoFlag() async {
        // Previously a manual-only scenario (see DemoModeTests): switching from
        // demo mode to a real key must drop the DEMO pill.
        DemoMode.isPersistedActive = true
        let vm = makeVM(cost: MockCostProvider(whoami: .success(org("Acme"))))

        _ = await vm.connect(using: validKey)

        XCTAssertFalse(DemoMode.isPersistedActive, "A successful real-key connect clears demo mode")
    }

    func testConnect_authFailure_doesNotSaveKey() async {
        let cost = MockCostProvider(whoami: .failure(TestFixtures.httpError(401)))
        let keychain = MockCredentialStore()
        let vm = makeVM(cost: cost, keychain: keychain)

        let result = await vm.connect(using: validKey)

        XCTAssertTrue(isFailure(result))
        XCTAssertEqual(vm.state, .needsCredentials)
        XCTAssertEqual(keychain.saveCount, 0, "A rejected key must never be stored")
        XCTAssertEqual(cost.costCount, 0, "Must not fetch cost after an auth failure")
    }

    func testConnect_openAIAuthFailure_doesNotSaveKey() async {
        let cost = MockCostProvider(whoami: .failure(TestFixtures.openAIHTTPError(401)))
        let keychain = MockCredentialStore()
        let vm = makeVM(cost: cost, keychain: keychain)

        let result = await vm.connect(using: validKey)

        XCTAssertTrue(isFailure(result))
        XCTAssertEqual(vm.state, .needsCredentials)
        XCTAssertEqual(keychain.saveCount, 0, "An OpenAI-rejected key must never be stored")
        XCTAssertEqual(cost.costCount, 0, "Must not fetch cost after an auth failure")
    }

    func testConnect_authFailure_preservesPersistedDemoFlag() async {
        // 401/403 on connect intentionally leaves demo mode alone so a
        // transient bad-key attempt doesn't strand a reviewer with no UI.
        DemoMode.isPersistedActive = true
        let cost = MockCostProvider(whoami: .failure(TestFixtures.httpError(403)))
        let vm = makeVM(cost: cost)

        _ = await vm.connect(using: validKey)

        XCTAssertTrue(DemoMode.isPersistedActive, "Auth failure must not clear demo mode")
    }

    func testConnect_authSucceedsButCostFails_savesKeyAndShowsFailed() async {
        let cost = MockCostProvider(
            whoami: .success(org("Acme")),
            cost: .failure(TestFixtures.httpError(500))
        )
        let keychain = MockCredentialStore()
        let vm = makeVM(cost: cost, keychain: keychain)

        let result = await vm.connect(using: validKey)

        XCTAssertTrue(isSuccess(result), "connect succeeds once the key auth'd, even if the cost fetch fails")
        XCTAssertEqual(keychain.savedValue, validKey, "Key stays saved — it authenticated")
        guard case .failed = vm.state else {
            return XCTFail("expected .failed, got \(vm.state)")
        }
    }

    func testConnect_authFailsOnCostFetchAfterSave_wipesKeyAndReOnboards() async {
        // whoami succeeds (so the key is saved), then the month-to-date cost
        // fetch is rejected with a 401 — the key was revoked or lacked scope
        // between the two calls. The rejected key must not linger in the
        // Keychain behind a generic dashboard error: we wipe it and route back
        // to onboarding. Mirrors the Android regression in PR #56.
        let cost = MockCostProvider(
            whoami: .success(org("Acme")),
            cost: .failure(TestFixtures.httpError(401))
        )
        let keychain = MockCredentialStore()
        let cache = MockReportCache()
        let vm = makeVM(cost: cost, keychain: keychain, cache: cache)

        let result = await vm.connect(using: validKey)

        XCTAssertTrue(isFailure(result), "a rejected cost fetch must surface as a connect failure")
        XCTAssertEqual(vm.state, .needsCredentials)
        XCTAssertEqual(cost.costCount, 1, "cost fetch ran after whoami auth'd")
        XCTAssertEqual(keychain.deleteCount, 1, "the rejected key is wiped, not left behind")
        XCTAssertNil(keychain.stored)
        XCTAssertEqual(cache.clearCount, 1, "the cache is wiped with the token")
        XCTAssertNil(vm.maskedKey)
    }

    // MARK: - refresh

    func testRefresh_noStoredKey_goesToNeedsCredentials() async {
        let vm = makeVM(keychain: MockCredentialStore(stored: nil))

        await vm.refresh()

        XCTAssertEqual(vm.state, .needsCredentials)
        XCTAssertNil(vm.maskedKey)
    }

    func testRefresh_authFailure_wipesKeyAndCache() async {
        let cost = MockCostProvider(whoami: .failure(TestFixtures.httpError(403)))
        let keychain = MockCredentialStore(stored: validKey)
        let cache = MockReportCache(cached: (TestFixtures.report(), "Old Org"))
        let vm = makeVM(cost: cost, keychain: keychain, cache: cache)

        await vm.refresh()

        XCTAssertEqual(vm.state, .needsCredentials)
        XCTAssertEqual(keychain.deleteCount, 1, "Bad token is wiped")
        XCTAssertEqual(cache.clearCount, 1, "Stale cache is wiped with the token")
        XCTAssertNil(vm.maskedKey)
    }

    func testRefresh_openAIAuthFailure_wipesKeyAndCache() async {
        let cost = MockCostProvider(whoami: .failure(TestFixtures.openAIHTTPError(403)))
        let keychain = MockCredentialStore(stored: validKey)
        let cache = MockReportCache(cached: (TestFixtures.report(), "Old Org"))
        let vm = makeVM(cost: cost, keychain: keychain, cache: cache)

        await vm.refresh()

        XCTAssertEqual(vm.state, .needsCredentials)
        XCTAssertEqual(keychain.deleteCount, 1, "Bad OpenAI token is wiped")
        XCTAssertEqual(cache.clearCount, 1, "Stale cache is wiped with the token")
        XCTAssertNil(vm.maskedKey)
    }

    func testRefresh_networkError_withCachedData_preservesLoadedState() async {
        // bootstrap shows the cached snapshot, then the in-flight refresh fails
        // with a transient (non-auth) error: the cached data must stay on screen.
        let cache = MockReportCache(cached: (TestFixtures.report(finalizedCents: 777), "Cached Org"))
        let cost = MockCostProvider(
            whoami: .success(org("Fresh Org")),
            cost: .failure(URLError(.timedOut))
        )
        let vm = makeVM(cost: cost, keychain: MockCredentialStore(stored: validKey), cache: cache)

        await vm.bootstrap()

        guard case .loaded(let loaded, let org) = vm.state else {
            return XCTFail("expected cached .loaded to survive a network error, got \(vm.state)")
        }
        XCTAssertEqual(org, "Cached Org")
        XCTAssertEqual(loaded.finalizedCost.cents, 777)
        XCTAssertFalse(vm.isRefreshing, "Refresh indicator clears even on failure")
    }

    func testRefresh_networkError_noCachedData_goesToFailed() async {
        let cost = MockCostProvider(
            whoami: .success(org("Fresh Org")),
            cost: .failure(URLError(.timedOut))
        )
        let vm = makeVM(
            cost: cost,
            keychain: MockCredentialStore(stored: validKey),
            cache: MockReportCache(cached: nil)
        )

        await vm.refresh()

        guard case .failed = vm.state else {
            return XCTFail("expected .failed with nothing to show, got \(vm.state)")
        }
    }

    // MARK: - disconnect

    func testDisconnect_clearsCacheKeyAndDemoFlag() async {
        DemoMode.isPersistedActive = true
        let keychain = MockCredentialStore(stored: validKey)
        let cache = MockReportCache(cached: (TestFixtures.report(), "Org"))
        let vm = makeVM(keychain: keychain, cache: cache)

        await vm.disconnect()

        XCTAssertEqual(vm.state, .needsCredentials)
        XCTAssertEqual(keychain.deleteCount, 1)
        XCTAssertEqual(cache.clearCount, 1)
        XCTAssertNil(vm.maskedKey)
        XCTAssertFalse(DemoMode.isPersistedActive)
    }

    func testDisconnect_keychainDeleteThrows_surfacesFailedButStillClearsCache() async {
        let keychain = MockCredentialStore(stored: validKey)
        keychain.deleteError = TestFixtures.httpError(500)
        let cache = MockReportCache(cached: (TestFixtures.report(), "Org"))
        let vm = makeVM(keychain: keychain, cache: cache)

        await vm.disconnect()

        guard case .failed(let message) = vm.state else {
            return XCTFail("expected .failed, got \(vm.state)")
        }
        XCTAssertTrue(message.contains("Disconnected"))
        XCTAssertEqual(cache.clearCount, 1, "Cache is cleared before the Keychain delete is attempted")
    }

    // MARK: - helpers

    private func makeVM(
        cost: MockCostProvider = MockCostProvider(),
        keychain: MockCredentialStore = MockCredentialStore(),
        cache: MockReportCache = MockReportCache(),
        spendLimits: SpendLimitStoring = MockSpendLimitStore(),
        notificationPrefs: NotificationPreferenceStoring = MockNotificationPrefs()
    ) -> DashboardViewModel {
        DashboardViewModel(
            cost: cost,
            keychain: keychain,
            cache: cache,
            spendLimits: spendLimits,
            notificationPrefs: notificationPrefs
        )
    }

    // MARK: - spend limit + alert opt-in

    func testSetSpendLimit_persistsAndClears() {
        let store = MockSpendLimitStore()
        let vm = makeVM(spendLimits: store)

        XCTAssertNil(vm.spendLimitCents)
        vm.setSpendLimit(140_000)
        XCTAssertEqual(vm.spendLimitCents, 140_000)
        XCTAssertEqual(store.limitCents, 140_000)

        vm.setSpendLimit(nil)
        XCTAssertNil(vm.spendLimitCents)
        XCTAssertNil(store.limitCents)
    }

    func testSetSpendAlertEnabled_persists() {
        let prefs = MockNotificationPrefs()
        let vm = makeVM(notificationPrefs: prefs)

        XCTAssertFalse(vm.spendAlertEnabled)
        vm.setSpendAlertEnabled(true)
        XCTAssertTrue(vm.spendAlertEnabled)
        XCTAssertTrue(prefs.alertEnabled)

        vm.setSpendAlertEnabled(false)
        XCTAssertFalse(vm.spendAlertEnabled)
        XCTAssertFalse(prefs.alertEnabled)
    }

    func testClearingSpendLimit_disablesAlert() {
        let limits = MockSpendLimitStore(140_000)
        let prefs = MockNotificationPrefs(enabled: true)
        let vm = makeVM(spendLimits: limits, notificationPrefs: prefs)
        XCTAssertTrue(vm.spendAlertEnabled)

        // Clearing the limit must turn the alert off (nothing to compare against).
        vm.setSpendLimit(nil)

        XCTAssertNil(vm.spendLimitCents)
        XCTAssertFalse(vm.spendAlertEnabled)
        XCTAssertFalse(prefs.alertEnabled)
    }

    private func org(_ name: String) -> AnthropicAPI.OrgIdentity {
        AnthropicAPI.OrgIdentity(id: "org_test", type: "organization", name: name)
    }

    private func isSuccess<T>(_ result: Result<T, Error>) -> Bool {
        if case .success = result { return true }
        return false
    }

    private func isFailure<T>(_ result: Result<T, Error>) -> Bool {
        if case .failure = result { return true }
        return false
    }
}

// MARK: - Test doubles

private enum TestFixtures {
    static func report(finalizedCents: Int64 = 1_000, todayCents: Int64 = 0) -> MTDCost {
        MTDCost(
            finalizedCost: Money(cents: finalizedCents),
            todayEstimatedCost: Money(cents: todayCents),
            unpricedModels: [],
            finalizedThrough: Date(timeIntervalSince1970: 1_700_000_000),
            asOf: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    static func httpError(_ status: Int) -> AnthropicHTTPError {
        AnthropicHTTPError(status: status, body: "test-error")
    }

    static func openAIHTTPError(_ status: Int) -> OpenAIHTTPError {
        OpenAIHTTPError(status: status, body: "test-error")
    }
}

private final class MockCostProvider: CostProviding {
    var whoamiResult: Result<AnthropicAPI.OrgIdentity, Error>
    var costResult: Result<MTDCost, Error>
    var whoamiByKey: [String: Result<AnthropicAPI.OrgIdentity, Error>]
    var costByKey: [String: Result<MTDCost, Error>]
    private(set) var whoamiCount = 0
    private(set) var costCount = 0
    private(set) var lastApiKey: String?

    init(
        whoami: Result<AnthropicAPI.OrgIdentity, Error> = .success(
            AnthropicAPI.OrgIdentity(id: "org_test", type: "organization", name: "Test Org")
        ),
        cost: Result<MTDCost, Error> = .success(TestFixtures.report()),
        whoamiByKey: [String: Result<AnthropicAPI.OrgIdentity, Error>] = [:],
        costByKey: [String: Result<MTDCost, Error>] = [:]
    ) {
        self.whoamiResult = whoami
        self.costResult = cost
        self.whoamiByKey = whoamiByKey
        self.costByKey = costByKey
    }

    func whoami(apiKey: String) async throws -> AnthropicAPI.OrgIdentity {
        whoamiCount += 1
        lastApiKey = apiKey
        return try (whoamiByKey[apiKey] ?? whoamiResult).get()
    }

    func monthToDateCost(apiKey: String) async throws -> MTDCost {
        costCount += 1
        lastApiKey = apiKey
        return try (costByKey[apiKey] ?? costResult).get()
    }
}

private final class MockCredentialStore: CredentialStoring {
    var storedByProvider: [ProviderKind: String]
    var loadError: Error?
    var deleteError: Error?
    private(set) var saveCount = 0
    private(set) var deleteCount = 0
    private(set) var savedValue: String?
    private(set) var savedProvider: ProviderKind?

    var stored: String? {
        get { storedByProvider[.anthropic] ?? storedByProvider[.openAI] }
        set {
            storedByProvider.removeAll()
            if let newValue { storedByProvider[providerKind(for: newValue)] = newValue }
        }
    }

    init(stored: String? = nil, storedByProvider: [ProviderKind: String] = [:]) {
        self.storedByProvider = storedByProvider
        if let stored { self.storedByProvider[providerKind(for: stored)] = stored }
    }

    func loadAll() throws -> [ProviderKind: String] {
        if let loadError { throw loadError }
        return storedByProvider
    }

    func load(_ provider: ProviderKind) throws -> String? {
        if let loadError { throw loadError }
        return storedByProvider[provider]
    }

    func save(_ value: String, for provider: ProviderKind) throws {
        saveCount += 1
        savedValue = value
        savedProvider = provider
        storedByProvider[provider] = value
    }

    func delete(_ provider: ProviderKind) throws {
        deleteCount += 1
        if let deleteError { throw deleteError }
        storedByProvider[provider] = nil
    }

    func deleteAll() throws {
        deleteCount += 1
        if let deleteError { throw deleteError }
        storedByProvider.removeAll()
    }
}

private final class MockSpendLimitStore: SpendLimitStoring {
    var limitCents: Int64?
    init(_ limitCents: Int64? = nil) { self.limitCents = limitCents }
}

private final class MockNotificationPrefs: NotificationPreferenceStoring {
    var alertEnabled: Bool
    var lastAlertedMonth: String?
    init(enabled: Bool = false, lastAlertedMonth: String? = nil) {
        self.alertEnabled = enabled
        self.lastAlertedMonth = lastAlertedMonth
    }
}

private final class MockReportCache: ReportCaching {
    var cachedByProvider: [ProviderKind: (report: MTDCost, orgName: String)]
    private(set) var saveCount = 0
    private(set) var clearCount = 0

    var cached: (report: MTDCost, orgName: String)? {
        get { cachedByProvider[.anthropic] ?? cachedByProvider[.openAI] }
        set {
            cachedByProvider.removeAll()
            if let newValue { cachedByProvider[.anthropic] = newValue }
        }
    }

    init(
        cached: (report: MTDCost, orgName: String)? = nil,
        cachedByProvider: [ProviderKind: (report: MTDCost, orgName: String)] = [:]
    ) {
        self.cachedByProvider = cachedByProvider
        if let cached { self.cachedByProvider[.anthropic] = cached }
    }

    func loadAll() -> [ProviderKind: (report: MTDCost, orgName: String)] { cachedByProvider }

    func load(_ provider: ProviderKind) -> (report: MTDCost, orgName: String)? { cachedByProvider[provider] }

    func save(report: MTDCost, orgName: String, for provider: ProviderKind) {
        saveCount += 1
        cachedByProvider[provider] = (report, orgName)
    }

    func clear(_ provider: ProviderKind) {
        clearCount += 1
        cachedByProvider[provider] = nil
    }

    func clearAll() {
        clearCount += 1
        cachedByProvider.removeAll()
    }
}
