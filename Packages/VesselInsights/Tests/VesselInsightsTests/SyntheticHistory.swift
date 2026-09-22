import Foundation
import VesselCore
@testable import VesselInsights

/// Builds histories where the right answer is known in advance.
///
/// The only way to test a statistical claim is to generate data whose truth you
/// control and check what the engine says about it. Real data can't do this:
/// nobody knows what is actually causing their bloating, which is the entire
/// reason the feature exists.
struct SyntheticHistory {

    /// Deterministic, so a failure is reproducible rather than a thing that
    /// happened once on a Tuesday. A linear congruential generator is plenty —
    /// this is noise for a test, not cryptography.
    struct Random {
        private var state: UInt64
        init(seed: UInt64 = 42) { state = seed }

        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double((state >> 33) % 1_000_000) / 1_000_000
        }

        mutating func chance(_ probability: Double) -> Bool { next() < probability }
    }

    static let start = Date(timeIntervalSince1970: 1_700_000_000)   // a fixed Thursday

    static func day(_ index: Int, hour: Double) -> Date {
        start.addingTimeInterval(Double(index) * 86400 + hour * 3600)
    }

    var meals: [MealObservation] = []
    var symptoms: [SymptomObservation] = []

    mutating func eat(day: Int, hour: Double, groups: Set<String>, foods: Set<String> = []) -> Date {
        let at = Self.day(day, hour: hour)
        meals.append(MealObservation(at: at, groups: groups, foods: foods))
        return at
    }

    mutating func feel(_ kind: SymptomKind, after meal: Date, hours: Double, severity: Severity = .moderate) {
        symptoms.append(SymptomObservation(at: meal.addingTimeInterval(hours * 3600),
                                           kind: kind, severity: severity))
    }
}
