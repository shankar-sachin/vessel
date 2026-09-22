import Foundation

/// A nutrient profile, always expressed as an absolute amount for the portion it
/// describes (never "per 100g" — callers scale before constructing one).
///
/// Stored *denormalized* onto every logged item rather than referenced from the
/// food database. That's intentional: if the database is corrected or replaced in
/// a later release, meals you logged last year must keep the numbers they were
/// logged with. A history that silently rewrites itself is worse than useless
/// when you're trying to correlate symptoms against it.
public struct Nutrients: Codable, Sendable, Hashable {

    // MARK: Energy and macros
    public var kilocalories: Double
    public var proteinG: Double
    public var carbohydrateG: Double
    public var fatG: Double

    // MARK: Carbohydrate detail
    public var fiberG: Double
    public var sugarG: Double
    public var addedSugarG: Double

    // MARK: Fat detail
    public var saturatedFatG: Double
    public var transFatG: Double
    public var cholesterolMG: Double

    // MARK: Minerals and micronutrients commonly watched
    public var sodiumMG: Double
    public var potassiumMG: Double
    public var calciumMG: Double
    public var ironMG: Double
    public var vitaminCMG: Double
    public var vitaminDMCG: Double

    /// Water contributed by the food itself. Food is a real fraction of daily
    /// hydration, so the Water Diary can optionally include it.
    public var waterML: Double

    public init(
        kilocalories: Double = 0,
        proteinG: Double = 0,
        carbohydrateG: Double = 0,
        fatG: Double = 0,
        fiberG: Double = 0,
        sugarG: Double = 0,
        addedSugarG: Double = 0,
        saturatedFatG: Double = 0,
        transFatG: Double = 0,
        cholesterolMG: Double = 0,
        sodiumMG: Double = 0,
        potassiumMG: Double = 0,
        calciumMG: Double = 0,
        ironMG: Double = 0,
        vitaminCMG: Double = 0,
        vitaminDMCG: Double = 0,
        waterML: Double = 0
    ) {
        self.kilocalories = kilocalories
        self.proteinG = proteinG
        self.carbohydrateG = carbohydrateG
        self.fatG = fatG
        self.fiberG = fiberG
        self.sugarG = sugarG
        self.addedSugarG = addedSugarG
        self.saturatedFatG = saturatedFatG
        self.transFatG = transFatG
        self.cholesterolMG = cholesterolMG
        self.sodiumMG = sodiumMG
        self.potassiumMG = potassiumMG
        self.calciumMG = calciumMG
        self.ironMG = ironMG
        self.vitaminCMG = vitaminCMG
        self.vitaminDMCG = vitaminDMCG
        self.waterML = waterML
    }

    public static let zero = Nutrients()

    /// Scales every value by a factor — used to turn per-100g database figures
    /// into the amount actually eaten.
    public func scaled(by factor: Double) -> Nutrients {
        guard factor.isFinite, factor >= 0 else { return .zero }
        var n = self
        n.kilocalories *= factor
        n.proteinG *= factor
        n.carbohydrateG *= factor
        n.fatG *= factor
        n.fiberG *= factor
        n.sugarG *= factor
        n.addedSugarG *= factor
        n.saturatedFatG *= factor
        n.transFatG *= factor
        n.cholesterolMG *= factor
        n.sodiumMG *= factor
        n.potassiumMG *= factor
        n.calciumMG *= factor
        n.ironMG *= factor
        n.vitaminCMG *= factor
        n.vitaminDMCG *= factor
        n.waterML *= factor
        return n
    }

