import Foundation
import VesselCore

/// Converts "2 cups of rice" into grams.
///
/// Three routes, tried in order of how much they actually know about the food:
/// a named portion from the database, the food's measured density, then a
/// generic assumption. The order matters — 1 cup of rice and 1 cup of spinach
/// differ by a factor of six, so falling back to "a cup is 240 g" is a last
/// resort, not a shortcut.
public struct PortionResolver: Sendable {

    public init() {}

    /// The outcome, including how it was reached, so the UI can be honest about
    /// an estimate versus a known measure.
    public struct Resolution: Sendable, Equatable {
        public let grams: Double
        public let basis: Basis

        public init(grams: Double, basis: Basis) {
            self.grams = grams
            self.basis = basis
        }

        public enum Basis: Sendable, Equatable {
            /// Matched a portion the database lists for this food.
            case namedPortion(String)
            /// Converted a volume using this food's measured density.
            case density
            /// A direct weight, no conversion needed.
            case weight
            /// Multiplied the food's default serving.
            case defaultServing(String)
            /// Generic assumption — least reliable.
            case assumption
        }

        /// Whether to present the number as exact or as an estimate.
        public var isEstimate: Bool {
            switch basis {
            case .weight, .namedPortion: return false
            case .density, .defaultServing, .assumption: return true
            }
        }
    }

    /// Resolves a quantity and unit against a food.
    public func grams(
        quantity: Double,
        unit: MeasurementUnit,
        food: FoodRecord
    ) -> Resolution? {
        guard quantity > 0 else { return nil }

        // 1. A direct weight needs nothing from the database.
        if let gramsPerUnit = unit.gramsPerUnit {
            return Resolution(grams: quantity * gramsPerUnit, basis: .weight)
        }

        // 2. A volume the food has a named portion for, e.g. "1 cup, cooked".
        if unit.isVolume, let portion = namedPortion(for: unit, in: food) {
            return Resolution(grams: quantity * portion.grams, basis: .namedPortion(portion.label))
        }

        // 3. A volume converted through the food's own density.
        if unit.isVolume, let millilitres = unit.millilitersPerUnit {
            if let density = food.density {
                return Resolution(grams: quantity * millilitres * density, basis: .density)
            }
            // Water's density, flagged as the assumption it is.
            return Resolution(grams: quantity * millilitres, basis: .assumption)
        }

        // 4. Counts and vague measures lean on the food's default serving.
        if let portion = food.defaultPortion {
            let multiplier = Self.vagueMultiplier(for: unit)
            return Resolution(
                grams: quantity * portion.grams * multiplier,
                basis: unit == .serving || unit == .item
                    ? .defaultServing(portion.label)
                    : .assumption
            )
        }

        // 5. Nothing known. 100 g is the figure USDA publishes against, so an
        // unqualified "one serving" at least lines up with the stated nutrition.
        return Resolution(grams: quantity * 100, basis: .assumption)
    }

    /// Finds a database portion whose label names this unit.
    private func namedPortion(for unit: MeasurementUnit, in food: FoodRecord) -> FoodPortion? {
        let needles: [String]
        switch unit {
        case .cup:        needles = ["cup"]
        case .tablespoon: needles = ["tablespoon", "tbsp"]
        case .teaspoon:   needles = ["teaspoon", "tsp"]
        case .fluidOunce: needles = ["fl oz", "fluid ounce"]
        default:          return nil
        }

        // Prefer a portion of exactly one unit ("1 cup") over a multiple
        // ("2 cups"), since we scale by the user's quantity ourselves.
        let candidates = food.portions.filter { portion in
            let lowered = portion.label.lowercased()
            return needles.contains { lowered.contains($0) }
        }
        return candidates.first { $0.label.hasPrefix("1 ") } ?? candidates.first
    }

    /// Rough sizes for measures that aren't really measures.
    private static func vagueMultiplier(for unit: MeasurementUnit) -> Double {
        switch unit {
        case .handful: return 0.5
        case .pinch:   return 0.02
        case .slice:   return 1.0
        default:       return 1.0
        }
    }
}
