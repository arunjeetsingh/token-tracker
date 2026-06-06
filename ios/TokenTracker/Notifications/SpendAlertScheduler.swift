import BackgroundTasks
import Foundation

/// Schedules and runs the background spend-alert check. Swift sibling of the
/// Android `SpendAlertScheduler` + `SpendAlertWorker` (WorkManager).
///
/// The handler itself is registered by SwiftUI's `.backgroundTask(.appRefresh:)`
/// scene modifier (see `TokenTrackerApp`); this type owns the identifier, the
/// scheduling requests, and the check logic. There's no backend to push from —
/// this is the app re-checking its own usage on an OS-scheduled wakeup.
enum SpendAlertScheduler {

    static let taskIdentifier = "ai.openclaw.tokentracker.spendalert"

    /// Roughly how far out to ask the OS to wake us (it decides the real time).
    private static let interval: TimeInterval = 6 * 60 * 60

    /// Submit a refresh request. Submitting again replaces the pending one.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
    }

    /// Entry point from the `.backgroundTask` handler: reschedule the next run,
    /// then perform the check.
    static func handleBackgroundRefresh() async {
        schedule()
        await SpendAlertChecker().run()
    }
}

/// The actual check: re-reads all preconditions (they can change between
/// schedules), fetches MTD cost, and posts once per month at ≥90%. Mirrors
/// `SpendAlertWorker.doWork()` on Android.
struct SpendAlertChecker {
    var prefs: NotificationPreferenceStoring = LiveNotificationPrefs()
    var spendLimits: SpendLimitStoring = LiveSpendLimitStore()
    var credentials: CredentialStoring = LiveCredentialStore()
    var cost: CostProviding = LiveCostProvider()
    /// Demo mode never wrote a real key — nothing to fetch.
    var isDemoActive: () -> Bool = { DemoMode.isPersistedActive }

    func run() async {
        guard prefs.alertEnabled else { return }
        guard let limitCents = spendLimits.limitCents else { return }
        if isDemoActive() { return }
        guard let key = (try? credentials.load()) ?? nil, !key.isEmpty else { return }
        guard let report = try? await cost.monthToDateCost(apiKey: key) else { return }

        let spent = report.total.cents
        guard SpendAlert.atThreshold(spentCents: spent, limitCents: limitCents) else { return }

        let month = SpendAlert.monthKey(report.finalizedThrough)
        var mutablePrefs = prefs
        if mutablePrefs.lastAlertedMonth == month { return }

        let percent = Int((Double(spent) / Double(limitCents) * 100).rounded())
        await SpendAlertNotifier.notify(spentFormatted: report.total.formatted(), percent: percent)
        mutablePrefs.lastAlertedMonth = month
    }
}
