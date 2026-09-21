import Foundation
import SQLite3
import VesselCore

/// Read-only access to the bundled USDA database.
///
/// Uses SQLite directly rather than a wrapper library: the queries here are a
/// handful of statements prepared once, and a dependency would add build weight
/// without removing any of the code that actually matters.
public final class FoodDatabase: @unchecked Sendable {

    /// Shared instance. Opening the database is cheap but not free, and every
    /// search in the app wants the same prepared statements.
    public static let shared = FoodDatabase()

    private var handle: OpaquePointer?
    /// Serializes access. SQLite is opened in the default threading mode, and
    /// searches can arrive from the UI and from the parser at once.
    private let lock = NSLock()

    /// Nil when the bundled file is missing or unreadable — the app degrades to
    /// manual entry rather than refusing to open.
    public private(set) var isAvailable = false

    public init(url: URL? = nil) {
        let location = url ?? Bundle.module.url(forResource: "foods", withExtension: "sqlite")
        guard let location else { return }

        var db: OpaquePointer?
        // Read-only: nothing in the app ever writes here, and saying so lets
        // SQLite skip journalling entirely.
        guard sqlite3_open_v2(location.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return
        }
        handle = db
        isAvailable = true
    }

    deinit {
        if let handle { sqlite3_close(handle) }
    }

    /// Total foods, for diagnostics and tests.
    public var foodCount: Int {
        lock.lock(); defer { lock.unlock() }
        guard let handle else { return 0 }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(handle, "SELECT count(*) FROM foods", -1, &statement, nil) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW
        else { return 0 }
        return Int(sqlite3_column_int(statement, 0))
    }

    // MARK: - Lookup

    /// Fetches one food by its stable id.
    public func food(withID id: String) -> FoodRecord? {
        lock.lock(); defer { lock.unlock() }
        guard let handle else { return nil }

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(handle, Self.selectColumns + " WHERE f.id = ?1 LIMIT 1", -1, &statement, nil) == SQLITE_OK
        else { return nil }
        bind(statement, 1, id)

        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return record(from: statement, handle: handle)
    }

    /// The most commonly logged foods, for an empty search box.
    ///
    /// An empty state that offers nothing is a dead end; offering the staples
    /// means the fastest path for most meals is two taps.
    public func popularFoods(limit: Int = 25) -> [FoodRecord] {
        lock.lock(); defer { lock.unlock() }
        guard let handle else { return [] }

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        // Staples first. Ranking purely by the builder's popularity score put
        // the shortest names on top, which in USDA's data means "Dal", "Flan"
        // and "Bear" — a useless list to start logging breakfast from.
        // Curated staples in their curated order, then everything else.
        // Ranking purely by the builder's popularity score put the shortest
        // names on top, which in USDA's data means "Dal", "Flan" and "Bear" —
        // a useless list to start logging breakfast from.
        let sql = Self.selectColumns
            + """
               ORDER BY CASE WHEN f.staple_rank IS NULL THEN 1 ELSE 0 END,
                        f.staple_rank ASC,
                        f.popularity DESC,
                        length(f.name) ASC
               LIMIT ?1
            """
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        sqlite3_bind_int(statement, 1, Int32(limit))

        var results: [FoodRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let record = record(from: statement, handle: handle) { results.append(record) }
        }
        return results
    }

    // MARK: - Search

    /// Candidate lookup by full-text match.
    ///
    /// Returns more rows than the UI shows so the ranker upstream has something
    /// to work with — FTS decides *whether* a row matches, not how well.
    func candidates(matching query: String, limit: Int) -> [FoodRecord] {
        lock.lock(); defer { lock.unlock() }
        guard let handle, let ftsQuery = Self.ftsExpression(for: query) else { return [] }

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let sql = """
        \(Self.selectColumns)
        JOIN foods_fts ON foods_fts.rowid = f.rowid
        WHERE foods_fts MATCH ?1
        ORDER BY bm25(foods_fts) ASC, f.popularity DESC
        LIMIT ?2
        """
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        bind(statement, 1, ftsQuery)
        sqlite3_bind_int(statement, 2, Int32(limit))

        var results: [FoodRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let record = record(from: statement, handle: handle) { results.append(record) }
        }
        return results
    }

