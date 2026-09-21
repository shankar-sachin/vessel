import Foundation

#if os(iOS)
import ActivityKit
#endif

/// The shape of the streak Live Activity, shared by the app (which starts and
/// updates it) and the widget extension (which draws it).
///
/// It lives in its own package precisely because two binaries need the identical
/// type: ActivityKit matches activities by type identity, so a copy-pasted
/// duplicate in each target would silently fail to connect at runtime.
///
/// Note this carries no App Group and reads no shared file. Everything the
/// Dynamic Island shows is passed through `ContentState`, which is why the
/// feature works on a free developer account where App Groups are unavailable.
public struct StreakActivityAttributes: Sendable, Hashable, Codable {

    /// When today's streak resets. Drives the countdown, and never changes while
    /// the activity is alive — a new day gets a new activity.
    public let deadline: Date

    /// Meals needed today under the user's plan.
    public let required: Int

    /// A label for the plan, e.g. "Three meals a day".
    public let planName: String

    public init(deadline: Date, required: Int, planName: String) {
        self.deadline = deadline
        self.required = required
        self.planName = planName
    }

    /// Everything that can change while the activity is on screen.
    ///
    /// Kept to three small fields: every update is an IPC round trip to the
    /// system, and ActivityKit budgets how often an app may push them.
    public struct ContentState: Sendable, Hashable, Codable {
        /// Distinct qualifying meal slots logged so far today.
        public var logged: Int
        /// The streak that's on the line.
        public var streakCount: Int
        /// The next meal we expect, so the island can name it rather than saying
        /// a bare number.
        public var nextSlotName: String?

        public init(logged: Int, streakCount: Int, nextSlotName: String? = nil) {
            self.logged = logged
            self.streakCount = streakCount
            self.nextSlotName = nextSlotName
        }
    }
}

#if os(iOS)
extension StreakActivityAttributes: ActivityAttributes {}
#endif

// MARK: - Presentation helpers

public extension StreakActivityAttributes {
    /// How many meals are still outstanding for a given state.
    func remaining(for state: ContentState) -> Int {
        max(0, required - state.logged)
    }

    func isComplete(_ state: ContentState) -> Bool {
        state.logged >= required
    }
}

/// Copy shown in the Live Activity.
///
/// Held here rather than in the widget so the app and the extension can't drift
/// apart, and so the wording is reviewable in one place — this text appears on a
/// lock screen, which is about as high-stakes as microcopy gets.
public enum StreakActivityCopy {

    public static func headline(logged: Int, required: Int, streak: Int) -> String {
        if logged >= required {
            return streak > 0 ? "\(streak)-day streak safe" : "Today is logged"
        }
        return streak > 0 ? "\(streak)-day streak at risk" : "Keep today going"
    }

    public static func detail(logged: Int, required: Int, nextSlot: String?) -> String {
        let remaining = max(0, required - logged)
        guard remaining > 0 else { return "Nothing left to log today." }
        if let nextSlot {
            return remaining == 1 ? "Log \(nextSlot) to finish" : "\(remaining) meals left, starting with \(nextSlot)"
        }
        return remaining == 1 ? "1 meal left today" : "\(remaining) meals left today"
    }

    /// The compact trailing label fits roughly five characters, so this stays
    /// terse on purpose.
    public static func compactProgress(logged: Int, required: Int) -> String {
        "\(logged)/\(required)"
    }
}
