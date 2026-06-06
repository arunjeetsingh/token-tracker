import XCTest
@testable import TokenTracker

final class SpendAlertTests: XCTestCase {

    private func utcDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testAtThreshold_trueAtOrAbove90Percent() {
        XCTAssertFalse(SpendAlert.atThreshold(spentCents: 89_999, limitCents: 100_000))
        XCTAssertTrue(SpendAlert.atThreshold(spentCents: 90_000, limitCents: 100_000))
        XCTAssertTrue(SpendAlert.atThreshold(spentCents: 100_000, limitCents: 100_000))
        XCTAssertTrue(SpendAlert.atThreshold(spentCents: 150_000, limitCents: 100_000))
    }

    func testAtThreshold_guardsNonPositiveLimit() {
        XCTAssertFalse(SpendAlert.atThreshold(spentCents: 90_000, limitCents: 0))
        XCTAssertFalse(SpendAlert.atThreshold(spentCents: 90_000, limitCents: -5))
    }

    func testMonthKey_isYearMonthUTC() {
        XCTAssertEqual(SpendAlert.monthKey(utcDate(2026, 6, 6)), "2026-06")
        XCTAssertEqual(SpendAlert.monthKey(utcDate(2026, 12, 31)), "2026-12")
    }
}
