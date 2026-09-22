import Foundation
import SQLite3

/// Writes the compiled food database.
///
/// SQLite rather than a JSON blob because the app needs to *search* this at
/// keystroke speed over ~13,000 rows. FTS5 gives sub-millisecond prefix matching
/// with an index we build once here rather than on every launch.
struct DatabaseWriter {

    /// SQLite needs to know a string parameter outlives the bind call.
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    let destination: URL

    func write(_ foods: [FoodRow]) throws {
        try? FileManager.default.removeItem(at: destination)

        var handle: OpaquePointer?
        guard sqlite3_open_v2(
            destination.path, &handle,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil
        ) == SQLITE_OK, let db = handle else {
            throw BuilderError.sqlite("couldn't create \(destination.lastPathComponent)")
        }
        defer { sqlite3_close(db) }

        // This file is written once and shipped read-only, so durability
        // guarantees during the build buy nothing and cost a lot of time.
        try exec(db, "PRAGMA journal_mode = OFF")
        try exec(db, "PRAGMA synchronous = OFF")
        try exec(db, schema)

        try exec(db, "BEGIN TRANSACTION")
        try insertFoods(db, foods)
        try insertStatistics(db, foods)
        try exec(db, "COMMIT")

        // Build the search index after the rows land — far faster than
        // maintaining it incrementally through 13,000 inserts.
        try exec(db, "INSERT INTO foods_fts(foods_fts) VALUES('rebuild')")
        try DatabaseWriter.reindex(db)
        try exec(db, "ANALYZE")
        try exec(db, "VACUUM")
    }

    private var schema: String {
        """
        CREATE TABLE foods (
            rowid       INTEGER PRIMARY KEY,
            id          TEXT NOT NULL UNIQUE,
            name        TEXT NOT NULL,
            search_name TEXT NOT NULL,
            category    TEXT NOT NULL DEFAULT '',
            source      TEXT NOT NULL,
            popularity  INTEGER NOT NULL DEFAULT 0,
            staple_rank INTEGER,
            density     REAL,
            kcal        REAL NOT NULL DEFAULT 0,
            protein     REAL NOT NULL DEFAULT 0,
            carbs       REAL NOT NULL DEFAULT 0,
            fat         REAL NOT NULL DEFAULT 0,
            fiber       REAL NOT NULL DEFAULT 0,
            sugar       REAL NOT NULL DEFAULT 0,
            added_sugar REAL NOT NULL DEFAULT 0,
            sat_fat     REAL NOT NULL DEFAULT 0,
            trans_fat   REAL NOT NULL DEFAULT 0,
            cholesterol REAL NOT NULL DEFAULT 0,
            sodium      REAL NOT NULL DEFAULT 0,
            potassium   REAL NOT NULL DEFAULT 0,
            calcium     REAL NOT NULL DEFAULT 0,
            iron        REAL NOT NULL DEFAULT 0,
            vit_c       REAL NOT NULL DEFAULT 0,
            vit_d       REAL NOT NULL DEFAULT 0,
            water       REAL NOT NULL DEFAULT 0
        );

        CREATE TABLE portions (
            food_rowid INTEGER NOT NULL,
            label      TEXT NOT NULL,
            grams      REAL NOT NULL,
            seq        INTEGER NOT NULL
        );

        CREATE TABLE food_tags (
            food_rowid INTEGER NOT NULL,
            tag        TEXT NOT NULL
        );

        CREATE INDEX idx_portions_food ON portions(food_rowid);
        CREATE INDEX idx_tags_food ON food_tags(food_rowid);
        CREATE INDEX idx_tags_tag ON food_tags(tag);
        CREATE INDEX idx_foods_popularity ON foods(popularity DESC);
        CREATE INDEX idx_foods_staple ON foods(staple_rank ASC);

        -- External-content FTS5: the index points at `foods` rather than
        -- duplicating the text, which roughly halves the file size.
        -- Prefix indexes make "chi", "chic", "chick" fast as someone types.
        CREATE VIRTUAL TABLE foods_fts USING fts5(
            search_name,
            content='foods',
            content_rowid='rowid',
            prefix='2 3 4'
        );

        -- Derived from the corpus at build time rather than hand-written.
        -- See Statistics.swift for why.
        CREATE TABLE head_nouns (
            head         TEXT PRIMARY KEY,
            variant_count INTEGER NOT NULL,
            kcal_min     REAL NOT NULL,
            kcal_max     REAL NOT NULL,
            is_ambiguous INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE accompaniments (
            head        TEXT NOT NULL,
            companion   TEXT NOT NULL,
            occurrences INTEGER NOT NULL
        );
        CREATE INDEX idx_accompaniments_head ON accompaniments(head);

        CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
        """
    }