    public static func + (lhs: Nutrients, rhs: Nutrients) -> Nutrients {
        Nutrients(
            kilocalories: lhs.kilocalories + rhs.kilocalories,
            proteinG: lhs.proteinG + rhs.proteinG,
            carbohydrateG: lhs.carbohydrateG + rhs.carbohydrateG,
            fatG: lhs.fatG + rhs.fatG,
            fiberG: lhs.fiberG + rhs.fiberG,
            sugarG: lhs.sugarG + rhs.sugarG,
            addedSugarG: lhs.addedSugarG + rhs.addedSugarG,
            saturatedFatG: lhs.saturatedFatG + rhs.saturatedFatG,
            transFatG: lhs.transFatG + rhs.transFatG,
            cholesterolMG: lhs.cholesterolMG + rhs.cholesterolMG,
            sodiumMG: lhs.sodiumMG + rhs.sodiumMG,
            potassiumMG: lhs.potassiumMG + rhs.potassiumMG,
            calciumMG: lhs.calciumMG + rhs.calciumMG,
            ironMG: lhs.ironMG + rhs.ironMG,
            vitaminCMG: lhs.vitaminCMG + rhs.vitaminCMG,
            vitaminDMCG: lhs.vitaminDMCG + rhs.vitaminDMCG,
            waterML: lhs.waterML + rhs.waterML
        )
    }

    public static func sum(_ items: some Sequence<Nutrients>) -> Nutrients {
        items.reduce(.zero, +)
    }

    /// Energy implied by the macros, using Atwater factors.
    ///
    /// Compared against the stated calories to catch bad database rows and bad
    /// parses — if someone logs "2 eggs" and we resolve 4000 kcal, the macros
    /// won't agree and we can flag it instead of silently ruining their day.
    public var derivedKilocalories: Double {
        proteinG * 4 + carbohydrateG * 4 + fatG * 9
    }

    /// True when stated and derived energy disagree by more than 25%, ignoring
    /// trivially small entries where rounding dominates.
    public var hasImplausibleEnergy: Bool {
        guard kilocalories > 25, derivedKilocalories > 25 else { return false }
        let ratio = derivedKilocalories / kilocalories
        return ratio < 0.75 || ratio > 1.25
    }
}

/// Units a quantity can be expressed in.
public enum MeasurementUnit: String, Codable, Sendable, CaseIterable {
    // Mass
    case gram, ounce, pound
    // Volume
    case milliliter, liter, fluidOunce, cup, tablespoon, teaspoon
    // Count / descriptive
    case item, slice, serving, handful, pinch

    public var isMass: Bool {
        switch self {
        case .gram, .ounce, .pound: return true
        default: return false
        }
    }

    public var isVolume: Bool {
        switch self {
        case .milliliter, .liter, .fluidOunce, .cup, .tablespoon, .teaspoon: return true
        default: return false
        }
    }

    /// Grams per unit, for mass units.
    public var gramsPerUnit: Double? {
        switch self {
        case .gram:  return 1
        case .ounce: return 28.349523125
        case .pound: return 453.59237
        default:     return nil
        }
    }

    /// Milliliters per unit, for volume units. US customary measures.
    public var millilitersPerUnit: Double? {
        switch self {
        case .milliliter: return 1
        case .liter:      return 1000
        case .fluidOunce: return 29.5735295625
        case .cup:        return 236.5882365
        case .tablespoon: return 14.78676478125
        case .teaspoon:   return 4.92892159375
        default:          return nil
        }
    }

    public var shortName: String {
        switch self {
        case .gram: return "g"
        case .ounce: return "oz"
        case .pound: return "lb"
        case .milliliter: return "ml"
        case .liter: return "L"
        case .fluidOunce: return "fl oz"
        case .cup: return "cup"
        case .tablespoon: return "tbsp"
        case .teaspoon: return "tsp"
        case .item: return "item"
        case .slice: return "slice"
        case .serving: return "serving"
        case .handful: return "handful"
        case .pinch: return "pinch"
        }
    }

    /// The short name, pluralised where English does — "2 servings", not
    /// "2 serving". Abbreviations never take a plural.
    public func shortName(for quantity: Double) -> String {
        guard quantity != 1 else { return shortName }
        switch self {
        case .cup, .item, .slice, .serving: return shortName + "s"
        case .handful: return "handfuls"
        case .pinch: return "pinches"
        default: return shortName
        }
    }
}
