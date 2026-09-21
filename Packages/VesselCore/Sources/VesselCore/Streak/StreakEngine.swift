import Foundation

/// A single day's progress toward the streak requirement.
public struct DayProgress: Sendable, Equatable {
    /// Start of the streak day (respects the user's rollover hour, not midnight).
    public let dayStart: Date
    /// End of the streak day — the moment the streak resets.
    public let dayEnd: Date
    /// Distinct qualifying meal slots logged.
    public let slotsLogged: Set<MealSlot>
    /// How many are needed under the active plan.
    public let required: Int
    /// Meals logged outside the eating window on a time-restricted plan. Surfaced
    /// as information, never as a scolding — the goal is a log you trust.
    public let outsideWindowCount: Int

    public var logged: Int { slotsLogged.count }
    public var isQualified: Bool { logged >= required }
    public var remaining: Int { max(0, required - logged) }

    public var fraction: Double {
        guard required > 0 else { return 1 }
        return min(1, Double(logged) / Double(required))
    }

    /// Time left before the streak resets. Zero once the day has ended.
    public func timeRemaining(at now: Date = Date()) -> TimeInterval {
        max(0, dayEnd.timeIntervalSince(now))
    }

    public init(
        dayStart: Date,
        dayEnd: Date,
        slotsLogged: Set<MealSlot>,
        required: Int,
        outsideWindowCount: Int = 0
    ) {
        self.dayStart = dayStart
        self.dayEnd = dayEnd
        self.slotsLogged = slotsLogged
        self.required = required
        self.outsideWindowCount = outsideWindowCount
    }
}

/// The running streak.
public struct StreakState: Sendable, Equatable, Codable {
    public var current: Int
    public var longest: Int
    /// The last day that met the requirement, normalized to its day start.
    public var lastQualifiedDay: Date?
    /// Rest days spent this week, when the user has allowed any.
    public var restDaysUsedThisWeek: Int

    public init(
        current: Int = 0,
        longest: Int = 0,
        lastQualifiedDay: Date? = nil,
        restDaysUsedThisWeek: Int = 0
    ) {
        self.current = current
        self.longest = longest
        self.lastQualifiedDay = lastQualifiedDay
        self.restDaysUsedThisWeek = restDaysUsedThisWeek
    }

    public static let empty = StreakState()
}

/// The minimum a value needs to expose to be counted by the engine.
///
/// A protocol rather than the SwiftData model directly, so the rules can be
/// unit-tested with plain structs and no persistent container.
public protocol MealLoggable {
    var loggedAt: Date { get }
    var slot: MealSlot { get }
}

/// Computes day progress and streak length.
///
/// Every method is pure — same inputs, same outputs, no clock reads except the
/// `now` you pass in. That's deliberate: streak bugs are miserable to reproduce
/// otherwise, and "it broke at midnight on a DST boundary" needs to be a test,
/// not a bug report.
public struct StreakEngine: Sendable {

    /// The hour a streak day begins, 0–23. Midnight by default. People who
    /// regularly eat past midnight can push this later so a 1am snack still
    /// belongs to the night before.
    public let dayRolloverHour: Int
    public let calendar: Calendar

    public init(dayRolloverHour: Int = 0, calendar: Calendar = .current) {
        self.dayRolloverHour = min(max(dayRolloverHour, 0), 23)
        self.calendar = calendar
    }

    // MARK: - Day boundaries

    /// The start of the streak day containing `date`.
    ///
    /// Uses `nextDate(after:matching:)` rather than adding seconds, so days stay
    /// correct across daylight saving transitions — on a spring-forward day a
    /// "24 hour" addition lands an hour off, and the streak silently breaks.
    public func dayStart(for date: Date) -> Date {
        let midnight = calendar.startOfDay(for: date)
        guard let rollover = calendar.date(byAdding: .hour, value: dayRolloverHour, to: midnight) else {
            return midnight
        }
        if date >= rollover {
            return rollover
        }
        // Before today's rollover, so we're still in yesterday's streak day.
        let previousMidnight = calendar.date(byAdding: .day, value: -1, to: midnight) ?? midnight
        return calendar.date(byAdding: .hour, value: dayRolloverHour, to: previousMidnight) ?? previousMidnight
    }

    /// The moment the streak day containing `date` ends.
    public func dayEnd(for date: Date) -> Date {
        let start = dayStart(for: date)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
    }

