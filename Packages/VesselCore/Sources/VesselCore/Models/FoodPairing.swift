import Foundation
import SwiftData

/// Two foods this person eats together.
///
/// The honest answer to "cereal implies milk". A hardcoded table only knows
/// what its author thought of, and USDA's own data turns out not to support the
/// assumption at all — the only cereal-and-milk entries in FoodData Central are
/// baby food. What's actually true is that *you* have milk with cereal, or you
/// don't, and the only way to know is to watch.
///
/// So Vessel counts. Every meal logged with more than one food records its
/// pairs, and after a handful of breakfasts it can offer the milk because you
/// keep having it — not because someone guessed you would.
@Model
public final class FoodPairing {
    public var id: UUID = UUID()

    /// Database id of the food this pairing is about.
    public var foodID: String = ""
    /// Database id of what it was eaten with.
    public var companionFoodID: String = ""
    /// Kept so a suggestion can name the food without a second lookup.
    public var companionName: String = ""

    /// How many separate meals contained both.
    public var occurrences: Int = 1
    public var lastSeenAt: Date = Date()

    /// Times the suggestion was offered and dismissed.
    ///
    /// Without this, a pairing seen three times keeps being suggested forever
    /// even as the user declines it every morning.
    public var dismissals: Int = 0

    public init(
        id: UUID = UUID(),
        foodID: String,
        companionFoodID: String,
        companionName: String
    ) {
        self.id = id
        self.foodID = foodID
        self.companionFoodID = companionFoodID
        self.companionName = companionName
        self.lastSeenAt = Date()
    }

    /// Whether this pairing is established enough to act on.
    ///
    /// Two co-occurrences is a coincidence; three is a habit. Declining it
    /// twice outweighs the evidence — the person has told us directly, which
    /// is better data than counting.
    public var isEstablished: Bool {
        occurrences >= 3 && dismissals < 2
    }

    /// Confidence, smoothed so a single pairing doesn't read as certainty.
    public var strength: Double {
        let total = Double(occurrences + dismissals)
        guard total > 0 else { return 0 }
        return (Double(occurrences) + 1) / (total + 2)
    }
}

/// Records and reads what foods are eaten together.
@MainActor
public enum PairingStore {

    /// Records every pair in a meal.
    ///
    /// Called after a meal is saved, so the record reflects what was actually
    /// kept rather than what was typed and then edited away.
    public static func record(foodIDs: [(id: String, name: String)], in context: ModelContext) {
        // A pairing needs two things to pair.
        guard foodIDs.count >= 2 else { return }

        let existing = (try? context.fetch(FetchDescriptor<FoodPairing>())) ?? []
        var index: [String: FoodPairing] = [:]
        for pairing in existing {
            index["\(pairing.foodID)|\(pairing.companionFoodID)"] = pairing
        }

        // Symmetric: eating cereal with milk is also eating milk with cereal,
        // and either one should be able to suggest the other.
        for first in foodIDs {
            for second in foodIDs where second.id != first.id {
                let key = "\(first.id)|\(second.id)"
                if let pairing = index[key] {
                    pairing.occurrences += 1
                    pairing.lastSeenAt = Date()
                } else {
                    let pairing = FoodPairing(
                        foodID: first.id,
                        companionFoodID: second.id,
                        companionName: second.name
                    )
                    context.insert(pairing)
                    index[key] = pairing
                }
            }
        }
    }

    /// What this person usually has with a given food.
    ///
    /// - Returns: the strongest established pairing, or nil while there isn't
    ///   enough evidence to say anything.
    public static func companion(
        for foodID: String,
        excluding alreadyPresent: [String] = [],
        in context: ModelContext
    ) -> FoodPairing? {
        let descriptor = FetchDescriptor<FoodPairing>(
            predicate: #Predicate { $0.foodID == foodID },
            sortBy: [SortDescriptor(\.occurrences, order: .reverse)]
        )
        let candidates = (try? context.fetch(descriptor)) ?? []

        return candidates.first { pairing in
            pairing.isEstablished && !alreadyPresent.contains(pairing.companionFoodID)
        }
    }

    /// Notes that a suggestion was offered and not taken.
    public static func dismiss(_ pairing: FoodPairing, in context: ModelContext) {
        pairing.dismissals += 1
        try? context.save()
    }
}