    /// Builds an FTS5 expression from raw user text.
    ///
    /// Every token gets a `*` so results appear while someone is still typing,
    /// and tokens are ANDed so "chicken breast" narrows rather than widens.
    /// User text is never interpolated raw — FTS5 has its own operator syntax
    /// and a stray quote or `-` would otherwise change the query's meaning.
    static func ftsExpression(for query: String) -> String? {
        let tokens = query
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }

        guard !tokens.isEmpty else { return nil }
        return tokens.map { "\"\($0)\"*" }.joined(separator: " AND ")
    }

    // MARK: - Row decoding

    private static let selectColumns = """
    SELECT f.rowid, f.id, f.name, f.category, f.source, f.popularity, f.density,
           f.kcal, f.protein, f.carbs, f.fat, f.fiber, f.sugar, f.added_sugar,
           f.sat_fat, f.trans_fat, f.cholesterol, f.sodium, f.potassium,
           f.calcium, f.iron, f.vit_c, f.vit_d, f.water
    FROM foods f
    """

    private func record(from statement: OpaquePointer?, handle: OpaquePointer) -> FoodRecord? {
        let rowid = sqlite3_column_int64(statement, 0)
        guard let id = text(statement, 1), let name = text(statement, 2) else { return nil }

        let nutrients = Nutrients(
            kilocalories: sqlite3_column_double(statement, 7),
            proteinG: sqlite3_column_double(statement, 8),
            carbohydrateG: sqlite3_column_double(statement, 9),
            fatG: sqlite3_column_double(statement, 10),
            fiberG: sqlite3_column_double(statement, 11),
            sugarG: sqlite3_column_double(statement, 12),
            addedSugarG: sqlite3_column_double(statement, 13),
            saturatedFatG: sqlite3_column_double(statement, 14),
            transFatG: sqlite3_column_double(statement, 15),
            cholesterolMG: sqlite3_column_double(statement, 16),
            sodiumMG: sqlite3_column_double(statement, 17),
            potassiumMG: sqlite3_column_double(statement, 18),
            calciumMG: sqlite3_column_double(statement, 19),
            ironMG: sqlite3_column_double(statement, 20),
            vitaminCMG: sqlite3_column_double(statement, 21),
            vitaminDMCG: sqlite3_column_double(statement, 22),
            waterML: sqlite3_column_double(statement, 23)
        )

        return FoodRecord(
            id: id,
            name: name,
            category: text(statement, 3) ?? "",
            source: text(statement, 4) ?? "",
            popularity: Int(sqlite3_column_int(statement, 5)),
            density: sqlite3_column_type(statement, 6) == SQLITE_NULL
                ? nil : sqlite3_column_double(statement, 6),
            nutrientsPer100g: nutrients,
            portions: portions(forRowID: rowid, handle: handle),
            tags: tags(forRowID: rowid, handle: handle)
        )
    }

    private func portions(forRowID rowid: Int64, handle: OpaquePointer) -> [FoodPortion] {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(
            handle, "SELECT label, grams FROM portions WHERE food_rowid = ?1 ORDER BY seq", -1, &statement, nil
        ) == SQLITE_OK else { return [] }
        sqlite3_bind_int64(statement, 1, rowid)

        var results: [FoodPortion] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let label = text(statement, 0) else { continue }
            results.append(FoodPortion(label: label, grams: sqlite3_column_double(statement, 1)))
        }
        return results
    }

    private func tags(forRowID rowid: Int64, handle: OpaquePointer) -> [String] {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(
            handle, "SELECT tag FROM food_tags WHERE food_rowid = ?1 ORDER BY tag", -1, &statement, nil
        ) == SQLITE_OK else { return [] }
        sqlite3_bind_int64(statement, 1, rowid)

        var results: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let tag = text(statement, 0) { results.append(tag) }
        }
        return results
    }

    private func text(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: pointer)
    }

    private func bind(_ statement: OpaquePointer?, _ index: Int32, _ value: String) {
        // SQLITE_TRANSIENT: tell SQLite to copy, since the Swift string may not
        // outlive the call.
        sqlite3_bind_text(statement, index, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }
}
