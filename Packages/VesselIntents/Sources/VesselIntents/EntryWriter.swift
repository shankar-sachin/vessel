import Foundation
import SwiftData
import VesselCore
import VesselIntelligence
import VesselNutrition

/// Turns a parse into saved entries.
///
/// The one place a parsed utterance becomes data, shared by every surface that
/// accepts free text — the Quick log sheet and Siri. The parser was already
/// shared; the saving wasn't, and two copies of "what a parse means" would
/// drift the same way the corpus and the normalizer once did.
@MainActor
public struct EntryWriter {

    /// What a write produced, for confirming it back to the person.
    public struct Outcome {
        public var meal: FoodEntry?
        public var drinks: [WaterEntry] = []
        public var symptom: SymptomEntry?
        public var journal: JournalEntry?

        public var isEmpty: Bool {
            meal == nil && drinks.isEmpty && symptom == nil && journal == nil
        }

        /// A short sentence saying what was saved — what Siri reads back.
        public var summary: String {
            var parts: [String] = []
            if let meal, let items = meal.items, !items.isEmpty {
                let names = items.map { FoodName($0.displayName).title.lowercased() }
                let kcal = Int(items.reduce(0) { $0 + $1.nutrients.kilocalories }.rounded())
                parts.append("\(Self.list(names)), \(kcal) calories")
            }
            if !drinks.isEmpty {
                let ml = Int(drinks.reduce(0) { $0 + $1.volumeML }.rounded())
                parts.append("\(ml) ml of water")
            }
            if let symptom {
                parts.append("\(symptom.kind.title.lowercased()), \(symptom.severity.title.lowercased())")
            }
            if journal != nil { parts.append("a journal note") }
            return parts.isEmpty ? "Nothing to log." : "Logged " + Self.list(parts) + "."
        }

        static func list(_ items: [String]) -> String {
            switch items.count {
            case 0: return ""
            case 1: return items[0]
            default: return items.dropLast().joined(separator: ", ") + " and " + items.last!
            }
        }
    }

    private let context: ModelContext
    private let resolver: EntryResolver
    private let search: FoodSearch

    public init(context: ModelContext, resolver: EntryResolver = EntryResolver(), search: FoodSearch = FoodSearch()) {
        self.context = context
        self.resolver = resolver
        self.search = search
    }

    /// Below this, a drink carries no energy worth logging.
    ///
    /// Five kcal per 100 g sits above the rounding noise USDA records for
    /// water, and matches the usual label threshold for calling a drink
    /// calorie-free.
    public static let caloricDrinkThreshold = 5.0

    /// Where a drink goes.
    ///
    /// The Water diary is for water. Everything else a person drinks is food
    /// with a nutrition label — milk, juice, beer, even black coffee — and
    /// belongs in the Diet log with its nutrients, where caffeine and alcohol
    /// arrive as the database's own tags. Water drunk inside other drinks and
    /// foods is counted toward hydration by the profile's "count water in
    /// food" setting, not by filing a latte under water.
    public enum DrinkPlan {
        case water(millilitres: Double)
        case food(FoodRecord?, millilitres: Double, grams: Double)

        public var millilitres: Double {
            switch self {
            case .water(let ml), .food(_, let ml, _): return ml
            }
        }

        public var kilocalories: Double {
            if case .food(let record?, _, let grams) = self {
                return record.nutrients(forGrams: grams).kilocalories
            }
            return 0
        }
    }

    public func plan(for drink: ParsedDrink) -> DrinkPlan {
        let millilitres = drink.millilitres ?? 250
        let matches = search.search(drink.name, limit: 4)

        // Water is decided by name *and* by the data. "Sparkling water" and
        // "tap water" are water; "tonic water" and "coconut water" carry
        // energy and are drinks like any other. The database has no row for
        // plain water, so the top hit for "water" alone is tonic at 34 kcal —
        // which is why every close match has to carry energy before a
        // water-named drink is treated as food.
        let isWaterNamed = drink.name.split(separator: " ").last == "water"
        let close = matches.filter { $0.score >= (matches.first?.score ?? 0) - 0.06 }
        let allCaloric = !close.isEmpty && close.allSatisfy {
            $0.food.nutrientsPer100g.kilocalories >= Self.caloricDrinkThreshold
        }
        if isWaterNamed && !allCaloric {
            return .water(millilitres: millilitres)
        }

        let record = matches.first?.food
        return .food(record, millilitres: millilitres, grams: millilitres * (record?.density ?? 1))
    }

