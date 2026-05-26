import XCTest
@testable import TokenTracker

final class DemoModeTests: XCTestCase {
    /// A throwaway defaults suite so these tests never write to
    /// `UserDefaults.standard`. Created fresh per-test and wiped in tearDown.
    private var suite: UserDefaults!
    private let suiteName = "ai.openclaw.tokentracker.DemoModeTests"

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: suiteName)
        suite = UserDefaults(suiteName: suiteName)
        DemoMode.defaultsOverride = suite
        // Make sure no carryover from a previous run.
        DemoMode.isPersistedActive = false
    }

    override func tearDown() {
        DemoMode.isPersistedActive = false
        DemoMode.defaultsOverride = nil
        UserDefaults().removePersistentDomain(forName: suiteName)
        suite = nil
        super.tearDown()
    }

    // MARK: - isReviewKey

    func testIsReviewKey_acceptsExactString() {
        XCTAssertTrue(DemoMode.isReviewKey("sk-ant-demo-2026-05-w22"))
    }

    func testIsReviewKey_acceptsWithWhitespace() {
        XCTAssertTrue(DemoMode.isReviewKey("  sk-ant-demo-2026-05-w22  "))
        XCTAssertTrue(DemoMode.isReviewKey("\nsk-ant-demo-2026-05-w22\n"))
        XCTAssertTrue(DemoMode.isReviewKey("\t sk-ant-demo-2026-05-w22 \t"))
    }

    func testIsReviewKey_isCaseInsensitive() {
        // Mobile keyboards autocorrect/auto-capitalize pasted strings, so
        // the comparison normalizes to lowercase.
        XCTAssertTrue(DemoMode.isReviewKey("SK-ANT-DEMO-2026-05-W22"))
        XCTAssertTrue(DemoMode.isReviewKey("Sk-Ant-Demo-2026-05-W22"))
    }

    func testIsReviewKey_rejectsRealLookingKey() {
        let realLooking = "sk-ant-admin01-" + String(repeating: "A", count: 40)
        XCTAssertFalse(DemoMode.isReviewKey(realLooking))
        XCTAssertFalse(DemoMode.isReviewKey("sk-ant-demo-2025-01-w01")) // wrong rotation
        XCTAssertFalse(DemoMode.isReviewKey("sk-ant-demo")) // prefix only
    }

    func testIsReviewKey_rejectsEmpty() {
        XCTAssertFalse(DemoMode.isReviewKey(""))
        XCTAssertFalse(DemoMode.isReviewKey("   "))
        XCTAssertFalse(DemoMode.isReviewKey("\n\t  \n"))
    }

    /// Regression guard for the OnboardingView "Save & Connect" gate.
    ///
    /// The demo key is intentionally shorter than `AnthropicKeyValidation.minLength`
    /// (which enforces a realistic admin key length). This is exactly *why*
    /// `OnboardingView.canSubmit` has to short-circuit on `DemoMode.isReviewKey`
    /// before the length check — otherwise reviewers paste the magic key, the
    /// button stays disabled, and Demo Mode is unreachable.
    ///
    /// If you ever lengthen `appReviewKey` past `minLength` and remove the
    /// short-circuit, this test will fail and remind you to keep the invariant
    /// documented in OnboardingView.canSubmit aligned with reality.
    func testAppReviewKey_isShorterThanMinLength_documentsCanSubmitShortCircuit() {
        XCTAssertLessThan(
            DemoMode.appReviewKey.count,
            AnthropicKeyValidation.minLength,
            "Demo review key must be shorter than the real-key minLength — this is the reason OnboardingView.canSubmit special-cases DemoMode.isReviewKey."
        )
        // Sanity: the magic key still matches itself.
        XCTAssertTrue(DemoMode.isReviewKey(DemoMode.appReviewKey))
    }

    // MARK: - Persistence

    func testPersistedActive_roundTrip() {
        XCTAssertFalse(DemoMode.isPersistedActive, "Fresh suite must read false")

        DemoMode.isPersistedActive = true
        XCTAssertTrue(DemoMode.isPersistedActive)

        DemoMode.isPersistedActive = false
        XCTAssertFalse(DemoMode.isPersistedActive)
    }

    // MARK: - snapshot

    func testSnapshot_includesDailySpendAndModelBreakdown() {
        let (org, report) = DemoMode.snapshot()
        XCTAssertEqual(org, "Personal")
        XCTAssertEqual(report.dailySpend.count, 30, "Should ship 30 days of canned spend")
        XCTAssertEqual(report.modelBreakdown.count, 3, "Should ship top 3 models")
        XCTAssertGreaterThan(report.todayEstimatedCost.cents, 0)
    }

    func testSnapshot_dailySpendSumsToFinalizedCost() {
        let (_, report) = DemoMode.snapshot()
        let sum = report.dailySpend.reduce(Int64(0)) { $0 + $1.cost.cents }
        XCTAssertEqual(sum, report.finalizedCost.cents,
                       "Hero finalized total should equal the sum of the sparkline data")
    }

    func testSnapshot_modelBreakdownSumsToFinalized() {
        let (_, report) = DemoMode.snapshot()
        let sum = report.modelBreakdown.reduce(Int64(0)) { $0 + $1.cost.cents }
        XCTAssertEqual(sum, report.finalizedCost.cents,
                       "Top-3 model breakdown should partition the finalized total exactly")
    }

    func testSnapshot_modelBreakdownSortedDescending() {
        let (_, report) = DemoMode.snapshot()
        for (a, b) in zip(report.modelBreakdown, report.modelBreakdown.dropFirst()) {
            XCTAssertGreaterThanOrEqual(a.cost.cents, b.cost.cents)
        }
    }

    func testSnapshot_dailySpendSortedChronologically() {
        let (_, report) = DemoMode.snapshot()
        for (a, b) in zip(report.dailySpend, report.dailySpend.dropFirst()) {
            XCTAssertLessThan(a.date, b.date)
        }
    }

    // MARK: - DashboardViewModel x DemoMode integration

    /// Regression for bug: tapping the refresh icon in demo mode used to
    /// dump the user back to onboarding because `KeychainStore.load` returns
    /// nil (demo mode never writes a key). Refresh must mirror bootstrap's
    /// demo-mode short-circuit.
    @MainActor
    func testRefreshInDemoMode_keepsDashboardLoaded() async {
        DemoMode.isPersistedActive = true
        let vm = DashboardViewModel()

        await vm.bootstrap()
        guard case .loaded(let bootReport, let bootOrg) = vm.state else {
            return XCTFail("bootstrap() in demo mode should leave state .loaded, got \(vm.state)")
        }
        XCTAssertEqual(bootOrg, "Personal")
        XCTAssertGreaterThan(bootReport.finalizedCost.cents, 0)

        await vm.refresh()
        guard case .loaded(let refReport, let refOrg) = vm.state else {
            return XCTFail("refresh() in demo mode must keep state .loaded (bug: was returning .needsCredentials), got \(vm.state)")
        }
        XCTAssertEqual(refOrg, "Personal")
        XCTAssertEqual(refReport.finalizedCost.cents, bootReport.finalizedCost.cents,
                       "Refresh in demo mode should re-render the same canned snapshot")
        XCTAssertNotNil(vm.maskedKey, "Demo-mode refresh must keep the masked key so Settings stays consistent")
    }

    /// Manual verification scenario for bug 2 (DEMO pill leaks after
    /// switching from demo to a real admin key):
    ///
    /// The flag-clear lives in `DashboardViewModel.connect(using:)`
    /// immediately after `client.whoami()` succeeds. We can't easily unit-test
    /// this path without mocking `AnthropicClient` (which currently has no
    /// protocol seam). To verify manually:
    ///   1. Launch app, paste `DemoMode.appReviewKey` in onboarding → demo
    ///      mode persists, DEMO pill visible.
    ///   2. Tap Disconnect.
    ///   3. Paste a real admin key, tap Save & Connect.
    ///   4. On success, the DEMO pill must NOT appear on the dashboard.
    ///   5. If the new key auth-fails (401/403), the persisted flag is
    ///      intentionally left alone so transient state isn't lost.
    func testConnectRealKey_clearsPersistedDemoFlag_manualScenarioDocumented() {
        // Sanity: flag round-trip already covered by testPersistedActive_roundTrip.
        // This test exists purely as a discoverable anchor for the manual scenario above.
        XCTAssertFalse(DemoMode.isPersistedActive)
    }

    func testIsEnabled_honorsPersistedFlag() {
        // Pre-condition: launch args aren't set in a unit test, so the only
        // way isEnabled flips true here is via the persisted flag.
        XCTAssertFalse(DemoMode.isPersistedActive)
        // isEnabled also reads UserDefaults.standard for the launch-arg path
        // and DemoModeScreen; in unit-test land those are unset, so this
        // should be false.
        XCTAssertFalse(DemoMode.isEnabled, "Demo mode must be off by default in tests")

        DemoMode.isPersistedActive = true
        XCTAssertTrue(DemoMode.isEnabled, "Persisted flag must flip isEnabled true")

        DemoMode.isPersistedActive = false
        XCTAssertFalse(DemoMode.isEnabled)
    }
}
