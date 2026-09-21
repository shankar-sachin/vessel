import Foundation
import VesselCore

/// Works out when a food needs a follow-up question.
///
/// "Milk" is not one food. Whole milk is 61 kcal per 100 g and skimmed is 34 —
/// a 45% difference that silently picking one would bury. The same is true of
/// bread, rice, yoghurt and a dozen other staples people name generically
/// because that's how anyone talks.
///
/// So rather than guessing, Vessel asks — but only when the answer actually
/// changes the numbers.
public enum FoodVariants {

    /// Whether the user should be asked which variant they meant.
    public static func needsChoice(
        query: String,
        matches: [FoodMatch],
        database: FoodDatabase = .shared
    ) -> Bool {
        !options(query: query, matches: matches, database: database).isEmpty
    }

    /// The variants worth offering, best first. Empty when there's no real
    /// question to ask.
    ///
    /// Which terms are ambiguous is *derived from the corpus*, not listed by
    /// hand: a head noun qualifies when several foods share it and their
    /// calories spread widely. "Milk" covers 64 rows from 32 to 496 kcal per
    /// 100 g, so it asks; "banana" covers two rows 97 to 161, so it doesn't.
    /// A hand-written list would have known about milk and missed the other
    /// four hundred.
    public static func options(
        query: String,
        matches: [FoodMatch],
        database: FoodDatabase = .shared,
        limit: Int = 6
    ) -> [FoodRecord] {
        let words = query
            .lowercased()
            .split(whereSeparator: { !$0.isLetter })
            .map(String.init)

        // Only a bare term is ambiguous. "whole milk" already said which one.
        guard words.count == 1, let term = words.first,
              database.isAmbiguousHead(term)
        else { return [] }

        // Candidates are rows that are *about* this food, not rows that merely
        // mention it — "Crackers, milk" is a cracker.
        let candidates = matches
            .map(\.food)
            .filter { food in
                let name = food.name.lowercased()
                return name.hasPrefix(term)
                    || name.hasPrefix("\(term),")
                    || name.split(separator: ",").first?.trimmingCharacters(in: .whitespaces) == term
            }
            .prefix(limit)

        guard candidates.count >= 2 else { return [] }

        return Array(candidates)
    }

    /// A short label distinguishing a variant from its siblings.
    ///
    /// "Milk, reduced fat (2%)" → "reduced fat (2%)", because repeating "Milk"
    /// on every button in a milk picker is noise.
    /// The first clause of a name, which is the food itself in USDA's style.
    public static func headNoun(of name: String) -> String {
        (name.components(separatedBy: ",").first ?? name)
            .lowercased()
            .trimmingCharacters(in: .whitespaces)
    }

    public static func distinguishingLabel(for food: FoodRecord, term: String) -> String {
        let name = food.name
        let parts = name.components(separatedBy: ", ")

        if parts.count > 1, parts[0].lowercased() == term.lowercased() {
            return parts.dropFirst().joined(separator: ", ")
        }
        if name.lowercased().hasPrefix(term.lowercased()) {
            let rest = name.dropFirst(term.count).trimmingCharacters(in: .whitespaces)
            return rest.isEmpty ? "plain" : rest
        }
        return name
    }
}

/// Foods commonly eaten together, mined from the corpus at build time.
///
/// This replaced a hand-written table. The table only knew what its author
/// thought of, and — more damningly — checking the data showed it was *wrong*:
/// USDA's only cereal-and-milk entries are baby food. What FoodData Central
/// does record, from real dietary surveys, is thousands of "X with Y"
/// composites: pasta with tomato sauce, oatmeal with milk, macaroni with
/// cheese. Those are observations, not assumptions.
///
/// This is only the cold start. `PairingStore` in VesselCore learns what *this
/// person* actually eats together and takes precedence, because the general
/// case is a weak guide to any particular breakfast.
public struct Accompaniments: Sendable {

    private let database: FoodDatabase

    public init(database: FoodDatabase = .shared) {
        self.database = database
    }

    /// A food commonly eaten with this one, according to the corpus.
    ///
    /// - Parameter alreadyLogged: other foods in the same meal, so a companion
    ///   that's already there isn't offered again.
    public func suggestion(
        for foodName: String,
        alreadyLogged: [String] = []
    ) -> (searchTerm: String, note: String)? {
        let head = FoodVariants.headNoun(of: foodName)
        guard let learned = database.companion(forHead: head) else { return nil }

        let existing = alreadyLogged.map { $0.lowercased() }
        guard !existing.contains(where: { $0.contains(learned.companion) }) else { return nil }

        return (
            learned.companion,
            "Often eaten with \(learned.companion) — seen \(learned.occurrences) times in the food data."
        )
    }
}
