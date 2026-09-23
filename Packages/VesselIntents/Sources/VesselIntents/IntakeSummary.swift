import Foundation
import SwiftData
import VesselCore

/// Today, in numbers — the same numbers the Today screen shows.
///
/// Computed exactly as the Today screen computes them, day boundaries from
/// the streak engine included, so Siri and the app never disagree about how
/// much has been eaten or drunk.
public struct IntakeSummary: Equatable {
    public var kilocalories: Double
    public var kilocalorieGoal: Double?
    public var waterML: Double
    public var waterGoalML: Double
    public var streakDays: Int
    public var mealsLogged: Int
    public var mealsRequired: Int

    @MainActor
    public static func today(in context: ModelContext, now: Date = Date()) -> IntakeSummary {
        let profile = UserProfile.current(in: context)
        let engine = profile.makeStreakEngine()
        let plan = profile.fastingPlan
        let start = engine.dayStart(for: now)
        let end = engine.dayEnd(for: now)

        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: now) ?? now
        let meals = (try? context.fetch(FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.loggedAt >= cutoff }
        ))) ?? []
        let todaysMeals = meals.filter { $0.loggedAt >= start && $0.loggedAt < end }
        let nutrients = Nutrients.sum(todaysMeals.map(\.totalNutrients))

        let water = (try? context.fetch(FetchDescriptor<WaterEntry>(
            predicate: #Predicate { $0.loggedAt >= start && $0.loggedAt < end }
        ))) ?? []
        var waterML = water.reduce(0) { $0 + $1.volumeML }
        if profile.countsFoodWaterTowardHydration { waterML += nutrients.waterML }

        let snapshot = engine.snapshot(
            meals: meals, plan: plan, now: now,
            allowedRestDays: profile.allowedRestDaysPerWeek
        )

        return IntakeSummary(
            kilocalories: nutrients.kilocalories,
            kilocalorieGoal: profile.goals.kilocalories,
            waterML: waterML,
            waterGoalML: profile.goals.waterML,
            streakDays: snapshot.streak.current,
            mealsLogged: snapshot.progress.logged,
            mealsRequired: snapshot.progress.required
        )
    }

    public var calorieSentence: String {
        let eaten = Int(kilocalories.rounded()).formatted()
        guard let goal = kilocalorieGoal, goal > 0 else { return "\(eaten) calories so far today." }
        let left = Int((goal - kilocalories).rounded())
        return left >= 0
            ? "\(eaten) of \(Int(goal).formatted()) calories, \(left.formatted()) left."
            : "\(eaten) calories, \((-left).formatted()) over your \(Int(goal).formatted())."
    }

    public var waterSentence: String {
        let litres = (waterML / 1000).formatted(.number.precision(.fractionLength(1)))
        let goal = (waterGoalML / 1000).formatted(.number.precision(.fractionLength(1)))
        return waterML >= waterGoalML
            ? "\(litres) litres of water — goal reached."
            : "\(litres) of \(goal) litres of water."
    }

    public var streakSentence: String {
        let days = streakDays == 1 ? "1-day streak" : "\(streakDays)-day streak"
        let remaining = mealsRequired - mealsLogged
        if remaining > 0 {
            return "\(days), \(remaining) more \(remaining == 1 ? "meal" : "meals") to keep it."
        }
        return "\(days), and today already counts."
    }

    public var sentence: String {
        [calorieSentence, waterSentence, streakSentence].joined(separator: " ")
    }
}
