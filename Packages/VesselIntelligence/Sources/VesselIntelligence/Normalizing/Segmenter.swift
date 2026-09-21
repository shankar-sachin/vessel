import Foundation

/// Splits one utterance into the separate foods it mentions.
///
/// "eggs and toast with a coffee" is three things, and resolving it as one
/// string finds nothing. The split has to be careful though, because the same
/// words join foods in one place and modify them in another: "toast **with**
/// butter" is one food, "toast **with** a coffee" is two.
public enum Segmenter {

    /// Words that usually introduce a new food.
    private static let separators: Set<String> = ["and", "plus", "then", "also"]

    /// "with" only separates when what follows looks like a drink or a clearly
    /// standalone item. Otherwise it's describing the food before it.
    private static let standaloneAfterWith: Set<String> = [
        "coffee", "tea", "water", "juice", "milk", "soda", "beer", "wine",
        "smoothie", "shake", "espresso", "latte", "cappuccino", "cola"
    ]

    /// Words that look like separators but are part of a food's name.
    ///
    /// Splitting "macaroni and cheese" into two foods gets both wrong.
    private static let compoundNames: [[String]] = [
        ["macaroni", "and", "cheese"],
        ["mac", "and", "cheese"],
        ["peanut", "butter", "and", "jelly"],
        ["peanut", "butter", "and", "jam"],
        ["bacon", "and", "eggs"],
        ["fish", "and", "chips"],
        ["rice", "and", "beans"],
        ["beans", "and", "rice"],
        ["chicken", "and", "rice"],
        ["bread", "and", "butter"],
        ["cream", "and", "sugar"],
        ["salt", "and", "pepper"],
        ["oil", "and", "vinegar"],
        ["sweet", "and", "sour"],
        ["half", "and", "half"]
    ]

    /// Token positions that sit inside a compound dish name and must never be
    /// treated as a separator.
    ///
    /// Public because the parse pipeline splits foods on "and" as well, and the
    /// two have to agree: the segmenter kept "macaroni and cheese" whole while
    /// the pipeline cut it in half, so the same sentence produced one food or
    /// two depending on which code path you asked.
    public static func protectedIndices(tokens: [String]) -> Set<Int> {
        var protected = Set<Int>()
        for name in compoundNames {
            guard tokens.count >= name.count else { continue }
            for start in 0...(tokens.count - name.count)
            where Array(tokens[start..<(start + name.count)]) == name {
                for offset in 0..<name.count { protected.insert(start + offset) }
            }
        }
        return protected
    }

    /// Splits tokens into per-food segments.
    public static func split(tokens: [String]) -> [String] {
        guard !tokens.isEmpty else { return [] }

        let protected = protectedIndices(tokens: tokens)

        var segments: [String] = []
        var current: [String] = []

        for index in tokens.indices {
            let token = tokens[index]

            let isSeparator: Bool
            if protected.contains(index) {
                isSeparator = false
            } else if separators.contains(token) {
                isSeparator = true
            } else if token == "with" {
                let next = index + 1 < tokens.count ? tokens[index + 1] : ""
                let afterNext = index + 2 < tokens.count ? tokens[index + 2] : ""
                // "with a coffee" — look past the article.
                isSeparator = standaloneAfterWith.contains(next)
                    || (["a", "an", "some"].contains(next) && standaloneAfterWith.contains(afterNext))
            } else {
                isSeparator = false
            }

            if isSeparator {
                if !current.isEmpty { segments.append(current.joined(separator: " ")) }
                current = []
            } else {
                current.append(token)
            }
        }

        if !current.isEmpty { segments.append(current.joined(separator: " ")) }

        // A separator with nothing meaningful after it shouldn't produce an
        // empty food.
        return segments.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}
