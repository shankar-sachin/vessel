import Foundation

/// How many meals a day counts as "logged", and when you're allowed to eat them.
///
/// The streak exists to reward consistent *logging*, so the plan has to match how
/// the person actually eats. Holding someone on one meal a day to a three-meal
/// streak would punish them for following their own plan, which is the fastest
/// way to get an app deleted.
public struct FastingPlan: Codable, Sendable, Hashable, Identifiable {

    public enum Style: String, Codable, Sendable, CaseIterable, Identifiable {
        /// Three meals a day. The default.
        case standard
        /// Two meals — commonly breakfast skipped.
        case twoMeals
        /// One meal a day.
        case omad
        /// Time-restricted eating: all meals must fall inside a daily window
        /// (16:8, 18:6, and so on).
        case timeRestricted
        /// User-defined meal count.
        case custom

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .standard:       return "Three meals a day"
            case .twoMeals:       return "Two meals a day"
            case .omad:           return "One meal a day"
            case .timeRestricted: return "Time-restricted eating"
            case .custom:         return "Custom"
            }
        }

        public var detail: String {
            switch self {
            case .standard:       return "Log breakfast, lunch and dinner to keep your streak."
            case .twoMeals:       return "Log any two main meals to keep your streak."
            case .omad:           return "Log your one meal to keep your streak."
            case .timeRestricted: return "Log your meals inside your eating window."
            case .custom:         return "Set your own number of meals."
            }
        }
    }

    public var id: String { style.rawValue }

    public var style: Style

    /// Distinct meal slots required in a day. Derived from `style` for the preset
    /// plans, freely set for `.custom`.
    public var mealsRequired: Int

    /// Length of the eating window in hours. `nil` means no window constraint.
    /// Only meaningful for `.timeRestricted`.
    public var eatingWindowHours: Double?

    /// When the eating window opens, as minutes after local midnight.
    public var eatingWindowStartMinute: Int?

    /// Whether snacks can satisfy the requirement. Off by default, so three
    /// separate snacks don't quietly count as three meals.
    public var countsSnacks: Bool

    public init(
        style: Style = .standard,
        mealsRequired: Int = 3,
        eatingWindowHours: Double? = nil,
        eatingWindowStartMinute: Int? = nil,
        countsSnacks: Bool = false
    ) {
        self.style = style
        self.mealsRequired = mealsRequired
        self.eatingWindowHours = eatingWindowHours
        self.eatingWindowStartMinute = eatingWindowStartMinute
        self.countsSnacks = countsSnacks
    }

    // MARK: - Presets

    public static let standard = FastingPlan(style: .standard, mealsRequired: 3)
    public static let twoMeals = FastingPlan(style: .twoMeals, mealsRequired: 2)
    public static let omad = FastingPlan(style: .omad, mealsRequired: 1, countsSnacks: true)

    /// 16:8 — an eight-hour window, conventionally noon to 8pm.
    public static let sixteenEight = FastingPlan(
        style: .timeRestricted,
        mealsRequired: 2,
        eatingWindowHours: 8,
        eatingWindowStartMinute: 12 * 60
    )

    /// 18:6 — a six-hour window.
    public static let eighteenSix = FastingPlan(
        style: .timeRestricted,
        mealsRequired: 2,
        eatingWindowHours: 6,
        eatingWindowStartMinute: 13 * 60,
        countsSnacks: true
    )

    public static let presets: [FastingPlan] = [standard, twoMeals, sixteenEight, eighteenSix, omad]

    // MARK: - Derived

    /// Which slots can count toward the requirement under this plan.
    public var qualifyingSlots: [MealSlot] {
        countsSnacks ? MealSlot.allCases : MealSlot.primarySlots
    }

    /// Human-readable window, e.g. "12:00 – 20:00". `nil` when unconstrained.
    public var windowDescription: String? {
        guard let hours = eatingWindowHours, let start = eatingWindowStartMinute else { return nil }
        let endMinute = start + Int(hours * 60)
        return "\(Self.format(minute: start)) – \(Self.format(minute: endMinute % (24 * 60)))"
    }

    private static func format(minute: Int) -> String {
        let h = (minute / 60) % 24, m = minute % 60
        var components = DateComponents()
        components.hour = h
        components.minute = m
        let date = Calendar.current.date(from: components) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    /// Whether a timestamp falls inside the eating window. Always `true` when the
    /// plan has no window.
    ///
    /// Handles windows that wrap past midnight (e.g. 20:00–02:00) — a real pattern
    /// for night-shift workers, and a silent bug if you only compare raw minutes.
    public func isWithinEatingWindow(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard let hours = eatingWindowHours, let start = eatingWindowStartMinute else { return true }
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        let length = Int(hours * 60)
        let end = start + length

        if end <= 24 * 60 {
            return minute >= start && minute < end
        } else {
            // Wraps midnight: inside if after the start, or before the wrapped end.
            return minute >= start || minute < (end - 24 * 60)
        }
    }
}
