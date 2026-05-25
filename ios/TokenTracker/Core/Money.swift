import Foundation

/// USD amount with cents precision. Used to normalize Anthropic's
/// `cost_report.amount` field, which is a string of cents despite the
/// `currency: "USD"` label (see ADR-005).
struct Money: Hashable, Codable {
    /// Whole cents. Internal representation to avoid Float drift.
    let cents: Int64

    static let zero = Money(cents: 0)

    init(cents: Int64) {
        self.cents = cents
    }

    /// Construct from the Anthropic API's stringified cents value (e.g. "2013.9595").
    /// Fractions of a cent are truncated toward zero. Callers that need more
    /// precision should keep the Decimal.
    static func fromAnthropicCentsString(_ raw: String) -> Money? {
        guard let dec = Decimal(string: raw) else { return nil }
        let truncated = (dec * 100 as NSDecimalNumber).int64Value / 100
        return Money(cents: truncated)
    }

    var dollars: Decimal {
        Decimal(cents) / 100
    }

    func formatted(locale: Locale = .current) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.locale = locale
        return f.string(from: dollars as NSDecimalNumber) ?? "$\(dollars)"
    }

    static func + (lhs: Money, rhs: Money) -> Money {
        Money(cents: lhs.cents + rhs.cents)
    }

    static func += (lhs: inout Money, rhs: Money) {
        lhs = lhs + rhs
    }

    /// Convert a Decimal USD amount (e.g. 19.8093 dollars) to Money. Rounds
    /// to the nearest whole cent using bankers' rounding so half-cent splits
    /// don't bias the running total.
    static func fromDollars(_ dollars: Decimal) -> Money {
        var scaled = dollars * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .bankers)
        let cents = (rounded as NSDecimalNumber).int64Value
        return Money(cents: cents)
    }
}
