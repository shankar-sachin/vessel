import Foundation
import VesselCore

/// A search hit with the reasoning that produced it.
public struct FoodMatch: Sendable, Identifiable, Hashable {
    public let food: FoodRecord
    /// 0...1. Above `FoodSearch.confidentThreshold` the parser may accept this
    /// without asking; below it, the user confirms.
    public let score: Double

    public var id: String { food.id }
}

/// Ranks database candidates against what someone typed or said.
///
/// FTS5 decides *whether* a row matches; this decides how well. That split
/// matters because SQLite's bm25 has no idea that "Rice, white, cooked" is a
/// better answer to "rice" than "Rice flour, brown, gluten-free" is, even though
/// both contain the word.
public struct FoodSearch: Sendable {

    /// Above this, a match is good enough to fill in without confirmation.
    public static let confidentThreshold = 0.72

    private let database: FoodDatabase

    public init(database: FoodDatabase = .shared) {
        self.database = database
    }

    /// Searches the bundled database.
    ///
    /// - Parameter limit: how many results to return after ranking.
    public func search(_ query: String, limit: Int = 20) -> [FoodMatch] {
        let cleaned = Self.normalize(query)
        guard cleaned.count >= 2 else { return [] }

        // Pull a wide net, then rank. 200 is comfortably more than any query
        // needs while staying fast enough to run on every keystroke.
        let candidates = database.candidates(matching: cleaned, limit: 200)
        guard !candidates.isEmpty else { return [] }

        let queryTokens = cleaned.split(separator: " ").map(String.init)

        return candidates
            .map { FoodMatch(food: $0, score: score(food: $0, query: cleaned, queryTokens: queryTokens)) }
            .sorted { lhs, rhs in
                lhs.score == rhs.score
                    ? lhs.food.popularity > rhs.food.popularity
                    : lhs.score > rhs.score
            }
            .prefix(limit)
            .map { $0 }
    }

    /// Foods to show before anything is typed.
    public func suggestions(limit: Int = 25) -> [FoodMatch] {
        database.popularFoods(limit: limit).map { FoodMatch(food: $0, score: 0) }
    }

    // MARK: - Scoring

    /// Combines four signals, each catching a case the others miss.
    private func score(food: FoodRecord, query: String, queryTokens: [String]) -> Double {
        let name = Self.normalize(food.name)
        let nameTokens = name.split(separator: " ").map(String.init)

        // 1. Exact or prefix match on the whole name. "milk" → "Milk, whole".
        var exactness = 0.0
        if name == query {
            exactness = 1.0
        } else if name.hasPrefix(query) {
            exactness = 0.85
        } else if nameTokens.first == queryTokens.first {
            // Leading word agreeing matters because USDA names are
            // comma-inverted: the head noun is what the food *is*.
            exactness = 0.6
        }

        // 2. How much of the query the name actually covers.
        let covered = queryTokens.filter { token in
            nameTokens.contains { $0 == token || $0.hasPrefix(token) }
        }.count
        let coverage = queryTokens.isEmpty ? 0 : Double(covered) / Double(queryTokens.count)

        // 3. Brevity. A name with few extra words is usually the staple, and
        // "rice" should not return "Rice, white, glutinous, unenriched, cooked".
        let extraWords = max(0, nameTokens.count - queryTokens.count)
        let brevity = 1.0 / (1.0 + Double(extraWords) * 0.35)

        // 4. Source and name-quality prior, normalised out of the builder's
        // popularity score.
        let prior = min(1.0, Double(food.popularity) / 100.0)

        // Coverage dominates: a result missing half the query is wrong however
        // short and well-sourced it is.
        let combined = coverage * 0.45 + exactness * 0.30 + brevity * 0.15 + prior * 0.10

        // Nothing matched at all — guard against FTS prefix noise.
        return covered == 0 ? 0 : min(1.0, combined)
    }

    /// Lowercases, strips accents and punctuation, collapses whitespace.
    ///
    /// Also reverses USDA's comma-inverted phrasing so "cooked white rice"
    /// lines up with "Rice, white, cooked".
    static func normalize(_ text: String) -> String {
        let reordered = text.contains(", ")
            ? text.components(separatedBy: ", ").reversed().joined(separator: " ")
            : text
        let folded = reordered.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        let stripped = folded.replacingOccurrences(
            of: "[^a-z0-9 ]", with: " ", options: .regularExpression
        )
        return stripped
            .replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}
