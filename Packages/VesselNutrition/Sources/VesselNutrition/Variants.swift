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
        // Split on spaces, not on every non-letter: "2% milk" has already said
        // which milk, and splitting at the "%" reduced it to a bare "milk"
        // that asked again.
        let words = query
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map { $0.trimmingCharacters(in: .punctuationCharacters.subtracting(CharacterSet(charactersIn: "%"))) }
            .filter { !$0.isEmpty }

        // Only a bare term is ambiguous. "whole milk" already said which one.
        guard words.count == 1, let term = words.first,
              database.isAmbiguousHead(term)
        else { return [] }

        // Candidates are rows that are *about* this food, not rows that merely
        // mention it — "Crackers, milk" is a cracker.
        func isAbout(_ food: FoodRecord) -> Bool {
            food.name.split(separator: ",").first?
                .trimmingCharacters(in: .whitespaces).lowercased() == term
        }
        let ranked = matches.map(\.food).filter(isAbout)

        // The whole family, not just the handful the search returned: which
        // choice matters is a property of the family.
        var seen = Set<String>()
        let family = (ranked + database.headMatches(heads: [term, term + "s"], limit: 120).filter(isAbout))
            .filter { seen.insert($0.id).inserted }

        // Trusted only when it contains the row search already chose. For milk
        // that is whole milk, one of the fat levels. For coffee it's brewed
        // coffee, and the family's recurring axis turned out to be how instant
        // coffee is sweetened — a real pattern in the data, but not the
        // question anyone asking for "coffee" is answering.
        if let axis = axisOptions(family: family, limit: min(limit, 4)),
           let top = ranked.first, axis.contains(where: { $0.id == top.id }) {
            return axis
        }
        let fallback = Array(ranked.prefix(limit))
        return fallback.count >= 2 ? fallback : []
    }

    /// The variants that differ along the family's main axis.
    ///
    /// The question worth asking is the one the family keeps asking itself.
    /// Across milk's rows the same qualifiers recur — whole, skim, 1%, 2% turn
    /// up under plain, lactose-free, evaporated and reconstituted milk alike —
    /// while "malted" or "condensed" are one-offs. So the options are the rows
    /// qualified by a single clause, ranked by how often that clause closes
    /// the family's longer names, and shown richest first. For milk that is whole, 2%, 1% and
    /// skim, without anyone having written down that milk has fat levels.
    private static func axisOptions(family: [FoodRecord], limit: Int) -> [FoodRecord]? {
        var recurrence: [String: Int] = [:]
        let clausesByID = Dictionary(family.map { food in
            (food.id, FoodSearch.specifiedClauses(of: food.name).filter { !$0.hasPrefix("~") })
        }, uniquingKeysWith: { first, _ in first })
        // Counted where a clause *closes* a longer name. Fat levels finish
        // names across every form of milk — "evaporated, skim", "lactose free,
        // low fat (1%)" — while "evaporated" is itself a form that fat levels
        // attach to. Plain recurrence ranked evaporated above 1%.
        for clauses in clausesByID.values where clauses.count >= 2 {
            if let last = clauses.last { recurrence[last, default: 0] += 1 }
        }

        // One row per clause: the most popular row qualified by it alone.
        var best: [String: FoodRecord] = [:]
        for food in family {
            guard let clauses = clausesByID[food.id], clauses.count == 1, let clause = clauses.first,
                  (recurrence[clause] ?? 0) >= 1
            else { continue }
            if let current = best[clause], current.popularity >= food.popularity { continue }
            best[clause] = food
        }

        let chosen = best
            .sorted { (recurrence[$0.key] ?? 0, $0.value.popularity) > (recurrence[$1.key] ?? 0, $1.value.popularity) }
            .prefix(limit)
            .map(\.value)
            .sorted { $0.nutrientsPer100g.kilocalories > $1.nutrientsPer100g.kilocalories }

        // Worth a tap only if the choices actually change the numbers.
        guard chosen.count >= 2,
              let high = chosen.first?.nutrientsPer100g.kilocalories,
              let low = chosen.last?.nutrientsPer100g.kilocalories,
              high > 0, (high - low) / high > 0.15
        else { return nil }
        return Array(chosen)
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
        let name = food.displayName
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
