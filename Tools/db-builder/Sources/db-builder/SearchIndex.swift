import Foundation

/// The search index: a food's *head noun* and how heavily qualified it is.
///
/// Without this the ranker cannot tell "Rice, white, cooked" from "Bread, rice".
/// Both contain the word, both are short, both are popular — and a search for
/// rice was returning rice crackers, rice pudding and rice paper while plain
/// cooked rice sat below the fold. The difference between them is not a score
/// to be tuned, it is a fact about English: the head noun says what a thing
/// *is*, and everything else says which kind.
///
/// USDA writes names two ways, and one rule covers both:
///
/// | Name | First clause | Head |
/// |---|---|---|
/// | `Rice, white, cooked` | `rice` | **rice** |
/// | `Rice cake` | `rice cake` | **cake** |
/// | `Bread, rice` | `bread` | **bread** |
/// | `Coffee, brewed` | `coffee` | **coffee** |
/// | `Coffee creamer` | `coffee creamer` | **creamer** |
///
/// Take the clause before the first comma, then its last word. Comma-inverted
/// names put the head first; plain compound names put it last; in both cases
/// the last word of the first clause is the noun being modified.
///
/// Derived in SQL rather than in Swift so that it is reproducible against a
/// database that already exists, without the 12 MB of USDA CSVs it was built
/// from. `db-builder --reindex <db>` applies exactly this to a built file.
enum SearchIndex {

    static let sql = """
    -- Columns are added if missing so this can run on an existing database.
    ALTER TABLE foods ADD COLUMN head TEXT NOT NULL DEFAULT '';
    ALTER TABLE foods ADD COLUMN qualifiers INTEGER NOT NULL DEFAULT 0;
    """

    /// The derivation itself, separate because the `ALTER`s above fail
    /// harmlessly on a database that already has the columns.
    static let populate = """
    -- Peel words off the front of the first clause until one word is left.
    WITH RECURSIVE clause(rid, rest) AS (
        SELECT rowid,
               trim(
                 replace(replace(replace(replace(replace(
                   lower(CASE WHEN instr(name, ',') > 0
                              THEN substr(name, 1, instr(name, ',') - 1)
                              ELSE name END),
                   '(', ' '), ')', ' '), '"', ' '), '.', ' '), '  ', ' ')
               )
          FROM foods
        UNION ALL
        SELECT rid, substr(rest, instr(rest, ' ') + 1)
          FROM clause
         WHERE instr(rest, ' ') > 0
    )
    UPDATE foods
       SET head = COALESCE(
           (SELECT rest FROM clause
             WHERE clause.rid = foods.rowid AND instr(rest, ' ') = 0
             LIMIT 1), '');

    -- How many qualifying clauses the name carries. "Rice" is the food;
    -- "Rice, white, glutinous, unenriched, cooked" is a specific case of it,
    -- and a bare search means the former.
    UPDATE foods SET qualifiers = length(name) - length(replace(name, ',', ''));

    CREATE INDEX IF NOT EXISTS idx_foods_head ON foods(head);
    """
}
