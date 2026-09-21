import Foundation
import UserNotifications
import VesselCore

/// Schedules the local notification that warns the streak is about to lapse.
///
/// This is the *reliable* half of the reminder pair. A scheduled local
/// notification fires whether or not the app has run recently, which the Live
/// Activity cannot promise. See `StreakActivityController` for why both exist.
@MainActor
enum StreakReminderScheduler {

    private static let identifier = "vessel.streak.at-risk"

    /// Whether we're already allowed to post, without prompting.
    ///
    /// Scheduling must never trigger the permission dialog: `refresh()` runs on
    /// every launch and every meal logged, so prompting from there would throw
    /// the dialog at someone seconds after first opening the app, with no
    /// explanation of what they'd be agreeing to. People decline those.
    static func isAuthorized() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        switch status {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    /// Asks for permission. Called only from a deliberate user action — turning
    /// the reminder on in Settings — so the prompt arrives with obvious context.
    ///
    /// - Returns: whether we may post notifications afterwards.
    @discardableResult
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus

        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            // Already refused: iOS won't show the dialog again, and asking would
            // silently no-op. The caller surfaces a link to Settings instead.
            return false
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        @unknown default:
            return false
        }
    }

    /// Replaces any pending reminder with one for the current day.
    static func schedule(
        progress: DayProgress,
        streak: StreakState,
        isEnabled: Bool,
        leadTime: TimeInterval,
        now: Date = Date()
    ) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        // Nothing to warn about if it's off, already done, or the moment passed.
        guard isEnabled, !progress.isQualified else { return }
        // Silently skip when not yet authorized — permission is asked for in
        // Settings, never from here.
        guard await isAuthorized() else { return }

        let fireDate = progress.dayEnd.addingTimeInterval(-leadTime)
        guard fireDate > now else { return }

        let content = UNMutableNotificationContent()
        content.title = streak.current > 0
            ? "Your \(streak.current)-day streak needs one more meal"
            : "Finish today's log"
        content.body = Self.body(progress: progress)
        content.sound = .default
        // Opens straight into food logging rather than the app's last screen.
        content.userInfo = ["deepLink": "vessel://log/food"]

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, fireDate.timeIntervalSince(now)),
            repeats: false
        )

        try? await center.add(
            UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        )
    }

    private static func body(progress: DayProgress) -> String {
        let remaining = progress.remaining
        let meals = remaining == 1 ? "one more meal" : "\(remaining) more meals"
        return "Log \(meals) before the day resets to keep it going."
    }

    static func cancel() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