    private func insertFoods(_ db: OpaquePointer, _ foods: [FoodRow]) throws {
        let foodSQL = """
        INSERT INTO foods (rowid, id, name, search_name, category, source, popularity, staple_rank, density,
            kcal, protein, carbs, fat, fiber, sugar, added_sugar, sat_fat, trans_fat,
            cholesterol, sodium, potassium, calcium, iron, vit_c, vit_d, water)
        VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14,?15,?16,?17,?18,?19,?20,?21,?22,?23,?24,?25,?26)
        """
        var foodStatement: OpaquePointer?
        guard sqlite3_prepare_v2(db, foodSQL, -1, &foodStatement, nil) == SQLITE_OK else {
            throw BuilderError.sqlite("prepare foods: \(String(cString: sqlite3_errmsg(db)))")
        }
        defer { sqlite3_finalize(foodStatement) }

        var portionStatement: OpaquePointer?
        sqlite3_prepare_v2(db, "INSERT INTO portions (food_rowid, label, grams, seq) VALUES (?1,?2,?3,?4)", -1, &portionStatement, nil)
        defer { sqlite3_finalize(portionStatement) }

        var tagStatement: OpaquePointer?
        sqlite3_prepare_v2(db, "INSERT INTO food_tags (food_rowid, tag) VALUES (?1,?2)", -1, &tagStatement, nil)
        defer { sqlite3_finalize(tagStatement) }

        for (offset, food) in foods.enumerated() {
            let rowid = Int64(offset + 1)
            sqlite3_reset(foodStatement)
            sqlite3_bind_int64(foodStatement, 1, rowid)
            bind(foodStatement, 2, food.id)
            bind(foodStatement, 3, food.name)
            bind(foodStatement, 4, food.searchName)
            bind(foodStatement, 5, food.category)
            bind(foodStatement, 6, food.source.rawValue)
            sqlite3_bind_int(foodStatement, 7, Int32(food.popularity))
            if let rank = food.stapleRank {
                sqlite3_bind_int(foodStatement, 8, Int32(rank))
            } else {
                sqlite3_bind_null(foodStatement, 8)
            }
            if let density = food.density {
                sqlite3_bind_double(foodStatement, 9, density)
            } else {
                sqlite3_bind_null(foodStatement, 9)
            }

            let columns: [Int] = [
                NutrientID.protein, NutrientID.carbohydrate, NutrientID.fat,
                NutrientID.fiber, NutrientID.sugar, NutrientID.addedSugar,
                NutrientID.saturatedFat, NutrientID.transFat, NutrientID.cholesterol,
                NutrientID.sodium, NutrientID.potassium, NutrientID.calcium,
                NutrientID.iron, NutrientID.vitaminC, NutrientID.vitaminD, NutrientID.water
            ]
            sqlite3_bind_double(foodStatement, 10, food.kilocalories)
            for (index, nutrient) in columns.enumerated() {
                sqlite3_bind_double(foodStatement, Int32(11 + index), food.nutrients[nutrient] ?? 0)
            }

            guard sqlite3_step(foodStatement) == SQLITE_DONE else {
                throw BuilderError.sqlite("insert \(food.id): \(String(cString: sqlite3_errmsg(db)))")
            }

            for (index, portion) in food.portions.enumerated() {
                sqlite3_reset(portionStatement)
                sqlite3_bind_int64(portionStatement, 1, rowid)
                bind(portionStatement, 2, portion.label)
                sqlite3_bind_double(portionStatement, 3, portion.grams)
                sqlite3_bind_int(portionStatement, 4, Int32(index))
                sqlite3_step(portionStatement)
            }

            for tag in food.tags.sorted() {
                sqlite3_reset(tagStatement)
                sqlite3_bind_int64(tagStatement, 1, rowid)
                bind(tagStatement, 2, tag)
                sqlite3_step(tagStatement)
            }
        }

        try exec(db, """
            INSERT INTO meta (key, value) VALUES
                ('schema_version', '1'),
                ('source', 'USDA FoodData Central'),
                ('built_at', '\(ISO8601DateFormatter().string(from: Date()))'),
                ('food_count', '\(foods.count)');
            """)
    }

