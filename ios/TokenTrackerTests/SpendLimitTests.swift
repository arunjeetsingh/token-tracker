import XCTest
@testable import TokenTracker

final class SpendLimitTests: XCTestCase {

    private func utcDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testProgressFraction_clampsAndGuardsZeroLimit() {
        XCTAssertEqual(SpendLimit.progressFraction(spentCents: 50_000, limitCents: 100_000), 0.5, accuracy: 0.0001)
        XCTAssertEqual(SpendLimit.progressFraction(spentCents: 150_000, limitCents: 100_000), 1.0, accuracy: 0.0001)
        XCTAssertEqual(SpendLimit.progressFraction(spentCents: 50_000, limitCents: 0), 0.0, accuracy: 0.0001)
    }

    func testPercentUsed_isNotCapped() {
        XCTAssertEqual(SpendLimit.percentUsed(spentCents: 50_000, limitCents: 100_000), 50)
        XCTAssertEqual(SpendLimit.percentUsed(spentCents: 150_000, limitCents: 100_000), 150)
        XCTAssertEqual(SpendLimit.percentUsed(spentCents: 50_000, limitCents: 0), 0)
    }

    func testSeverity_crossesAt80And100() {
        XCTAssertEqual(SpendLimit.severity(spentCents: 50_000, limitCents: 100_000), .normal)
        XCTAssertEqual(SpendLimit.severity(spentCents: 85_000, limitCents: 100_000), .approaching)
        XCTAssertEqual(SpendLimit.severity(spentCents: 100_000, limitCents: 100_000), .over)
        XCTAssertEqual(SpendLimit.severity(spentCents: 120_000, limitCents: 0), .normal)
    }

    func testSeverity_usesRawRatioNotRoundedPercent() {
        // 79.5% rounds to 80 for display but must NOT flip to .approaching.
        XCTAssertEqual(SpendLimit.severity(spentCents: 79_500, limitCents: 100_000), .normal)
        XCTAssertEqual(SpendLimit.severity(spentCents: 80_000, limitCents: 100_000), .approaching)
        // 99.5% rounds to 100 for display but must stay .approaching, not .over.
        XCTAssertEqual(SpendLimit.severity(spentCents: 99_500, limitCents: 100_000), .approaching)
        XCTAssertEqual(SpendLimit.severity(spentCents: 100_000, limitCents: 100_000), .over)
    }

    func testNextResetDate_isFirstOfFollowingMonth() {
        XCTAssertEqual(SpendLimit.nextResetDate(after: utcDate(2026, 6, 6)), utcDate(2026, 7, 1))
        XCTAssertEqual(SpendLimit.nextResetDate(after: utcDate(2026, 12, 15)), utcDate(2027, 1, 1))
    }

    func testResetDateText_formattedInUTC() {
        // The reset is a UTC month boundary; formatting must use UTC so a
        // negative-offset device doesn't show the previous day.
        XCTAssertEqual(SpendLimit.resetDateText(after: utcDate(2026, 6, 15)), "Jul 1, 2026")
        XCTAssertEqual(SpendLimit.resetDateText(after: utcDate(2026, 12, 31)), "Jan 1, 2027")
    }
}
