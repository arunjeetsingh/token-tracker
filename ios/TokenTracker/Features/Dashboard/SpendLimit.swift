import Foundation

/// Pure helpers for the spend-limit gauge — no SwiftUI, so they're unit
/// testable. Swift sibling of the Android `SpendLimit` object.
enum SpendLimit {

    /// Where the bar sits, 0...1. Zero / non-positive limit → 0 (no divide).
    static func progressFraction(spentCents: Int64, limitCents: Int64) -> Double {
        guard limitCents > 0 else { return 0 }
        return min(max(Double(spentCents) / Double(limitCents), 0), 1)
    }

    /// Percent of the limit used, rounded. NOT capped — can exceed 100.
    static func percentUsed(spentCents: Int64, limitCents: Int64) -> Int {
        guard limitCents > 0 else { return 0 }
        return Int((Double(spentCents) / Double(limitCents) * 100).rounded())
    }

    enum Severity { case normal, approaching, over }

    /// `.approaching` at ≥80% of the limit, `.over` at ≥100%.
    static func severity(spentCents: Int64, limitCents: Int64) -> Severity {
        guard limitCents > 0 else { return .normal }
        let pct = percentUsed(spentCents: spentCents, limitCents: limitCents)
        if pct >= 100 { return .over }
        if pct >= 80 { return .approaching }
        return .normal
    }

    /// First of the month after `date` (UTC) — spend is MTD, so the gauge
    /// "resets" at the next month boundary.
    static func nextResetDate(after date: Date) -> Date {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let comps = calendar.dateComponents([.year, .month], from: date)
        let firstOfMonth = calendar.date(from: comps) ?? date
        return calendar.date(byAdding: .month, value: 1, to: firstOfMonth) ?? date
    }
}
