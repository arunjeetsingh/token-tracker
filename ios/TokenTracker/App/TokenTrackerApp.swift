import SwiftUI

@main
struct TokenTrackerApp: App {
    var body: some Scene {
        WindowGroup {
            DashboardView()
        }
        // Background spend-alert check (opt-in). SwiftUI registers the handler
        // for this identifier; scheduling/cancelling happens in Settings when
        // the user toggles alerts. Reschedules itself after each run.
        .backgroundTask(.appRefresh(SpendAlertScheduler.taskIdentifier)) {
            await SpendAlertScheduler.handleBackgroundRefresh()
        }
    }
}
