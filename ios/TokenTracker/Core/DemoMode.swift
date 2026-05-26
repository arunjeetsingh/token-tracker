import Foundation

/// Launch-argument-driven demo mode for App Store screenshot capture.
///
/// When `-DemoMode YES` is passed on launch (UserDefaults reads command-line
/// args of the form `-key value` as defaults), the app skips the live Anthropic
/// API entirely and renders a fixed, realistic-looking month-to-date cost
/// report. No keys, no network calls, no personal data — exactly what we want
/// for App Store screenshots.
///
/// Usage from a screenshot script:
///   xcrun simctl launch <udid> ai.openclaw.tokentracker.TokenTracker -DemoMode YES
enum DemoMode {
    /// Magic key string an Apple App Reviewer (or anyone) can paste in
    /// onboarding to bypass the real Anthropic API and exercise the full UI
    /// against canned data. The year-month-week suffix lets us rotate this
    /// per release iteration if it leaks.
    static let appReviewKey = "sk-ant-demo-2026-05-w22"

    /// UserDefaults key under which we persist "reviewer pasted the magic
    /// key and is currently in demo mode." Persisting (vs. in-memory only)
    /// matters because App Review will kill+relaunch the app and expect
    /// the demo state to survive.
    private static let persistedKey = "TokenTracker.demoModeActive"

    /// Test seam: tests inject a private suite so they don't pollute
    /// `UserDefaults.standard`. Production reads `.standard`.
    static var defaultsOverride: UserDefaults?

    private static var defaults: UserDefaults {
        defaultsOverride ?? UserDefaults.standard
    }

    /// True when the app was launched with `-DemoMode YES`, any -DemoModeScreen
    /// value, OR when a reviewer previously activated demo mode by pasting
    /// the magic key (`appReviewKey`).
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "DemoMode") || screen != nil || isPersistedActive
    }

    /// Persisted "demo mode is active because someone pasted the magic key."
    /// Survives app launches. Cleared when the user taps Disconnect.
    static var isPersistedActive: Bool {
        get { defaults.bool(forKey: persistedKey) }
        set { defaults.set(newValue, forKey: persistedKey) }
    }

    /// Returns true if `candidate`, after trimming whitespace/newlines and
    /// lowercasing, equals `appReviewKey`. Case-insensitive because mobile
    /// keyboards love to autocorrect/auto-capitalize pasted strings.
    static func isReviewKey(_ candidate: String) -> Bool {
        let normalized = candidate.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        return normalized == appReviewKey
    }

    /// Optional screen-specific override: pass `-DemoModeScreen onboarding`
    /// to force the needs-credentials state for screenshotting the onboarding
    /// flow without writing to / reading from the simulator Keychain (which
    /// fails with errSecMissingEntitlement on unsigned simulator builds).
    enum Screen: String {
        case dashboard
        case onboarding
    }

    static var screen: Screen? {
        guard let raw = UserDefaults.standard.string(forKey: "DemoModeScreen") else { return nil }
        return Screen(rawValue: raw.lowercased())
    }

    /// A canned month-to-date report and org identity for screenshots.
    /// Numbers chosen to:
    ///   - Look like a real Anthropic account (4-digit MTD)
    ///   - Showcase the intra-day estimate (today's spend > $0)
    ///   - Use a generic org name ("Personal") so the screenshot doesn't
    ///     telegraph 'this is fake demo data'
    static func snapshot(now: Date = Date()) -> (orgName: String, report: MTDCost) {
        let todayEstimate = Money(cents: 312_88)      // $312.88
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let finalizedThrough = calendar.startOfDay(for: now)

        // 30 days of canned daily spend in cents — noisy but trending up,
        // "we're scaling" vibe. Sum ~= $7,800. Hero finalized is set to
        // exactly this sum so the sparkline + hero stay consistent.
        let dailyCents: [Int64] = [
            10_523, 11_247, 12_891,  9_856, 14_203, 15_672, 13_941, 16_808, 18_234, 17_456,
            19_872, 21_034, 20_156, 22_890, 24_561, 23_445, 26_012, 27_889, 25_678, 29_234,
            31_456, 30_123, 32_890, 34_567, 33_245, 35_678, 37_234, 36_012, 38_901, 40_234
        ]
        let daily: [DailySpend] = dailyCents.enumerated().map { idx, c in
            let date = calendar.date(byAdding: .day, value: -(dailyCents.count - 1 - idx), to: finalizedThrough)!
            return DailySpend(date: date, cost: Money(cents: c))
        }
        let finalizedSum = dailyCents.reduce(Int64(0), +)
        let finalized = Money(cents: finalizedSum)

        // Top-3 models: ~55% / ~30% / ~15% of the finalized total.
        // Use integer cent arithmetic; assign the rounding remainder to
        // the largest bucket so the three sum exactly to `finalized`.
        let opusCents = Int64(Double(finalizedSum) * 0.55)
        let sonnetCents = Int64(Double(finalizedSum) * 0.30)
        let haikuCents = Int64(Double(finalizedSum) * 0.15)
        let remainder = finalizedSum - (opusCents + sonnetCents + haikuCents)
        let modelBreakdown: [ModelSpend] = [
            .init(modelId: "claude-opus-4-5",   displayName: "Claude Opus 4.5",   cost: Money(cents: opusCents + remainder)),
            .init(modelId: "claude-sonnet-4-5", displayName: "Claude Sonnet 4.5", cost: Money(cents: sonnetCents)),
            .init(modelId: "claude-haiku-4-5",  displayName: "Claude Haiku 4.5",  cost: Money(cents: haikuCents))
        ]

        let report = MTDCost(
            finalizedCost: finalized,
            todayEstimatedCost: todayEstimate,
            unpricedModels: [],
            finalizedThrough: finalizedThrough,
            asOf: now,
            dailySpend: daily,
            modelBreakdown: modelBreakdown
        )
        return (orgName: "Personal", report: report)
    }
}
