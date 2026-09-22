import Foundation
import SwiftData

/// Realistic sample content for previews and simulator runs.
///
/// Deliberately not tidy: it includes a low-confidence parse, a skipped day, and
/// a symptom a few hours after a meal — the situations the UI actually has to
/// handle. Seeding only perfect data is how you ship a layout that breaks on
/// the first real week of use.
public enum SampleData {

    @MainActor
    public static func seed(into context: ModelContext, referenceDate: Date = Date()) {
        let cal = Calendar.current
        // Reuse the profile the app created at launch. Inserting a second one
        // would leave the UI reading whichever sorted first, with the other's
        // settings silently ignored.
        let profile = UserProfile.current(in: context)
        profile.goals = DailyGoals(
            kilocalories: 2200, proteinG: 130, carbohydrateG: 240, fatG: 70, fiberG: 30, waterML: 2500
        )

        func at(_ daysAgo: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let day = cal.date(byAdding: .day, value: -daysAgo, to: referenceDate) ?? referenceDate
            return cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }

        // A full recent week, minus one skipped day so the streak UI has a break
        // to render.
        for daysAgo in [0, 1, 2, 3, 5, 6, 7] {
            let breakfast = FoodEntry(
                loggedAt: at(daysAgo, 8, 15), slot: .breakfast, source: .voice,
                rawInput: "two eggs and a slice of sourdough toast"
            )
            breakfast.items = [
                FoodItem(foodID: "fdc:748967", displayName: "Eggs, scrambled", quantity: 2, unit: .item,
                         grams: 100, nutrients: Nutrients(kilocalories: 148, proteinG: 12.6, carbohydrateG: 1.6,
                                                          fatG: 10.6, sodiumMG: 310, waterML: 73),
                         tags: ["egg"]),
                FoodItem(foodID: "fdc:325871", displayName: "Sourdough bread", quantity: 1, unit: .slice,
                         grams: 56, nutrients: Nutrients(kilocalories: 150, proteinG: 6, carbohydrateG: 29,
                                                         fatG: 1.2, fiberG: 1.7, sodiumMG: 340, waterML: 20),
                         tags: ["gluten", "wheat"])
            ]
            context.insert(breakfast)

            let lunch = FoodEntry(
                loggedAt: at(daysAgo, 13, 10), slot: .lunch, source: .photo,
                rawInput: nil
            )
            lunch.items = [
                FoodItem(foodID: "fdc:171705", displayName: "Chicken breast, grilled", quantity: 165, unit: .gram,
                         grams: 165, nutrients: Nutrients(kilocalories: 273, proteinG: 51, fatG: 6,
                                                          sodiumMG: 125, waterML: 105), tags: ["poultry"]),
                FoodItem(foodID: "fdc:168878", displayName: "Brown rice, cooked", quantity: 1, unit: .cup,
                         grams: 195, nutrients: Nutrients(kilocalories: 218, proteinG: 4.5, carbohydrateG: 46,
                                                          fatG: 1.6, fiberG: 3.5, waterML: 137), tags: ["grain"])
            ]
            context.insert(lunch)

            // Dinner is missing today, so today's streak ring is mid-progress —
            // the most common live state, and the one worth designing against.
            if daysAgo != 0 {
                let dinner = FoodEntry(
                    loggedAt: at(daysAgo, 19, 30), slot: .dinner, source: .text,
                    rawInput: "bowl of pasta with parmesan"
                )
                dinner.items = [
                    FoodItem(foodID: "fdc:168928", displayName: "Pasta, cooked", quantity: 1.5, unit: .cup,
                             grams: 210, nutrients: Nutrients(kilocalories: 331, proteinG: 12, carbohydrateG: 65,
                                                              fatG: 2, fiberG: 3.8, waterML: 130),
                             tags: ["gluten", "wheat"]),
                    FoodItem(foodID: "fdc:171247", displayName: "Parmesan, grated", quantity: 2, unit: .tablespoon,
                             grams: 10, nutrients: Nutrients(kilocalories: 43, proteinG: 3.8, fatG: 2.8,
                                                             sodiumMG: 170, calciumMG: 137),
                             tags: ["dairy", "lactose"])
                ]
                context.insert(dinner)
            }

            for (hour, ml) in [(7, 300), (10, 250), (13, 400), (16, 250), (20, 350)] {
                context.insert(WaterEntry(
                    loggedAt: at(daysAgo, hour), volumeML: Double(ml),
                    containerName: ml >= 350 ? "Bottle" : "Glass"
                ))
            }
        }

        // A parse we weren't sure about — exercises the "needs review" treatment.
        let uncertain = FoodEntry(
            loggedAt: at(1, 15, 40), slot: .snack, source: .voice,
            rawInput: "handful of those seed cracker things",
            parseConfidence: 0.42
        )
        uncertain.items = [
            FoodItem(displayName: "Seed crackers", quantity: 1, unit: .handful,
                     nutrients: Nutrients(kilocalories: 130, proteinG: 4, carbohydrateG: 12, fatG: 8, fiberG: 3),
                     tags: ["seed", "gluten"])
        ]
        context.insert(uncertain)

        // Symptoms clustered a couple of hours after dairy-containing dinners —
        // gives the correlation engine a real signal to find.
        for daysAgo in [1, 3, 6] {
            context.insert(SymptomEntry(
                occurredAt: at(daysAgo, 22, 15), kind: .bloating, severity: .moderate,
                note: daysAgo == 1 ? "Started about two hours after dinner" : nil,
                durationMinutes: 90
            ))
        }
        context.insert(SymptomEntry(
            occurredAt: at(2, 23, 0), kind: .heartburn, severity: .mild, durationMinutes: 45
        ))

        context.insert(JournalEntry(
            createdAt: at(0, 21, 30),
            title: "Steadier today",
            body: "Ate earlier than usual and it made a real difference to how the evening felt. "
                + "Still noticing the pattern where late pasta sits badly.\n\n"
                + "Walked for forty minutes after lunch.",
            mood: .good, tags: ["energy", "routine"]
        ))
        context.insert(JournalEntry(
            createdAt: at(3, 20, 0),
            title: nil,
            body: "Rough afternoon. Low energy from about three o'clock and never really came back.",
            mood: .subdued, tags: ["energy"]
        ))

        seedEarlierHistory(into: context, at: at)

        try? context.save()
    }

