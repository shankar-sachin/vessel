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

        let queryTokens = cleaned.split(separator: " ").map(String.init)
        let stems = Set(queryTokens.map(Self.stem))

        // Two candidate passes, because they answer different questions.
        // FTS finds every name containing the words; the head-noun pass finds
        // the names that are *about* them. Without the second, "rice" never
        // sees "Rice, white, cooked" — it is one of 161 matches and bm25 has no
        // reason to float it above rice paper.
        var candidates = database.headMatches(heads: Array(stems.union(stems.map { $0 + "s" })), limit: 60)
        var seen = Set(candidates.map(\.id))
        for candidate in database.candidates(matching: cleaned, limit: 200) where seen.insert(candidate.id).inserted {
            candidates.append(candidate)
        }
        guard !candidates.isEmpty else { return [] }

        let typicality = Self.typicality(of: candidates)
        return candidates
            .map { food in
                FoodMatch(food: food, score: score(
                    food: food, query: cleaned, queryTokens: queryTokens,
                    typicality: typicality[food.id] ?? Typicality(score: 0, qualifierCost: Double(food.qualifiers))
                ))
            }
            .filter { $0.score > 0 }
            .sorted { lhs, rhs in
                // Ties are common — many rows differ only in a qualifier the
                // query said nothing about — so they are broken deliberately
                // rather than left to whatever order SQLite returned.
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                if lhs.food.isStaple != rhs.food.isStaple { return lhs.food.isStaple }
                if lhs.food.popularity != rhs.food.popularity {
                    return lhs.food.popularity > rhs.food.popularity
                }
                return lhs.food.name.count < rhs.food.name.count
            }
            .prefix(limit)
            .map { $0 }
    }

    /// Foods to show before anything is typed.
    public func suggestions(limit: Int = 25) -> [FoodMatch] {
        database.popularFoods(limit: limit).map { FoodMatch(food: $0, score: 0) }
    }

    // MARK: - Scoring

    /// Combines five signals, each catching a case the others miss.
    ///
    /// The one that matters most is `aboutness`. Coverage, brevity and
    /// popularity between them cheerfully rank "Rice cake" above "Rice, white,
    /// cooked": it contains the whole query, it is two words long, and USDA
    /// scores it just as popular. Nothing in that trio knows that a rice cake
    /// is a cake. The head noun does.
    private func score(food: FoodRecord, query: String, queryTokens: [String], typicality: Typicality) -> Double {
        let name = Self.normalize(food.name)
        let nameTokens = name.split(separator: " ").map(String.init)
        let queryStems = queryTokens.map(Self.stem)
        let head = Self.stem(food.head)

        // 1. Is this name *about* what was asked for?
        //
        // English puts the head noun last in a compound and USDA puts it first
        // in an inverted name; the database resolves both to a single word, so
        // here it is one comparison. A row whose head is absent from the query
        // is named for something else — "Bread, rice" is bread — and no amount
        // of word overlap makes it the answer.
        var aboutness: Double
        if name == query {
            aboutness = 1.0
        } else if let last = queryStems.last, head == last {
            // "chicken breast" → a row whose head is "breast".
            aboutness = 0.9
        } else if queryStems.contains(head) {
            aboutness = 0.6
        } else {
            aboutness = 0.0
        }

        // Words standing in front of the head that nobody asked for.
        //
        // "Almond chicken" and "Chicken, roasted" both have chicken as their
        // head, so aboutness alone ranks the first higher — it has no qualifying
        // clauses to be docked for. But a modifier before the head changes what
        // the dish *is* far more than a clause after it does: almond chicken is
        // not a kind of chicken you get by asking for chicken. Each unasked-for
        // modifier costs more than a qualifier, which is why this is not simply
        // folded into `brevity`.
        let unaskedModifiers = Self.headClauseTokens(of: food.name)
            .filter { token in !queryStems.contains(Self.stem(token)) }
            .count
        aboutness = max(0, aboutness - Double(unaskedModifiers) * 0.25)

        // 2. How much of the query the name actually covers.
        //
        // Compared on stems as well as raw words. Raw only, "eggs" covered
        // nothing in "Egg, whole, cooked" — so the only rows that could win were
        // the handful USDA happened to spell "Eggs", led by egg yolk.
        let nameStems = Set(nameTokens.map(Self.stem))
        let covered = queryTokens.filter { token in
            nameStems.contains(Self.stem(token))
                || nameTokens.contains { $0 == token || $0.hasPrefix(token) }
        }.count
        let coverage = queryTokens.isEmpty ? 0 : Double(covered) / Double(queryTokens.count)

        // 3. How heavily qualified the name is. Counted in clauses rather than
        // words, because a clause is a decision the user did not make: asking
        // for rice should not land on "glutinous, unenriched".
        //
        // Except USDA's own "not specified" clauses. "Coffee, NS as to type" is
        // how the survey coded someone who said just "coffee": the clause
        // records a decision *not* made, which is exactly the user's position.
        // Counting it as a qualifier ranked those rows below "Coffee, Cuban".
        //
        // And each clause is charged by how unusual it is in the food's family
        // (see `typicality(of:)`): "Egg, whole, raw" pins down less than
        // "Egg, creamed", despite having more commas.
        let unspecified = Self.unspecifiedClauseCount(in: food.name)
        let specified = max(0, food.qualifiers - unspecified)
        let brevity = 1.0 / (1.0 + typicality.qualifierCost * 0.3)
        // Rows that leave something open, and pin nothing else down, are the
        // generic answer to a query that pinned nothing down either.
        let generic = unspecified > 0 && specified <= unspecified ? 1.0 : 0.0

        // 4. Curated everyday foods, in the builder's order.
        let staple = food.isStaple ? 1.0 : 0.0

        // 5. Source and name-quality prior, normalised out of the builder's
        // popularity score.
        let prior = min(1.0, Double(food.popularity) / 100.0)

        // 6. `typicality`: how ordinary this row's qualifiers are among its
        // own family. Computed per search; see `typicality(of:)`.

        let combined = coverage * 0.35 + aboutness * 0.35 + brevity * 0.12
            + staple * 0.10 + prior * 0.08 + generic * 0.06 + typicality.score * 0.10

        // Nothing matched at all — guard against FTS prefix noise.
        return covered == 0 ? 0 : min(1.0, combined)
    }

    /// How ordinary each candidate is among the rows sharing its head noun.
    ///
    /// Of the egg rows, dozens say "whole" and one says "creamed"; of the
    /// melons, most say "raw" and one says "frozen". A clause shared across a
    /// family describes the ordinary food, and a rare one describes a special
    /// case — which is what a bare "eggs" or "melon" does not ask for. Each row
    /// scores the mean share of its family that carries each of its clauses.
    /// "Not specified" clauses are skipped; they are scored by `generic`.
    ///
    /// On its own this is noisy — it rewards whatever USDA catalogued densely,
    /// so it rates decaf lattes as the typical coffee — which is why it only
    /// ever breaks near-ties between rows the other signals already like.
    static func typicality(of foods: [FoodRecord]) -> [String: Typicality] {
        let families = Dictionary(grouping: foods) { stem($0.head) }
        var result: [String: Typicality] = [:]
        for members in families.values {
            let clausesByID = Dictionary(uniqueKeysWithValues: members.map { food in
                (food.id, specifiedClauses(of: food.name))
            })
            var counts: [String: Int] = [:]
            for clauses in clausesByID.values {
                for clause in Set(clauses) { counts[clause, default: 0] += 1 }
            }
            // Relative to the family's commonest clause, so a big family with
            // many shallow variants doesn't flatten every share towards zero.
            let commonest = Double(max(1, counts.values.max() ?? 1))
            func share(_ clause: String) -> Double { Double(counts[clause] ?? 0) / commonest }

            for food in members {
                let clauses = clausesByID[food.id] ?? []
                let mean = clauses.isEmpty ? 1.0 : clauses.map(share).reduce(0, +) / Double(clauses.count)
                // What the trailing clauses cost `brevity`: a clause most of the
                // family shares ("whole" for eggs) is close to free; a rare one
                // ("creamed") costs a full qualifier.
                let cost = clauses.filter { !$0.hasPrefix("~") }.map { 1 - share($0) }.reduce(0, +)
                result[food.id] = Typicality(score: mean, qualifierCost: cost)
            }
        }
        return result
    }

    struct Typicality {
        /// Mean relative share of the row's clauses within its family, 0...1.
        var score: Double
        /// Trailing qualifiers, each weighted by how unusual it is.
        var qualifierCost: Double
    }

    /// A name's qualifying clauses, normalised, without "not specified" ones.
    ///
    /// Words standing before the head in the first clause count as clauses
    /// too: "Dessert pizza" has no comma, but "dessert" qualifies it every bit
    /// as much as ", dessert" would.
    static func specifiedClauses(of name: String) -> [String] {
        let modifiers = headClauseTokens(of: name).dropLast().map { "~" + stem($0) }
        let trailing = name.components(separatedBy: ",").dropFirst()
            .filter { !isUnspecified($0) }
            .map(normalize)
            .filter { !$0.isEmpty }
        return modifiers + trailing
    }

    private static func isUnspecified(_ clause: String) -> Bool {
        clause.split(separator: " ").contains("NFS") || clause.contains("NS as to")
    }

    /// How many of a name's clauses are USDA's "not specified" markers —
    /// "NS as to fat", "NFS", "white or NFS".
    static func unspecifiedClauseCount(in name: String) -> Int {
        name.components(separatedBy: ",").dropFirst().filter(isUnspecified).count
    }

    /// The words of a name's first clause — everything before the first comma,
    /// which is the food itself rather than how it was prepared.
    static func headClauseTokens(of name: String) -> [String] {
        let firstClause = name.components(separatedBy: ",").first ?? name
        return normalize(firstClause).split(separator: " ").map(String.init)
    }

    /// Crude singular form, enough to line "apple" up with "Apples, raw".
    ///
    /// Not a real stemmer, and it does not need to be: it is applied to both
    /// sides of every comparison, so the only thing that matters is that a
    /// word and its plural land on the same string. Whether that string is a
    /// word is beside the point — `molasses` and `molass` are both fine as long
    /// as nothing else stems to either.
    static func stem(_ word: String) -> String {
        guard word.count > 3 else { return word }
        if word.hasSuffix("ies"), word.count > 4 { return word.dropLast(3) + "y" }
        // "-es" is only a plural marker after a sibilant. Elsewhere the "e"
        // belongs to the word: apples is apple + s, not appl + es.
        for ending in ["sses", "shes", "ches", "xes", "zes", "oes"] where word.hasSuffix(ending) {
            return String(word.dropLast(2))
        }
        guard word.hasSuffix("s"), !word.hasSuffix("ss"), !word.hasSuffix("us") else { return word }
        return String(word.dropLast())
    }

    /// Lowercases, strips accents and punctuation, collapses whitespace.
    ///
    /// It used to also reverse USDA's comma-inverted phrasing, so that "cooked
    /// white rice" lined up with "Rice, white, cooked". That reversal is gone:
    /// it moved the head noun to the *end* of every inverted name, which taught
    /// the ranker that "Chicken curry" was a better answer to "chicken" than
    /// "Chicken, roasted" was. Word order is handled by token coverage, which
    /// never cared about it in the first place.
    static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        let stripped = folded.replacingOccurrences(
            of: "[^a-z0-9 ]", with: " ", options: .regularExpression
        )
        return stripped
            .replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}
