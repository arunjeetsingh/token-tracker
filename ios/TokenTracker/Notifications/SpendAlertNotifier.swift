import Foundation
import UserNotifications

/// Requests notification permission and posts the local "spend approaching
/// limit" notification. Swift sibling of the Android `SpendAlertNotifier`.
enum SpendAlertNotifier {

    /// Prompts for notification permission. Returns whether it's granted —
    /// called only when the user turns the alert on.
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        return granted ?? false
    }

    /// Posts the alert immediately. No-ops if authorization was later revoked.
    static func notify(spentFormatted: String, percent: Int) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized ||
            settings.authorizationStatus == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = "Spend at \(percent)% of your limit"
        content.body = "\(spentFormatted) spent so far this month."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "spend-alert",
            content: content,
            trigger: nil // deliver now
        )
        try? await center.add(request)
    }
}
