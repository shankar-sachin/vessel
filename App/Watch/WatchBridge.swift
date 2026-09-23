import Foundation
import SwiftData
import WatchConnectivity
import VesselCore
import VesselIntelligence
import VesselIntents

/// The phone's end of the conversation with the watch.
///
/// Receives what was said on the wrist and saves it through `EntryWriter` —
/// the same path as Quick log and Siri — then sends back today's summary so
/// the watch face is current. The summary is also pushed whenever the streak
/// is refreshed, which every logging path already does.
@MainActor
final class WatchBridge: NSObject {

    static let shared = WatchBridge()

    private var container: ModelContainer?

    /// Ids of messages already saved. `transferUserInfo` delivers reliably but
    /// can deliver twice across a relaunch; saving a meal twice would count it
    /// twice toward the streak.
    private var handled: [String] {
        get { UserDefaults.standard.stringArray(forKey: "watch.handledMessages") ?? [] }
        set { UserDefaults.standard.set(Array(newValue.suffix(500)), forKey: "watch.handledMessages") }
    }

    func start(container: ModelContainer) {
        self.container = container
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Sends today's numbers to the watch. Cheap and idempotent: the system
    /// keeps only the latest application context.
    func pushSummary(context: ModelContext) {
        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated,
              WCSession.default.isPaired, WCSession.default.isWatchAppInstalled
        else { return }
        let intake = IntakeSummary.today(in: context)
        let profile = UserProfile.current(in: context)
        let engine = profile.makeStreakEngine()
        let progress = engine.progress(
            for: Date(),
            meals: (try? context.fetch(FetchDescriptor<FoodEntry>())) ?? [],
            plan: profile.fastingPlan
        )
        let summary = WatchSummary(
            streakDays: intake.streakDays,
            mealsLogged: intake.mealsLogged,
            mealsRequired: intake.mealsRequired,
            slotsLogged: progress.slotsLogged.map(\.rawValue),
            kilocalories: intake.kilocalories,
            kilocalorieGoal: intake.kilocalorieGoal,
            waterML: intake.waterML,
            waterGoalML: intake.waterGoalML,
            updatedAt: Date()
        )
        if let payload = try? summary.encoded() {
            try? WCSession.default.updateApplicationContext(payload)
        }
    }

    /// Saves one message from the watch, once.
    func handle(_ message: WatchMessage) async {
        guard let container, !handled.contains(message.id.uuidString) else { return }
        let context = container.mainContext

        switch message {
        case .log(_, let text, let at):
            var parsed = ParsePipeline().parse(text)
            // Said on the wrist at a known moment; a time in the words wins.
            if parsed.occurredAt == nil { parsed.occurredAt = at }
            EntryWriter(context: context).write(parsed, source: .watch)
        case .water(_, let millilitres, let at):
            context.insert(WaterEntry(loggedAt: at, volumeML: millilitres, source: .watch, containerName: "Water"))
            try? context.save()
        }
        handled.append(message.id.uuidString)

        await StreakCoordinator.refresh(context: context)
    }
}

extension WatchBridge: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            if let context = self.container?.mainContext { self.pushSummary(context: context) }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let message = WatchMessage(userInfo: userInfo) else { return }
        Task { @MainActor in await self.handle(message) }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Switching to another watch: reactivate so the new one is reached.
        session.activate()
    }
}
