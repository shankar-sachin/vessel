import Foundation
import SQLite3

// Compiles the USDA FoodData Central CSV dumps into Vessel's bundled database.
//
//   swift run db-builder <input-dir> <output.sqlite>
//
// <input-dir> holds the extracted dataset folders. Datasets are merged in
// increasing order of name quality, and later sources win when the same food
// appears twice — see `deduplicate`.

let arguments = CommandLine.arguments

// Rebuilding from the CSVs needs 12 MB of USDA downloads. Re-deriving the
// search index needs only the database, so it gets its own entry point.
if arguments.count == 3, arguments[1] == "--reindex" {
    var handle: OpaquePointer?
    guard sqlite3_open_v2(arguments[2], &handle, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK,
          let db = handle else {
        print("cannot open \(arguments[2])")
        exit(1)
    }
    try DatabaseWriter.reindex(db)
    sqlite3_exec(db, "ANALYZE", nil, nil, nil)
    sqlite3_close(db)
    print("reindexed \(arguments[2])")
    exit(0)
}

guard arguments.count >= 3 else {
    print("""
    usage: db-builder <input-dir> <output.sqlite>

      <input-dir>  directory containing extracted FoodData Central folders
      <output>     path to write the compiled SQLite database

    db-builder --reindex <db.sqlite>

      re-derives the head-noun search index on an existing database
    """)
    exit(2)
}

let inputRoot = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2])

/// Finds the dataset folder for a source, wherever the zip nested it.
func locate(_ marker: String, under root: URL) -> URL? {
    guard let enumerator = FileManager.default.enumerator(
        at: root, includingPropertiesForKeys: [.isDirectoryKey]
    ) else { return nil }

    for case let url as URL in enumerator {
        guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
        guard url.lastPathComponent.contains(marker) else { continue }
        // The zips wrap the real folder in one of the same name, so only accept
        // the level that actually holds the CSVs.
        if FileManager.default.fileExists(atPath: url.appendingPathComponent("food.csv").path) {
            return url
        }
    }
    return nil
}

let datasets: [(marker: String, source: DataSource)] = [
    ("sr_legacy", .legacy),
    ("foundation", .foundation),
    ("survey", .survey)
]

var all: [FoodRow] = []

for dataset in datasets {
    guard let directory = locate(dataset.marker, under: inputRoot) else {
        print("  – skipping \(dataset.source.rawValue): no folder matching '\(dataset.marker)'")
        continue
    }
    let loaded = try DatasetLoader(directory: directory, source: dataset.source).load()
    print("  · \(dataset.source.rawValue): \(loaded.count) foods")
    all.append(contentsOf: loaded)
}

guard !all.isEmpty else {
    print("No foods loaded — check the input directory.")
    exit(1)
}

/// Collapses foods that are the same thing under different USDA names.
///
/// Searching "whole milk" and getting the FNDDS entry, the SR Legacy entry and a
/// Foundation entry — three rows, three slightly different calorie counts — is
/// confusing and makes the app look wrong. Keeping the highest-ranked of each
/// duplicate name gives one clear answer.
func deduplicate(_ foods: [FoodRow]) -> [FoodRow] {
    var best: [String: FoodRow] = [:]
    for food in foods {
        let key = food.searchName
        if let existing = best[key], existing.popularity >= food.popularity { continue }
        best[key] = food
    }
    return best.values.sorted { lhs, rhs in
        lhs.popularity == rhs.popularity ? lhs.name < rhs.name : lhs.popularity > rhs.popularity
    }
}

var deduplicated = deduplicate(all)
print("  · merged: \(all.count) → \(deduplicated.count) after deduplication")

let stapleRanks = Staples.resolve(in: deduplicated)
for index in deduplicated.indices {
    deduplicated[index].stapleRank = stapleRanks[deduplicated[index].id]
}
print("  · staples: \(stapleRanks.count) of \(Staples.terms.count) terms resolved")

try DatabaseWriter(destination: outputURL).write(deduplicated)

let size = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int) ?? 0
let tagged = deduplicated.filter { !$0.tags.isEmpty }.count
let withPortions = deduplicated.filter { !$0.portions.isEmpty }.count
let withDensity = deduplicated.filter { $0.density != nil }.count

print("""

Wrote \(outputURL.lastPathComponent)
  foods        \(deduplicated.count)
  with tags    \(tagged)
  with portions \(withPortions)
  with density \(withDensity)
  staples      \(deduplicated.filter(\.isStaple).count)
  ambiguous    \(Statistics.headNouns(in: deduplicated).filter(\.isAmbiguous).count) head nouns
  companions   \(Statistics.accompaniments(in: deduplicated).count) learned pairs
  size         \(String(format: "%.1f MB", Double(size) / 1_048_576))
""")