    /// Writes the derived ambiguity and co-occurrence tables.
    private func insertStatistics(_ db: OpaquePointer, _ foods: [FoodRow]) throws {
        var headStatement: OpaquePointer?
        sqlite3_prepare_v2(db, """
            INSERT INTO head_nouns (head, variant_count, kcal_min, kcal_max, is_ambiguous)
            VALUES (?1,?2,?3,?4,?5)
            """, -1, &headStatement, nil)
        defer { sqlite3_finalize(headStatement) }

        for head in Statistics.headNouns(in: foods) {
            sqlite3_reset(headStatement)
            bind(headStatement, 1, head.head)
            sqlite3_bind_int(headStatement, 2, Int32(head.count))
            sqlite3_bind_double(headStatement, 3, head.minimumEnergy)
            sqlite3_bind_double(headStatement, 4, head.maximumEnergy)
            sqlite3_bind_int(headStatement, 5, head.isAmbiguous ? 1 : 0)
            sqlite3_step(headStatement)
        }

        var companionStatement: OpaquePointer?
        sqlite3_prepare_v2(db, """
            INSERT INTO accompaniments (head, companion, occurrences) VALUES (?1,?2,?3)
            """, -1, &companionStatement, nil)
        defer { sqlite3_finalize(companionStatement) }

        for pair in Statistics.accompaniments(in: foods) {
            sqlite3_reset(companionStatement)
            bind(companionStatement, 1, pair.head)
            bind(companionStatement, 2, pair.companion)
            sqlite3_bind_int(companionStatement, 3, Int32(pair.occurrences))
            sqlite3_step(companionStatement)
        }
    }

    private func bind(_ statement: OpaquePointer?, _ index: Int32, _ value: String) {
        sqlite3_bind_text(statement, index, value, -1, Self.transient)
    }

    /// Derives the head-noun search index. Safe to run on a database that
    /// already has it — the `ALTER`s fail, and only those, which is why they
    /// are executed apart from the derivation.
    static func reindex(_ db: OpaquePointer) throws {
        for statement in SearchIndex.sql.split(separator: ";") {
            let trimmed = statement.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            sqlite3_exec(db, trimmed, nil, nil, nil)   // duplicate column is expected
        }
        guard sqlite3_exec(db, SearchIndex.populate, nil, nil, nil) == SQLITE_OK else {
            throw BuilderError.sqlite("reindex: \(String(cString: sqlite3_errmsg(db)))")
        }
    }

    private func exec(_ db: OpaquePointer, _ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(error)
            throw BuilderError.sqlite(message)
        }
    }
}

enum BuilderError: LocalizedError {
    case sqlite(String)
    case missingInput(String)

    var errorDescription: String? {
        switch self {
        case .sqlite(let detail):  return "SQLite: \(detail)"
        case .missingInput(let p): return "Couldn't find \(p)"
        }
    }
}