    // MARK: - Progress

    /// Evaluates one day's meals against the plan.
    public func progress(
        for date: Date,
        meals: [some MealLoggable],
        plan: FastingPlan
    ) -> DayProgress {
        let start = dayStart(for: date)
        let end = dayEnd(for: date)
        let qualifying = Set(plan.qualifyingSlots)

        let todays = meals.filter { $0.loggedAt >= start && $0.loggedAt < end }

        // A Set of slots, not a count of entries — logging lunch twice is still
        // one meal toward the requirement.
        let slots = Set(todays.map(\.slot).filter { qualifying.contains($0) })

        let outside = todays.filter { !plan.isWithinEatingWindow($0.loggedAt, calendar: calendar) }.count

        return DayProgress(
            dayStart: start,
            dayEnd: end,
            slotsLogged: slots,
            required: max(1, plan.mealsRequired),
            outsideWindowCount: outside
        )
    }

    // MARK: - Streak

    /// Recomputes the streak from scratch over a set of qualified days.
    ///
    /// Rebuilding from history rather than incrementing a stored counter means a
    /// backdated entry, an edit, or a deletion all produce the right answer
    /// without a migration or a repair path.
    ///
    /// - Parameters:
    ///   - qualifiedDays: day-start dates that met the requirement.
    ///   - now: the moment to evaluate from.
    ///   - allowedRestDays: consecutive missed days tolerated before the streak
    ///     breaks. Zero (the default) means any miss resets it.
    public func streak(
        qualifiedDays: Set<Date>,
        now: Date = Date(),
        allowedRestDays: Int = 0
    ) -> StreakState {
        guard !qualifiedDays.isEmpty else { return .empty }

        let normalized = Set(qualifiedDays.map { dayStart(for: $0) })
        let sorted = normalized.sorted()

        // Longest run anywhere in history.
        var longest = 0
        var run = 0
        var previous: Date?
        for day in sorted {
            if let prev = previous, let gap = calendar.dateComponents([.day], from: prev, to: day).day {
                run = (gap - 1) <= allowedRestDays ? run + 1 : 1
            } else {
                run = 1
            }
            longest = max(longest, run)
            previous = day
        }

        // Current run, walking backward from today.
        let today = dayStart(for: now)
        var cursor = today
        var current = 0
        var restUsed = 0

        // Today not being logged yet doesn't break the streak — the day isn't
        // over. Start from yesterday in that case.
        if !normalized.contains(today) {
            cursor = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        }

        while normalized.contains(cursor) || restUsed < allowedRestDays {
            if normalized.contains(cursor) {
                current += 1
            } else {
                // Never let a rest day extend a streak that hasn't started.
                if current == 0 { break }
                restUsed += 1
            }
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }

        return StreakState(
            current: current,
            longest: max(longest, current),
            lastQualifiedDay: sorted.last,
            restDaysUsedThisWeek: restUsed
        )
    }

    /// Every day in `meals` that met the requirement.
    ///
    /// Derived rather than stored, so editing or deleting a past entry
    /// recomputes the streak correctly with no repair step.
    public func qualifiedDays(
        from meals: [some MealLoggable],
        plan: FastingPlan
    ) -> Set<Date> {
        let days = Set(meals.map { dayStart(for: $0.loggedAt) })
        return days.filter { progress(for: $0, meals: meals, plan: plan).isQualified }
    }

    /// Progress plus streak for the current moment, which is what every caller
    /// actually wants.
    public func snapshot(
        meals: [some MealLoggable],
        plan: FastingPlan,
        now: Date = Date(),
        allowedRestDays: Int = 0
    ) -> (progress: DayProgress, streak: StreakState) {
        let progress = progress(for: now, meals: meals, plan: plan)
        let streak = streak(
            qualifiedDays: qualifiedDays(from: meals, plan: plan),
            now: now,
            allowedRestDays: allowedRestDays
        )
        return (progress, streak)
    }

    /// Whether the streak is at risk right now: the day isn't met yet and we're
    /// inside the warning lead time. This is what starts the Live Activity.
    public func isAtRisk(
        progress: DayProgress,
        now: Date = Date(),
        leadTime: TimeInterval
    ) -> Bool {
        guard !progress.isQualified else { return false }
        let remaining = progress.timeRemaining(at: now)
        return remaining > 0 && remaining <= leadTime
    }
}