    /// Eight weeks before the detailed recent week, at lower resolution.
    ///
    /// The recent week is what the logging screens are demonstrated with; this
    /// is what the *insights* need. A correlation engine that refuses to speak
    /// below five exposures and two weeks of history has nothing to say about
    /// seven days, which is correct of it and makes for a dull screenshot.
    ///
    /// There is a real pattern planted here — dairy at dinner twice a week,
    /// bloating about two and a half hours later — alongside enough unrelated
    /// reactions to give the base rate something to be. The engine is not told
    /// any of that; it has to find it, which is also how the tests work.
    private static func seedEarlierHistory(
        into context: ModelContext,
        at: (Int, Int, Int) -> Date
    ) {
        for daysAgo in 8...63 {
            let breakfast = FoodEntry(loggedAt: at(daysAgo, 8, 0), slot: .breakfast, source: .text)
            breakfast.items = [
                FoodItem(foodID: "fdc:325871", displayName: "Toast", quantity: 2, unit: .slice,
                         grams: 56, nutrients: Nutrients(kilocalories: 150, proteinG: 6,
                                                         carbohydrateG: 29, fatG: 1.2, fiberG: 1.7),
                         tags: ["gluten", "wheat"])
            ]
            context.insert(breakfast)

            let hasDairy = daysAgo % 7 == 2 || daysAgo % 7 == 5
            let dinner = FoodEntry(loggedAt: at(daysAgo, 19, 0), slot: .dinner, source: .text)
            dinner.items = hasDairy
                ? [FoodItem(foodID: "fdc:170904", displayName: "Lasagne", quantity: 1, unit: .serving,
                            grams: 280, nutrients: Nutrients(kilocalories: 380, proteinG: 22,
                                                             carbohydrateG: 38, fatG: 15),
                            tags: ["dairy", "gluten", "wheat"])]
                : [FoodItem(foodID: "fdc:171705", displayName: "Chicken and vegetables", quantity: 1,
                            unit: .serving, grams: 300,
                            nutrients: Nutrients(kilocalories: 340, proteinG: 38, carbohydrateG: 20, fatG: 11),
                            tags: ["poultry"])]
            context.insert(dinner)

            if hasDairy {
                context.insert(SymptomEntry(
                    occurredAt: at(daysAgo, 21, 30), kind: .bloating,
                    severity: daysAgo % 3 == 0 ? .strong : .moderate, durationMinutes: 90
                ))
            } else if daysAgo % 11 == 0 {
                // Reactions that follow nothing in particular, so the engine has
                // a base rate to measure against rather than a clean signal.
                context.insert(SymptomEntry(
                    occurredAt: at(daysAgo, 15, 0), kind: .bloating, severity: .mild
                ))
            }
        }
    }
}
