import Foundation
import SwiftData
import BackgroundTasks
import VesselCore

/// The single entry point for keeping the streak's reminders in sync.
///
/// Reads the current day out of SwiftData, then hands the same snapshot to both
/// the Live Activity and the notification scheduler. Everything that could
/// change the streak — launching, returning to the foreground, logging a meal,
/// changing the plan in Settings — funnels through `refresh()`, so the two
/// surfaces can never disagree about what day it is.
@MainActor
enum StreakCoordinator {

    /// Identifier declared in Info.plist under BGTaskSchedulerPermittedIdentifiers.
    static let backgroundTaskIdentifier = "com.sachinshankar.vessel.streakwatch"

    /// Recomputes the day and updates both reminder surfaces.
    static func refresh(context: ModelContext, now: Date = Date()) async {
        let profile = UserProfile.current(in: context)
        let engine = profile.makeStreakEngine()
        let plan = profile.fastingPlan

        // Only the days that could affect the current streak. Fetching the whole
        // history here would make every meal log progressively slower.
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: now) ?? now
        let descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.loggedAt >= cutoff },
            sortBy: [SortDescriptor(\.loggedAt, order: .reverse)]
        )
        let meals = (try? context.fetch(descriptor)) ?? []

        let snapshot = engine.snapshot(
            meals: meals,
            plan: plan,
            now: now,
            allowedRestDays: profile.allowedRestDaysPerWeek
        )

        await StreakActivityController.shared.reconcile(
            progress: snapshot.progress,
            streak: snapshot.streak,
            plan: plan,
            isEnabled: profile.liveActivityEnabled,
            leadTime: profile.streakWarningLeadTime,
            now: now
        )

        await StreakReminderScheduler.schedule(
            progress: snapshot.progress,
            streak: snapshot.streak,
            isEnabled: profile.streakReminderEnabled,
            leadTime: profile.streakWarningLeadTime,
            now: now
        )
    }

    // MARK: - Background refresh

    /// Registers the background task. Must run before the app finishes launching.
    static func registerBackgroundTask(container: ModelContainer) {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: backgroundTaskIdentifier,
            using: nil
        ) { task in
            Task { @MainActor in
                await refresh(context: container.mainContext)
                scheduleBackgroundRefresh(context: container.mainContext)
                task.setTaskCompleted(success: true)
            }
        }
    }

    /// Asks iOS to wake us near the moment the warning window opens.
    ///
    /// `earliestBeginDate` is a request, not a promise — iOS decides based on
    /// battery, usage patterns and thermal state, and may skip it entirely. That
    /// is exactly why the local notification exists alongside this.
    static func scheduleBackgroundRefresh(context: ModelContext, now: Date = Date()) {
        let profile = UserProfile.current(in: context)
        guard profile.liveActivityEnabled else { return }

        let engine = profile.makeStreakEngine()
        let warningOpens = engine.dayEnd(for: now).addingTimeInterval(-profile.streakWarningLeadTime)
        // If we're already past the opening, aim at tomorrow's instead.
        let target = warningOpens > now
            ? warningOpens
            : engine.dayEnd(for: now).addingTimeInterval(86_400 - profile.streakWarningLeadTime)

        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskIdentifier)
        request.earliestBeginDate = target

        // Throws when the identifier isn't registered or too many are queued;
        // neither should cost the user anything, so it fails quietly.
        try? BGTaskScheduler.shared.submit(request)
    }
}
