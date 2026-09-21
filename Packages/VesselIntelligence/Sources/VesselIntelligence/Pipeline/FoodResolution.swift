import Foundation
import VesselCore
import VesselNutrition

/// Joins the parser to the food database.
///
/// The parser says *what words were spoken*; this decides *which food that is*
/// and *how much of it*. Kept separate because the two fail differently: the
/// parser can be sure it heard "two eggs" while the database is unsure which of
/// forty egg entries is meant, and the UI needs to tell those apart.
public struct EntryResolver: Sendable {

    private let search: FoodSearch
    private let portions: PortionResolver
    private let accompaniments: Accompaniments

    public init(
        search: FoodSearch = FoodSearch(),
        portions: PortionResolver = PortionResolver(),
        accompaniments: Accompaniments = Accompaniments()
    ) {
        self.search = search
        self.portions = portions
        self.accompaniments = accompaniments
    }

    /// A parsed food matched against the database.
    public struct ResolvedFood: Sendable, Identifiable {
        public let id = UUID()
        /// What the user said.
        public let phrase: String
        /// Best database match, if there was one.
        public let food: FoodRecord?
        /// Other plausible matches, for a picker.
        public let alternatives: [FoodRecord]
        public let quantity: Double
        public let unit: MeasurementUnit
        public let grams: Double?
        public let nutrients: Nutrients
        /// 0...1, combining how sure the parser and the database each are.
        public let confidence: Double
        /// True when the weight was inferred rather than measured.
        public let isEstimate: Bool

        /// Variants worth choosing between, when the word was generic enough
        /// that picking one silently would hide a real difference — "milk"
        /// spans 34 to 61 kcal per 100 g.
        public let variants: [FoodRecord]

        /// A food this one is usually eaten with, offered rather than added.
        public let suggestedCompanion: (searchTerm: String, note: String)?

        public var isUnmatched: Bool { food == nil }
        public var needsChoice: Bool { !variants.isEmpty }
    }

    /// Resolves every food in a parsed entry.
    public func resolve(_ entry: ParsedEntry) -> [ResolvedFood] {
        let wanted = entry.foods.filter { !$0.isNegated }
        // Companion suggestions need to know what else is in the meal, so the
        // milk isn't offered twice when it's already there.
        let names = wanted.map(\.phrase)
        return wanted.map { resolve($0, alongside: names) }
    }

    public func resolve(_ parsed: ParsedFood, alongside others: [String] = []) -> ResolvedFood {
        // Search on the food words plus any preparation, since "grilled
        // chicken" and "fried chicken" are different rows with different fat.
        let query = (parsed.preparation + [parsed.phrase]).joined(separator: " ")
        let matches = search.search(query, limit: 6)

        guard let best = matches.first else {
            return ResolvedFood(
                phrase: parsed.phrase,
                food: nil,
                alternatives: [],
                quantity: parsed.quantity ?? 1,
                unit: parsed.unit ?? .serving,
                grams: nil,
                nutrients: .zero,
                confidence: 0,
                isEstimate: true,
                variants: [],
                suggestedCompanion: nil
            )
        }

        let quantity = parsed.quantity ?? 1
        let unit = parsed.unit ?? defaultUnit(for: best.food)
        let resolution = portions.grams(quantity: quantity, unit: unit, food: best.food)
        let grams = resolution?.grams ?? best.food.defaultPortion?.grams ?? 100

        // Multiply rather than average: a confident parse of a food the
        // database isn't sure about is still an uncertain entry overall, and
        // averaging would hide that behind one strong signal.
        var confidence = best.score
        if parsed.quantity == nil { confidence *= 0.9 }
        if parsed.quantityIsApproximate { confidence *= 0.92 }
        // A close second suggests the top hit is a coin flip.
        if matches.count > 1, matches[1].score > best.score * 0.92 { confidence *= 0.85 }

        let variants = FoodVariants.options(query: parsed.phrase, matches: matches)
        // An unanswered "which one?" is itself a reason to be less sure.
        if !variants.isEmpty { confidence *= 0.8 }

        return ResolvedFood(
            phrase: parsed.phrase,
            food: best.food,
            alternatives: matches.dropFirst().map(\.food),
            quantity: quantity,
            unit: unit,
            grams: grams,
            nutrients: best.food.nutrients(forGrams: grams),
            confidence: min(1, confidence),
            isEstimate: resolution?.isEstimate ?? true,
            variants: variants,
            suggestedCompanion: accompaniments.suggestion(
                for: best.food.name,
                alreadyLogged: others
            )
        )
    }

    /// When no unit was spoken, use the food's own default measure.
    private func defaultUnit(for food: FoodRecord) -> MeasurementUnit {
        food.defaultPortion != nil ? .serving : .gram
    }
}
