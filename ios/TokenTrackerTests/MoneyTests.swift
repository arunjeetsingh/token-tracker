import XCTest
@testable import TokenTracker

final class MoneyTests: XCTestCase {
    func testFromAnthropicCentsStringTruncatesSubCent() {
        // ADR-005: the API returns cents as a string with fractional cents.
        let m = Money.fromAnthropicCentsString("2013.9595")
        XCTAssertEqual(m?.cents, 2013)
        XCTAssertEqual(m?.dollars, Decimal(string: "20.13"))
    }

    func testAddition() {
        let a = Money(cents: 100)
        let b = Money(cents: 250)
        XCTAssertEqual((a + b).cents, 350)
    }

    func testInPlaceAddition() {
        var total = Money.zero
        total += Money(cents: 17943)
        total += Money(cents: 20100)
        total += Money(cents: 16875)
        total += Money(cents: 1154)
        // Real MTD snapshot from 2026-05-23: 56,073 cents == $560.73
        XCTAssertEqual(total.cents, 56_072)
        XCTAssertEqual(total.formatted(locale: Locale(identifier: "en_US")), "$560.72")
    }

    func testZeroFormat() {
        XCTAssertEqual(Money.zero.formatted(locale: Locale(identifier: "en_US")), "$0.00")
    }

    func testNegativeFromInvalidString() {
        XCTAssertNil(Money.fromAnthropicCentsString("not a number"))
    }
}
