import Foundation

/// The foods offered before anyone types anything.
///
/// Curated rather than computed. The obvious approach — "show the highest-ranked
/// rows" — fails badly, because the ranking prefers short names and the shortest
/// names in USDA's database are things like "Dal", "Flan" and "Bear". A list
/// that opens with bear meat is not a useful starting point for logging
/// breakfast.
///
/// These are ordinary search terms, resolved against the built database at
/// compile time. If a term matches nothing it's simply skipped, so the list
/// can't break the build when USDA renames something.
enum Staples {

    /// Roughly ordered by how often a person logs them.
    static let terms: [String] = [
        // Drinks. Terms are specific enough to resolve to the plain version:
        // a bare "tea" matches "Tea, bubble" just as well as the ordinary kind.
        // And specific enough to be *hot*: "tea, black, brewed" resolved to
        // iced tea, which then outranked every hot tea for a bare "tea".
        "coffee, brewed", "tea, hot, leaf, black", "orange juice, raw",
        // Dairy and eggs
        "milk, whole", "milk, reduced fat", "yogurt, plain", "cheddar cheese",
        "egg, whole, cooked, scrambled",
        // Grains and bread
        "bread, whole wheat", "bread, white", "rice, white, cooked, no added fat",
        "rice, brown, cooked, no added fat", "oatmeal", "pasta, cooked",
        // Protein
        "chicken breast, baked", "beef, ground, cooked", "salmon, cooked", "tuna",
        "tofu", "beans, black", "lentils, cooked", "peanut butter",
        // Fruit
        "apple, raw", "banana, raw", "orange, raw", "strawberries, raw",
        "blueberries, raw", "grapes, raw", "avocado",
        // Vegetables
        "broccoli, cooked", "carrots, raw", "spinach, raw", "tomato, raw",
        "potato, baked", "sweet potato, cooked", "onions, raw",
        // Fats and extras
        "olive oil", "butter", "almonds", "chocolate, dark", "honey"
    ]

    /// Finds the best database row for each term.
    ///
    /// Matching is the same normalised comparison the app's search uses, kept
    /// deliberately simple: an exact normalised name first, then the
    /// highest-ranked row whose name contains every word of the term.
    /// - Returns: food id → its position in `terms`, so the app can present
    ///   them in the curated order rather than alphabetically or by name length.
    static func resolve(in foods: [FoodRow]) -> [String: Int] {
        var chosen: [String: Int] = [:]

        for (rank, term) in terms.enumerated() {
            let needle = Curation.searchName(term)
            let words = needle.split(separator: " ").map(String.init)
            guard !words.isEmpty else { continue }

            if let exact = foods.first(where: { $0.searchName == needle }) {
                if chosen[exact.id] == nil { chosen[exact.id] = rank }
                continue
            }

            let candidate = foods
                .filter { food in
                    let haystack = food.searchName.split(separator: " ").map(String.init)
                    return words.allSatisfy { word in haystack.contains { $0.hasPrefix(word) } }
                }
                // Shortest name among the matches is the plainest version.
                .min { lhs, rhs in
                    lhs.name.count == rhs.name.count
                        ? lhs.popularity > rhs.popularity
                        : lhs.name.count < rhs.name.count
                }

            if let candidate, chosen[candidate.id] == nil { chosen[candidate.id] = rank }
        }
        return chosen
    }
}
