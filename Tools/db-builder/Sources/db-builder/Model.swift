import Foundation

/// USDA nutrient identifiers we care about.
///
/// FoodData Central carries hundreds of nutrients; these seventeen are the ones
/// Vessel actually shows or reasons about. Pulling the rest would multiply the
/// database size for data no screen displays.
enum NutrientID {
    static let energy = 1008
    static let energyAtwaterGeneral = 2047
    static let energyAtwaterSpecific = 2048
    static let protein = 1003
    static let fat = 1004
    static let carbohydrate = 1005
    static let fiber = 1079
    static let sugar = 2000
    static let addedSugar = 1235
    static let saturatedFat = 1258
    static let transFat = 1257
    static let cholesterol = 1253
    static let sodium = 1093
    static let potassium = 1092
    static let calcium = 1087
    static let iron = 1089
    static let vitaminC = 1162
    static let vitaminD = 1114
    static let water = 1051

    /// Every id we extract, so the loader can skip the rest cheaply.
    static let all: Set<Int> = [
        energy, energyAtwaterGeneral, energyAtwaterSpecific, protein, fat,
        carbohydrate, fiber, sugar, addedSugar, saturatedFat, transFat,
        cholesterol, sodium, potassium, calcium, iron, vitaminC, vitaminD, water
    ]
}

/// Which USDA dataset a food came from.
///
/// This drives ranking, not just provenance. FNDDS descriptions are written the
/// way people speak ("Milk, whole"), so they should win ties over an SR Legacy
/// entry for the same food ("Milk, whole, 3.25% milkfat, with added vitamin D").
enum DataSource: String {
    case foundation   // lab-analysed, highest quality, few items
    case survey       // FNDDS — natural names, realistic portions
    case legacy       // SR Legacy — broadest coverage

    /// Base ranking prior. Higher wins.
    var priority: Int {
        switch self {
        case .survey:     return 100
        case .foundation: return 80
        case .legacy:     return 50
        }
    }
}

/// One portion the food is commonly measured in.
struct Portion {
    var label: String       // "1 cup", "1 medium", "1 slice"
    var grams: Double
}

/// A food, assembled from several CSVs, ready to write.
struct FoodRow {
    var id: String              // "fdc:171705"
    var fdcID: Int
    var name: String
    var searchName: String
    var category: String
    var source: DataSource

    /// Nutrients per 100 g.
    var nutrients: [Int: Double] = [:]
    var portions: [Portion] = []
    var tags: Set<String> = []

    /// Grams per millilitre, derived from a volume portion when one exists.
    /// Lets "a cup of rice" resolve to grams.
    var density: Double?

    /// Position in the curated staples list, or nil if not a staple.
    /// See `Staples`.
    var stapleRank: Int?

    var isStaple: Bool { stapleRank != nil }

    var kilocalories: Double {
        // Prefer the directly measured value; Atwater-derived figures are the
        // documented fallback when a food has no measured energy.
        nutrients[NutrientID.energy]
            ?? nutrients[NutrientID.energyAtwaterSpecific]
            ?? nutrients[NutrientID.energyAtwaterGeneral]
            ?? 0
    }

    /// Ranking prior: source quality, nudged by how simple the name is.
    ///
    /// Short names are usually the generic staple ("Rice, white, cooked") while
    /// long ones are oddly specific variants. When someone types "rice" they
    /// almost always want the staple.
    var popularity: Int {
        var score = source.priority
        let wordCount = name.split(separator: " ").count
        score -= min(30, max(0, (wordCount - 3) * 3))
        if name.contains("(") { score -= 5 }
        // Baby food, fast-food chains, and branded dough aren't what a generic
        // query means, so they sink below the staples.
        let lowered = name.lowercased()
        for demote in ["baby food", "infant formula", "restaurant", "fast food", "school lunch"] {
            if lowered.contains(demote) { score -= 25 }
        }
        return max(1, score)
    }
}
