import Foundation
import SwiftData

/// Which measurement system the UI presents.
public enum UnitSystem: String, Codable, Sendable, CaseIterable {
    case metric, imperial

    public var title: String { self == .metric ? "Metric" : "Imperial" }

    /// Preferred unit for drinks.
    public var volumeUnit: MeasurementUnit { self == .metric ? .milliliter : .fluidOunce }
    /// Preferred unit for solids.
    public var massUnit: MeasurementUnit { self == .metric ? .gram : .ounce }
}

/// Daily targets. All optional — an app that demands you pick a calorie goal
/// before you can log a glass of water has lost the plot.
public struct DailyGoals: Codable, Sendable, Hashable {
    public var kilocalories: Double?
    public var proteinG: Double?
    public var carbohydrateG: Double?
    public var fatG: Double?
    public var fiberG: Double?
    public var waterML: Double

    public init(
        kilocalories: Double? = nil,
        proteinG: Double? = nil,
        carbohydrateG: Double? = nil,
        fatG: Double? = nil,
        fiberG: Double? = nil,
        waterML: Double = 2000
    ) {
        self.kilocalories = kilocalories
        self.proteinG = proteinG
        self.carbohydrateG = carbohydrateG
        self.fatG = fatG
        self.fiberG = fiberG
        self.waterML = waterML
    }

    public static let `default` = DailyGoals()
}

/// The user's single settings record.
///
/// One row, fetched via `UserProfile.current(in:)`, which creates it on first
/// run. Modelled as a record rather than `UserDefaults` so it travels with the
/// database in an export, and so it can sync if CloudKit is ever switched on.
@Model
public final class UserProfile {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()

    // MARK: Streak configuration

    /// Encoded `FastingPlan`. Stored as data so the plan can gain fields without
    /// a schema migration.
    public var fastingPlanData: Data?

    /// Hour at which a streak day begins and the previous one resets, 0–23.
    public var dayRolloverHour: Int = 0

    /// How long before the reset we start warning. Four hours by default.
    public var streakWarningLeadHours: Double = 4

    /// Consecutive missed days tolerated before the streak breaks. Zero is strict.
    public var allowedRestDaysPerWeek: Int = 0

    /// Whether to run the Live Activity / Dynamic Island countdown.
    public var liveActivityEnabled: Bool = true

    /// Whether to post a local notification when the streak is at risk. Kept
    /// separate from the Live Activity because the notification is the *reliable*
    /// mechanism — iOS will not promise to wake us to start an Activity.
    public var streakReminderEnabled: Bool = true

    // MARK: Goals and units

    public var goalsData: Data?
    public var unitSystemRaw: String = UnitSystem.metric.rawValue

    /// Count water contained in food toward the hydration goal.
    public var countsFoodWaterTowardHydration: Bool = false

    // MARK: Personalization

    /// Serialized weights for the food resolver's personal ranker. See
    /// `VesselIntelligence`. Opaque here on purpose — Core owns storage, not the
    /// model's internals.
    public var rankerWeightsData: Data?

    /// Whether the user dismissed the "upgrade your OS" card. Shown once, then
    /// only in Settings.
    public var didDismissUpgradePrompt: Bool = false

    public init(id: UUID = UUID()) {
        self.id = id
        self.createdAt = Date()
        self.fastingPlan = .standard
        self.goals = .default
    }

    // MARK: Derived accessors

    public var fastingPlan: FastingPlan {
        get {
            guard let fastingPlanData,
                  let decoded = try? JSONDecoder().decode(FastingPlan.self, from: fastingPlanData)
            else { return .standard }
            return decoded
        }
        set { fastingPlanData = try? JSONEncoder().encode(newValue) }
    }

    public var goals: DailyGoals {
        get {
            guard let goalsData,
                  let decoded = try? JSONDecoder().decode(DailyGoals.self, from: goalsData)
            else { return .default }
            return decoded
        }
        set { goalsData = try? JSONEncoder().encode(newValue) }
    }

    public var unitSystem: UnitSystem {
        get { UnitSystem(rawValue: unitSystemRaw) ?? .metric }
        set { unitSystemRaw = newValue.rawValue }
    }

    public var streakWarningLeadTime: TimeInterval {
        streakWarningLeadHours * 3600
    }

    /// A streak engine configured from these settings.
    public func makeStreakEngine(calendar: Calendar = .current) -> StreakEngine {
        StreakEngine(dayRolloverHour: dayRolloverHour, calendar: calendar)
    }

    /// Fetches the profile, creating it on first launch.
    ///
    /// Returns a fresh unsaved profile rather than throwing if the fetch fails,
    /// so a storage problem degrades into default settings instead of a screen
    /// the user can't get past.
    @MainActor
    public static func current(in context: ModelContext) -> UserProfile {
        let descriptor = FetchDescriptor<UserProfile>(sortBy: [SortDescriptor(\.createdAt)])
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let profile = UserProfile()
        context.insert(profile)
        try? context.save()
        return profile
    }
}

/// A phrase the user says that maps to a particular food.
///
/// This is the memory behind "my usual". Every time someone corrects a parse, we
/// write one of these; over a few weeks the resolver stops guessing and starts
/// knowing. It's also why the app gets *better* with use rather than staying
/// exactly as clever as the day it shipped.
@Model
public final class LearnedAlias {
    public var id: UUID = UUID()

    /// Normalized user phrase, e.g. "my protein shake".
    public var phrase: String = ""

    /// Food it resolves to.
    public var foodID: String = ""
    public var displayName: String = ""

    /// Times the user has confirmed this mapping. Higher wins ties.
    public var confirmations: Int = 1

    /// Times the user corrected *away* from this mapping. A phrase that keeps
    /// getting rejected must be able to lose, or one early mistake becomes
    /// permanent.
    public var rejections: Int = 0

    public var lastUsedAt: Date = Date()
    public var createdAt: Date = Date()

    /// Remembered portion, so "my usual coffee" restores the size too.
    public var defaultQuantity: Double?
    public var defaultUnitRaw: String?

    public init(
        id: UUID = UUID(),
        phrase: String,
        foodID: String,
        displayName: String,
        defaultQuantity: Double? = nil,
        defaultUnit: MeasurementUnit? = nil
    ) {
        self.id = id
        self.phrase = phrase
        self.foodID = foodID
        self.displayName = displayName
        self.defaultQuantity = defaultQuantity
        self.defaultUnitRaw = defaultUnit?.rawValue
        self.createdAt = Date()
        self.lastUsedAt = Date()
    }

    public var defaultUnit: MeasurementUnit? {
        get { defaultUnitRaw.flatMap(MeasurementUnit.init(rawValue:)) }
        set { defaultUnitRaw = newValue?.rawValue }
    }

    /// Confidence this alias is right, smoothed so a single confirmation doesn't
    /// read as certainty.
    public var strength: Double {
        let total = Double(confirmations + rejections)
        guard total > 0 else { return 0.5 }
        return (Double(confirmations) + 1) / (total + 2)
    }
}
