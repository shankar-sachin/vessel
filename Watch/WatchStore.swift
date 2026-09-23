import Foundation
import Observation
import UserNotifications
import WatchConnectivity
import VesselCore

/// The watch's view of the day, and its outbox.
///
/// Nothing is stored here except what the phone last reported and what has
/// been sent since. Logs travel with `transferUserInfo`, which the system
/// queues and delivers when the phone is next reachable — so logging works
/// with the phone out of range, and the face adds what's still in flight on
/// top of the phone's last numbers until the phone confirms them.
@MainActor
@Observable
final class WatchStore: NSObject {

    static let shared = WatchStore()

    /// What the phone last said about today.
    private(set) var summary: WatchSummary?
    /// Sent since that summary, not yet reflected in it.
    private(set) var pending: [WatchMessage] = []

    var remindersEnabled: Bool {
        didSet {
            UserDefaults.standard.set(remindersEnabled, forKey: Keys.reminders)
            if remindersEnabled { Task { await requestNotificationPermission() } }
            scheduleReminders()
        }
    }

    private enum Keys {
        static let summary = "watch.summary"
        static let pending = "watch.pending"
        static let reminders = "watch.reminders"
    }

    override init() {
        remindersEnabled = UserDefaults.standard.bool(forKey: Keys.reminders)
        super.init()
        if let data = UserDefaults.standard.data(forKey: Keys.summary) {
            summary = try? JSONDecoder().decode(WatchSummary.self, from: data)
        }
        if let data = UserDefaults.standard.data(forKey: Keys.pending) {
            pending = (try? JSONDecoder().decode([WatchMessage].self, from: data)) ?? []
        }
    }

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Today, including what's in flight

    private var todayStart: Date { Calendar.current.startOfDay(for: Date()) }

    /// The phone's numbers only if they're about today.
    private var current: WatchSummary? {
        guard let summary, summary.isCurrent(dayStart: todayStart) else { return nil }
        return summary
    }

    var waterML: Double {
        (current?.waterML ?? 0) + pending.reduce(0) { total, message in
            if case .water(_, let ml, _) = message { return total + ml }
            return total
        }
    }

    var waterGoalML: Double { summary?.waterGoalML ?? 2000 }
    var kilocalories: Double { current?.kilocalories ?? 0 }
    var kilocalorieGoal: Double? { summary?.kilocalorieGoal }
    var streakDays: Int { summary?.streakDays ?? 0 }
    var mealsRequired: Int { summary?.mealsRequired ?? 3 }
    var mealsLogged: Int { current?.mealsLogged ?? 0 }
    var pendingMeals: Int {
        pending.filter { if case .log = $0 { return true } else { return false } }.count
    }

    // MARK: - Sending

    func logWater(_ millilitres: Double) {
        send(.water(id: UUID(), millilitres: millilitres, at: Date()))
    }

    func log(_ text: String) {
        send(.log(id: UUID(), text: text, at: Date()))
    }

    private func send(_ message: WatchMessage) {
        pending.append(message)
        persist()
        if WCSession.isSupported(), let payload = try? message.encoded() {
            WCSession.default.transferUserInfo(payload)
        }
    }

    private func receive(_ new: WatchSummary) {
        summary = new
        // The phone's numbers now include everything sent before it counted.
        pending.removeAll { message in
            switch message {
            case .log(_, _, let at), .water(_, _, let at): return at <= new.updatedAt
            }
        }
        persist()
        scheduleReminders()
    }

    private func persist() {
        UserDefaults.standard.set(try? JSONEncoder().encode(summary), forKey: Keys.summary)
        UserDefaults.standard.set(try? JSONEncoder().encode(pending), forKey: Keys.pending)
    }

    // MARK: - Meal reminders

    /// A tap on the wrist at the next meal still missing today — only for
    /// meals the streak needs, and only if the person turned reminders on.
    func scheduleReminders(now: Date = Date()) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard remindersEnabled else { return }

        let logged = Set(current?.slotsLogged ?? [])
        let times: [(MealSlot, Int, Int)] = [(.breakfast, 9, 0), (.lunch, 13, 0), (.dinner, 19, 0)]
        for (slot, hour, minute) in times.prefix(mealsRequired) where !logged.contains(slot.rawValue) {
            guard let fire = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: now),
                  fire > now else { continue }
            let content = UNMutableNotificationContent()
            content.title = "\(slot.title) time"
            content.body = "Raise to log what you're having."
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: Calendar.current.dateComponents([.hour, .minute], from: fire),
                repeats: false
            )
            center.add(UNNotificationRequest(identifier: "meal.\(slot.rawValue)", content: content, trigger: trigger))
        }
    }

    private func requestNotificationPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }
}

extension WatchStore: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        guard let summary = WatchSummary(context: session.receivedApplicationContext) else { return }
        Task { @MainActor in self.receive(summary) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        guard let summary = WatchSummary(context: context) else { return }
        Task { @MainActor in self.receive(summary) }
    }
}
