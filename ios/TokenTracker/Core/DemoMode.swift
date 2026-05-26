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
    /// True when the app was launched with `-DemoMode YES` or any -DemoModeScreen value.
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "DemoMode") || screen != nil
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
        let finalized = Money(cents: 4_847_23)        // $4,847.23
        let todayEstimate = Money(cents: 312_88)      // $312.88
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let finalizedThrough = calendar.startOfDay(for: now)

        let report = MTDCost(
            finalizedCost: finalized,
            todayEstimatedCost: todayEstimate,
            unpricedModels: [],
            finalizedThrough: finalizedThrough,
            asOf: now
        )
        return (orgName: "Personal", report: report)
    }
}
