import Foundation

/// Pure decision logic for the 90%-of-limit spend alert — no Android/iOS deps,
/// so it's unit testable. Swift sibling of the Android `SpendAlert` object. The
/// background check combines [atThreshold] with a once-per-[monthKey] dedupe.
enum SpendAlert {

    /// Fraction of the limit at which we notify.
    static let thresholdFraction = 0.90

    /// True when spend has reached ≥ 90% of a positive limit.
    static func atThreshold(spentCents: Int64, limitCents: Int64) -> Bool {
        guard limitCents > 0 else { return false }
        return Double(spentCents) / Double(limitCents) >= thresholdFraction
    }

    /// "yyyy-MM" (UTC) used to dedupe alerts to at most once per calendar month.
    static func monthKey(_ date: Date) -> String {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let comps = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", comps.year ?? 0, comps.month ?? 0)
    }
}
