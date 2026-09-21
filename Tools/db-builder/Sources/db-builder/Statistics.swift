import Foundation

/// Facts derived from the food corpus itself rather than written down by hand.
///
/// Both of these started as hardcoded lists — a set of "generic" words, and a
/// table saying cereal goes with milk. That approach only ever knows what its
/// author thought of: it had no idea about Cheerios, muesli, Weetabix, or the
/// several hundred other foods with the same property. Computing them from the
/// 11,750 rows we already ship means the app knows exactly as much as the data
/// does, and keeps knowing it when the data changes.
enum Statistics {

    // MARK: - Ambiguity

    /// A head noun and how much its variants disagree.
    struct HeadNoun {
        let head: String
        let count: Int
        let minimumEnergy: Double
        let maximumEnergy: Double

        /// Relative spread of calories across everything sharing this head.
        var spread: Double {
            guard maximumEnergy > 0 else { return 0 }
            return (maximumEnergy - minimumEnergy) / maximumEnergy
        }

        /// Whether naming this food without qualification leaves a real
        /// question open.
        ///
        /// Both conditions matter. A head with several rows that all land on
        /// the same calorie figure needs no question — the variants differ in
        /// ways a food diary doesn't care about. A head with a wide spread but
        /// only one or two rows isn't a pattern, it's a coincidence.
        var isAmbiguous: Bool {
            count >= 3 && spread >= 0.25
        }
    }

    /// Groups foods by the first clause of their name.
    ///
    /// USDA writes names head-noun first — "Milk, whole", "Rice, white,
    /// cooked" — so the text before the first comma is the food itself and
    /// everything after it is the qualification.
    static func headNouns(in foods: [FoodRow]) -> [HeadNoun] {
        var grouped: [String: [Double]] = [:]

        for food in foods where food.kilocalories > 0 {
            let head = headNoun(of: food.name)
            guard head.count >= 3 else { continue }
            grouped[head, default: []].append(food.kilocalories)
        }

        return grouped.compactMap { head, energies in
            guard let low = energies.min(), let high = energies.max() else { return nil }
            return HeadNoun(head: head, count: energies.count, minimumEnergy: low, maximumEnergy: high)
        }
    }

    static func headNoun(of name: String) -> String {
        let firstClause = name.components(separatedBy: ",").first ?? name
        return firstClause
            .lowercased()
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Accompaniments

    /// One food commonly eaten with another.
    struct Accompaniment {
        let head: String
        let companion: String
        let occurrences: Int
    }

    /// Words that follow "with" without naming a food.
    private static let notCompanions: Set<String> = [
        "added", "out", "no", "low", "high", "reduced", "sugar", "salt",
        "skin", "bone", "fat", "seeds", "shell", "peel", "sauce from",
        "unknown", "other", "type", "not"
    ]

    /// Mines "X with Y" food names to learn what goes with what.
    ///
    /// USDA ships thousands of composite entries — "Cereal, ready-to-eat, with
    /// milk", "Biscuit with gravy", "Chicken with rice". Each is direct
    /// evidence, recorded by dietitians from real consumption surveys, that
    /// those two foods are eaten together. That is a far better source than
    /// anyone's intuition about breakfast.
    static func accompaniments(in foods: [FoodRow], minimumOccurrences: Int = 2) -> [Accompaniment] {
        var counts: [String: [String: Int]] = [:]

        for food in foods {
            let name = food.name.lowercased()
            guard let range = name.range(of: " with ") else { continue }

            let head = headNoun(of: String(name[name.startIndex..<range.lowerBound]))
            var companion = String(name[range.upperBound...])
                .components(separatedBy: ",").first?
                .trimmingCharacters(in: .whitespaces) ?? ""

            // Keep the companion to its own head noun: "milk" rather than
            // "milk and sugar added".
            if let cut = companion.range(of: " and ") {
                companion = String(companion[companion.startIndex..<cut.lowerBound])
            }
            companion = companion.trimmingCharacters(in: .whitespaces)

            guard head.count >= 3, companion.count >= 3,
                  head != companion,
                  !notCompanions.contains(where: { companion.hasPrefix($0) })
            else { continue }

            counts[head, default: [:]][companion, default: 0] += 1
        }

        return counts.flatMap { head, companions in
            companions
                .filter { $0.value >= minimumOccurrences }
                .map { Accompaniment(head: head, companion: $0.key, occurrences: $0.value) }
        }
        .sorted { $0.occurrences > $1.occurrences }
    }
}
