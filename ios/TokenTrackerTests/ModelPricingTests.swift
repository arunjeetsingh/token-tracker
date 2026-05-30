import XCTest
@testable import TokenTracker

final class ModelPricingTests: XCTestCase {

    func testOpus4_7LooksUpAsModernPricing() {
        let p = ModelPricing.lookup("claude-opus-4-7")
        XCTAssertEqual(p, ModelPricing.opus4_5)
    }

    func testOpus4PrefixDoesNotShadow4_7() {
        // Regression: longest-prefix match means opus-4-7 wins over opus-4.
        let p47 = ModelPricing.lookup("claude-opus-4-7")
        let p4 = ModelPricing.lookup("claude-opus-4")
        XCTAssertEqual(p47, ModelPricing.opus4_5)
        XCTAssertEqual(p4, ModelPricing.opus4_1)
    }

    func testOpus4_8DatedIdDoesNotFallThroughToLegacy() {
        // Regression: a dated opus-4-8 id must match the current Opus 4.5+ rate,
        // not fall through to the legacy `claude-opus-4` ($15/$75) entry.
        let p = ModelPricing.lookup("claude-opus-4-8-20260115")
        XCTAssertEqual(p, ModelPricing.opus4_5)
    }

    func testSonnetAndHaikuPricing() {
        XCTAssertEqual(ModelPricing.lookup("claude-sonnet-4-5"), ModelPricing.sonnet4)
        XCTAssertEqual(ModelPricing.lookup("claude-haiku-4-5"), ModelPricing.haiku4_5)
        XCTAssertEqual(ModelPricing.lookup("claude-3-5-haiku-20241022"), ModelPricing.haiku3_5)
    }

    func testUnknownModelReturnsNil() {
        XCTAssertNil(ModelPricing.lookup("claude-future-9000"))
        XCTAssertNil(ModelPricing.lookup(""))
    }

    func testTokenUsageCostMatchesOurLiveProbe() {
        // Captured from a real usage_report/messages call against Arun's org
        // on 2026-05-24: 240 uncached_input + 2,033,453 5m cache writes +
        // 11,185,860 cache reads + 60,244 output tokens, all on opus-4-7.
        // Our python probe computed $19.8093.
        let usage = TokenUsage(
            uncachedInputTokens: 240,
            cacheWrite5mTokens: 2_033_453,
            cacheWrite1hTokens: 0,
            cacheReadTokens: 11_185_860,
            outputTokens: 60_244
        )
        let cost = usage.cost(at: ModelPricing.opus4_5)
        // Expected: 240/1M*5 + 2,033,453/1M*6.25 + 11,185,860/1M*0.5 + 60,244/1M*25
        //         = 0.0012 + 12.7090812 + 5.59293 + 1.5061 = 19.8093112
        // Allow small Decimal-vs-Double rounding tolerance.
        let expected = Decimal(string: "19.8093")!  // swiftlint:disable:this force_unwrapping
        let diff = (cost - expected) as NSDecimalNumber
        XCTAssertLessThan(abs(diff.doubleValue), 0.001, "got \(cost), expected ~\(expected)")
    }

    func testFromDollarsRoundsToCents() {
        XCTAssertEqual(Money.fromDollars(Decimal(string: "19.8093")!).cents, 1981)
        XCTAssertEqual(Money.fromDollars(Decimal(string: "0.005")!).cents, 0)   // bankers: to even
        XCTAssertEqual(Money.fromDollars(Decimal(string: "0.015")!).cents, 2)   // bankers: to even
        XCTAssertEqual(Money.fromDollars(.zero).cents, 0)
    }
}