    /// Saves everything the parse found.
    ///
    /// - Parameters:
    ///   - resolved: foods already resolved by the caller, when it has shown
    ///     them to the person and let them choose variants. Resolved here
    ///     otherwise.
    ///   - variantChoices: a hand-picked row per resolved food, keyed by its id.
    @discardableResult
    public func write(
        _ parsed: ParsedEntry,
        resolved: [EntryResolver.ResolvedFood]? = nil,
        variantChoices: [UUID: FoodRecord] = [:],
        source: EntrySource
    ) -> Outcome {
        var outcome = Outcome()
        let foods = resolved ?? resolver.resolve(parsed)
        let when = parsed.occurredAt ?? Date()

        switch parsed.intent {
        case .logFood, .correction, .logWater:
            // A meal can name a drink and a drink log can name a food — "toast
            // and a coffee", "a coffee and a biscuit". Both halves are kept
            // whichever way the classifier leaned.
            var items = foods.map { item(for: $0, chosen: variantChoices[$0.id] ?? $0.food) }
            for drink in parsed.drinks {
                switch plan(for: drink) {
                case .water(let millilitres):
                    let water = WaterEntry(
                        loggedAt: when,
                        volumeML: millilitres,
                        source: source,
                        containerName: drink.name.capitalized
                    )
                    context.insert(water)
                    outcome.drinks.append(water)
                case .food(let record, let millilitres, let grams):
                    items.append(FoodItem(
                        foodID: record?.id,
                        displayName: record?.displayName ?? drink.name.capitalized,
                        quantity: millilitres,
                        unit: .milliliter,
                        grams: grams,
                        nutrients: record?.nutrients(forGrams: grams) ?? .zero,
                        tags: record?.tags ?? []
                    ))
                }
            }
            if !items.isEmpty {
                outcome.meal = meal(items: items, parsed: parsed, at: when, source: source)
            }

        case .logSymptom:
            if let symptom = parsed.symptom {
                let entry = SymptomEntry(
                    occurredAt: when,
                    kind: symptom.kind,
                    severity: symptom.severity ?? .moderate,
                    note: parsed.original
                )
                context.insert(entry)
                outcome.symptom = entry
            }

        case .journalEntry, .query, .unknown:
            let entry = JournalEntry(body: parsed.original)
            context.insert(entry)
            outcome.journal = entry
        }

        // Learn what this person eats together, so "cereal" can eventually
        // offer their milk because they keep having it — not because a table
        // said they would.
        let identities = (outcome.meal?.items ?? []).compactMap { item in
            item.foodID.map { (id: $0, name: item.displayName) }
        }
        PairingStore.record(foodIDs: identities, in: context)

        try? context.save()
        // Searchable from the home screen, however it was logged.
        if let meal = outcome.meal { MealIndex.index(meal) }
        return outcome
    }

    // MARK: - Pieces

    private func item(for resolved: EntryResolver.ResolvedFood, chosen: FoodRecord?) -> FoodItem {
        let grams = resolved.grams ?? chosen?.defaultPortion?.grams ?? 100
        return FoodItem(
            foodID: chosen?.id,
            displayName: chosen?.displayName ?? resolved.phrase.capitalized,
            quantity: resolved.quantity,
            unit: resolved.unit,
            grams: grams,
            // Recomputed from the chosen row: picking skimmed milk has to
            // change the calories, not just the label.
            nutrients: chosen?.nutrients(forGrams: grams) ?? resolved.nutrients,
            tags: chosen?.tags ?? []
        )
    }

    private func meal(items: [FoodItem], parsed: ParsedEntry, at when: Date, source: EntrySource) -> FoodEntry {
        let entry = FoodEntry(
            loggedAt: when,
            slot: parsed.slot ?? MealSlot.inferred(from: when),
            source: source,
            rawInput: parsed.original,
            parseConfidence: parsed.confidence
        )
        context.insert(entry)
        for item in items { context.insert(item) }
        entry.items = items
        return entry
    }
}
