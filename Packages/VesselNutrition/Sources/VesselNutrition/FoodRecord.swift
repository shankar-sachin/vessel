import Foundation
import VesselCore

/// A food as it exists in the bundled database.
///
/// All nutrient figures are **per 100 g**, exactly as USDA publishes them.
/// Callers scale to an actual portion via `nutrients(forGrams:)` — keeping the
/// stored form canonical means there's one place scaling can go wrong instead
/// of one per call site.
public struct FoodRecord: Sendable, Identifiable, Hashable {

    public let id: String              // "fdc:171705"
    public let name: String
    public let category: String
    public let source: String          // survey | foundation | legacy
    public let popularity: Int

    /// Grams per millilitre, when the database could derive it. Needed to turn
    /// "a cup of rice" into a weight.
    public let density: Double?

    /// Per 100 g.
    public let nutrientsPer100g: Nutrients

    /// Common measures for this food, e.g. "1 cup" → 158 g.
    public let portions: [FoodPortion]

    /// Ingredient and allergen groups, used by the Date Log's correlations.
    public let tags: [String]

    public init(
        id: String, name: String, category: String, source: String, popularity: Int,
        density: Double?, nutrientsPer100g: Nutrients, portions: [FoodPortion], tags: [String]
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.source = source
        self.popularity = popularity
        self.density = density
        self.nutrientsPer100g = nutrientsPer100g
        self.portions = portions
        self.tags = tags
    }

    /// Nutrition for an actual weight.
    public func nutrients(forGrams grams: Double) -> Nutrients {
        nutrientsPer100g.scaled(by: grams / 100)
    }

    /// The portion to offer first.
    ///
    /// Prefers an ordinary household measure — people think in cups and slices,
    /// not grams, and a picker that opens on "100 g" makes them do arithmetic
    /// before they can log breakfast.
    ///
    /// USDA's own ordering can't be trusted for this: milk's first listed
    /// portion is "1 individual school container", which is a real measurement
    /// and a strange thing to greet someone with.
    public var defaultPortion: FoodPortion? {
        portions.min { lhs, rhs in lhs.defaultPreference < rhs.defaultPreference }
    }
}

/// One named measure of a food.
public struct FoodPortion: Sendable, Hashable, Identifiable {
    public let label: String   // "1 cup, cooked"
    public let grams: Double

    public var id: String { "\(label)|\(grams)" }

    public init(label: String, grams: Double) {
        self.label = label
        self.grams = grams
    }

    /// True for labels that are just a weight, like "100 g".
    var isBareWeight: Bool {
        let lowered = label.lowercased()
        return lowered.hasSuffix(" g") || lowered.hasSuffix(" oz") || lowered.hasSuffix(" gram")
    }

    /// Sort key for choosing a food's opening portion. Lower is better.
    var defaultPreference: Int {
        let lowered = label.lowercased()

        // Packaging and institutional servings are real measures but a poor
        // greeting — nobody thinks of milk in school containers.
        let oddities = ["school", "container", "package", "individual", "bottle",
                        "can ", "carton", "guideline", "not specified"]
        if oddities.contains(where: { lowered.contains($0) }) { return 400 }

        // The measures people actually speak in.
        let household = ["cup", "tablespoon", "tbsp", "teaspoon", "tsp", "slice",
                         "piece", "medium", "large", "small", "each", "whole",
                         "fl oz", "egg", "fillet", "breast"]
        if household.contains(where: { lowered.contains($0) }) {
            // A single unit beats a multiple, since quantity is chosen separately.
            return lowered.hasPrefix("1 ") ? 0 : 100
        }

        if isBareWeight { return 300 }
        return 200
    }

    /// "1 cup, cooked (158 g)"
    public var displayLabel: String {
        "\(label) (\(Int(grams.rounded())) g)"
    }
}
