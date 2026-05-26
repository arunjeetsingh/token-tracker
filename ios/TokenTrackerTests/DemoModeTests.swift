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

    // MARK: - Persistence

    func testPersistedActive_roundTrip() {
        XCTAssertFalse(DemoMode.isPersistedActive, "Fresh suite must read false")

        DemoMode.isPersistedActive = true
        XCTAssertTrue(DemoMode.isPersistedActive)

        DemoMode.isPersistedActive = false
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
