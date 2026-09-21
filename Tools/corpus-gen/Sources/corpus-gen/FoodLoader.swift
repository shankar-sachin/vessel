import Foundation
import SQLite3

/// Reads food names out of the database the app ships.
///
/// Training on the *actual* names the resolver will search means the tagger
/// learns the vocabulary it will meet. A corpus built from invented food names
/// would teach the model a language the database doesn't speak.
enum FoodLoader {

    /// Loads names, converted from USDA's comma-inverted style into the order a
    /// person would say them.
    ///
    /// - Parameter limit: cap on how many names to draw from, taking the most
    ///   commonly logged first. Every name in the database would skew the
    ///   corpus towards obscure entries nobody types.
    static func load(from url: URL, limit: Int) throws -> [Generator.FoodName] {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let db = handle
        else { throw CorpusError.cannotOpenDatabase(url.path) }
        defer { sqlite3_close(db) }

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        let sql = """
        SELECT name FROM foods
        ORDER BY CASE WHEN staple_rank IS NULL THEN 1 ELSE 0 END,
                 staple_rank ASC, popularity DESC
        LIMIT ?1
        """
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CorpusError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        sqlite3_bind_int(statement, 1, Int32(limit))

        var names: [Generator.FoodName] = []
        var seen = Set<String>()

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let raw = sqlite3_column_text(statement, 0) else { continue }
            let spoken = spokenForm(String(cString: raw))
            guard isUsableForCorpus(spoken), !seen.contains(spoken) else { continue }
            seen.insert(spoken)
            names.append(
                Generator.FoodName(spoken: spoken, hasPrep: containsPreparation(spoken))
            )
        }
        return names
    }

    /// "Rice, white, cooked" → "cooked white rice".
    ///
    /// USDA writes names head-noun first so they sort usefully; people say them
    /// the other way round. Training on the database form would teach the model
    /// a word order nobody uses.
    static func spokenForm(_ name: String) -> String {
        let parts = name.components(separatedBy: ", ")
        let reordered = parts.count > 1 ? parts.reversed().joined(separator: " ") : name

        return reordered
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: nil)
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Words that join clauses. A food name that contains one, once inverted,
    /// produces sentences like "i ate with beef lo mein" — and labelling that
    /// "with" as FOOD teaches the tagger that connectors are food, which then
    /// breaks segmentation on every real utterance.
    private static let connectors: Set<String> = [
        "with", "and", "or", "from", "in", "as", "to", "on", "plus", "than"
    ]

    /// USDA bookkeeping that reads as nonsense inside a sentence.
    private static let artifacts = [
        "skin eaten", "skin not eaten", "ns as to", "added from",
        "not further specified", "quantity not specified", "nfs",
        "baby food", "infant", "unprepared", "includes", "commodity",
        "composite of", "all varieties", "reduced sodium", "low sodium"
    ]

    /// Whether a name is clean enough to build training sentences from.
    ///
    /// Stricter than what the app will happily *search* — the database keeps
    /// every one of these; this filter only decides what the corpus is written
    /// in. A name that can't appear in a natural sentence teaches the model
    /// nothing useful and actively confuses the labels.
    static func isUsableForCorpus(_ spoken: String) -> Bool {
        let words = spoken.split(separator: " ").map(String.init)

        // One to five words. Longer names produce unwieldy sentences that don't
        // resemble anything a person types.
        guard (1...5).contains(words.count), spoken.count >= 3 else { return false }

        // A bare number inside a food name collides head-on with QTY, the label
        // that matters most. "Milk, reduced fat (2%)" inverts to "2 reduced fat
        // milk", which would teach the tagger that a leading digit is food.
        guard !words.contains(where: { $0.allSatisfy(\.isNumber) }) else { return false }

        // No connectors anywhere: leading ones produce broken sentences,
        // interior ones teach the tagger that "and" can be part of a food.
        guard Set(words).isDisjoint(with: connectors) else { return false }

        guard !artifacts.contains(where: { spoken.contains($0) }) else { return false }

        return true
    }

    private static let preparationWords: Set<String> = [
        "raw", "cooked", "grilled", "fried", "baked", "boiled", "roasted",
        "steamed", "scrambled", "poached", "toasted", "dried", "canned", "frozen"
    ]

    static func containsPreparation(_ name: String) -> Bool {
        !Set(name.split(separator: " ").map(String.init)).isDisjoint(with: preparationWords)
    }
}

enum CorpusError: LocalizedError {
    case cannotOpenDatabase(String)
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case .cannotOpenDatabase(let path): return "Couldn't open the food database at \(path)"
        case .queryFailed(let detail):      return "Query failed: \(detail)"
        }
    }
}
