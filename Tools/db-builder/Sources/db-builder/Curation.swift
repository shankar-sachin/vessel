import Foundation

/// Turns USDA's database-speak into something a person would recognise.
///
/// This matters more than it sounds. The raw descriptions are written for
/// nutritionists — "Milk, whole, 3.25% milkfat, with added vitamin D" — and if
/// the search results read like that, people stop trusting that the app knows
/// what they ate. Worse, the parser in Phase 3 trains on these names, so noise
/// here becomes noise in the model.
enum Curation {

    /// Entries that aren't food anyone logs.
    private static let rejectedSubstrings = [
        "not further specified",
        "quantity not specified",
        "formulated bar",
        "infant formula",
        "nutritional supplement",
        "meal replacement",
        "used in the preparation",
        "industrial",
        "unprepared"
    ]

    static func isUsable(name: String) -> Bool {
        guard name.count >= 3, name.count <= 90 else { return false }
        let lowered = name.lowercased()
        return !rejectedSubstrings.contains { lowered.contains($0) }
    }

    /// Trims the trailing clauses that make USDA names unreadable.
    static func cleanName(_ raw: String) -> String {
        var name = raw

        // Strip parenthetical scientific names and USDA bookkeeping.
        name = name.replacingOccurrences(
            of: #"\s*\((?:includes foods for|Includes foods for)[^)]*\)"#,
            with: "", options: .regularExpression
        )

        // Drop trailing qualifier clauses that add nothing for a logging app.
        let droppableSuffixes = [
            "with added vitamin d", "with added vitamin a and vitamin d",
            "with added vitamin a", "without added vitamin a",
            "unenriched", "enriched", "commercially prepared",
            "prepared from recipe", "home prepared", "nfs",
            "all commercial varieties", "composite of cuts",
            "raw or cooked", "usda commodity"
        ]
        var parts = name.components(separatedBy: ", ")
        while let last = parts.last?.lowercased().trimmingCharacters(in: .whitespaces),
              droppableSuffixes.contains(last), parts.count > 1 {
            parts.removeLast()
        }
        name = parts.joined(separator: ", ")

        // USDA caps some entries entirely; sentence case reads far better.
        if name == name.uppercased(), name.rangeOfCharacter(from: .lowercaseLetters) == nil {
            name = name.capitalized
        }

        name = name.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The form used for matching: lowercased, punctuation flattened, and the
    /// comma-inverted phrasing reversed so "Rice, white, cooked" also matches a
    /// query of "cooked white rice".
    static func searchName(_ name: String) -> String {
        let reordered = name.components(separatedBy: ", ").reversed().joined(separator: " ")
        let folded = reordered.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        let cleaned = folded.replacingOccurrences(
            of: #"[^a-z0-9 ]"#, with: " ", options: .regularExpression
        )
        return cleaned.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Deduplicates and caps a food's portion list.
    ///
    /// USDA ships dozens of portions for some foods, many near-identical. A
    /// picker with thirty options is worse than one with six.
    static func tidy(portions: [Portion]) -> [Portion] {
        var seen = Set<String>()
        var result: [Portion] = []

        for portion in portions {
            let label = portion.label
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            guard label.count >= 2, label.count <= 48 else { continue }

            // FNDDS ships advisory rows alongside real measures — "Guideline
            // amount per cup of hot cereal" is dietary advice about a different
            // food, not a portion of this one. Left in, they become the
            // default measure shown for staples like milk.
            let lowered = label.lowercased()
            guard !lowered.hasPrefix("guideline amount"),
                  !lowered.contains("quantity not specified")
            else { continue }

            let key = label.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(Portion(label: label, grams: portion.grams))

            if result.count == 8 { break }
        }
        return result
    }
}
