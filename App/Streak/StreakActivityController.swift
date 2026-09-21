import Foundation
// ActivityKit's `Activity` class is not annotated for Swift 6 concurrency and is
// not Sendable, so awaiting its `update`/`end` methods from this MainActor type
// is rejected outright. The handle never actually leaves the main actor here —
// it is created, used and cleared in MainActor-isolated code — so importing the
// framework as pre-concurrency is the accurate description of the situation
// rather than a workaround.
@preconcurrency import ActivityKit
import VesselCore
import VesselActivities

/// Starts, updates and ends the streak Live Activity.
///
/// The honest limitation, stated once here so the rest of the app can stop
/// worrying about it: **iOS will not reliably wake a suspended app at a chosen
/// time to start a Live Activity.** Background refresh is opportunistic. So this
/// controller starts the activity whenever it legitimately can — on launch, on
/// foreground, after a log, and from a background refresh if the system grants
/// one — and `StreakReminderScheduler` posts a local notification at the
/// deadline as the guaranteed path. Between them the user always gets warned;
/// the island is the nicer of the two, not the load-bearing one.
@MainActor
final class StreakActivityController {

    static let shared = StreakActivityController()

    private init() {}

    private var activity: Activity<StreakActivityAttributes>?

    /// True when the user hasn't switched Live Activities off for Vessel in
    /// Settings, and the device supports them at all.
    var isAvailable: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// Brings the Live Activity in line with the current day.
    ///
    /// Safe to call as often as you like — it decides whether to start, update,
    /// end or do nothing, so callers don't have to track activity state.
    func reconcile(
        progress: DayProgress,
        streak: StreakState,
        plan: FastingPlan,
        isEnabled: Bool,
        leadTime: TimeInterval,
        now: Date = Date()
    ) async {
        adoptExistingActivityIfNeeded()

        guard isEnabled, isAvailable else {
            await endActivity(immediately: true)
            return
        }

        // A stale activity from a previous day must go, or the countdown shows a
        // deadline that has already passed.
        if let current = activity, current.attributes.deadline != progress.dayEnd {
            await endActivity(immediately: true)
        }

        let state = StreakActivityAttributes.ContentState(
            logged: progress.logged,
            streakCount: streak.current,
            nextSlotName: nextSlotName(for: progress, plan: plan, now: now)
        )

        if progress.isQualified {
            // Show the completed state briefly rather than yanking it away the
            // instant the goal is met — the confirmation is the reward.
            if activity != nil {
                await update(state: state, deadline: progress.dayEnd)
                await endActivity(immediately: false)
            }
            return
        }

        let timeLeft = progress.timeRemaining(at: now)
        let withinWarningWindow = timeLeft > 0 && timeLeft <= leadTime

        if activity != nil {
            await update(state: state, deadline: progress.dayEnd)
        } else if withinWarningWindow {
            await start(progress: progress, plan: plan, state: state)
        }
    }

    // MARK: - Lifecycle

    private func start(
        progress: DayProgress,
        plan: FastingPlan,
        state: StreakActivityAttributes.ContentState
    ) async {
        let attributes = StreakActivityAttributes(
            deadline: progress.dayEnd,
            required: progress.required,
            planName: plan.style.title
        )

        do {
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: progress.dayEnd),
                // No push token: updates come from the app process. Remote
                // updates would need APNs, which a free account can't use.
                pushType: nil
            )
        } catch {
            // Most often: the user disabled Live Activities, or too many are
            // already running. Neither is worth interrupting them over — the
            // notification still fires.
            activity = nil
        }
    }

    private func update(state: StreakActivityAttributes.ContentState, deadline: Date) async {
        guard let activity else { return }
        await activity.update(ActivityContent(state: state, staleDate: deadline))
    }

    func endActivity(immediately: Bool) async {
        guard let activity else { return }
        await activity.end(
            nil,
            dismissalPolicy: immediately ? .immediate : .after(.now.addingTimeInterval(8 * 60))
        )
        self.activity = nil
    }

    /// Reattaches to an activity that outlived the app process.
    ///
    /// Without this, relaunching the app would lose the handle and then start a
    /// second activity alongside the first.
    private func adoptExistingActivityIfNeeded() {
        guard activity == nil else { return }
        activity = Activity<StreakActivityAttributes>.activities.first
    }

    /// The meal we'd expect next, so the island can say "Log dinner" instead of
    /// "1 meal left".
    private func nextSlotName(for progress: DayProgress, plan: FastingPlan, now: Date) -> String? {
        let outstanding = plan.qualifyingSlots.filter { !progress.slotsLogged.contains($0) }
        guard !outstanding.isEmpty else { return nil }

        // Prefer the slot that matches the time of day, falling back to the
        // earliest unlogged one so we never suggest breakfast at 11pm.
        let inferred = MealSlot.inferred(from: now)
        if outstanding.contains(inferred) { return inferred.title }
        return outstanding.last?.title
    }
}
