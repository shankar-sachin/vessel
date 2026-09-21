import Foundation

/// Turns the many ways people write a quantity into a number.
///
/// Speech and casual typing produce quantities in forms no `Double` initialiser
/// accepts: "two and a half", "a couple of", "½", "1 1/2", "2-3". Every one of
/// those has to become a number before anything downstream can reason about a
/// portion, and getting it wrong is worse than failing — "half a cup" silently
/// read as 1 cup doubles someone's logged intake.
public enum NumberParser {

    /// A parsed quantity, with how sure we are of it.
    public struct Quantity: Sendable, Equatable {
        public let value: Double
        /// Half-width of the range the speaker implied. "2-3 eggs" gives
        /// value 2.5, uncertainty 0.5. Zero when an exact number was stated.
        public let uncertainty: Double
        /// True when the number was implied rather than said, as in "a coffee".
        public let wasImplied: Bool

        public init(value: Double, uncertainty: Double = 0, wasImplied: Bool = false) {
            self.value = value
            self.uncertainty = uncertainty
            self.wasImplied = wasImplied
        }

        public var isApproximate: Bool { uncertainty > 0 || wasImplied }
    }

    // MARK: - Word tables

    static let units: [String: Double] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
        "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14,
        "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18,
        "nineteen": 19
    ]

    static let tens: [String: Double] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
        "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90
    ]

    /// Words that name a fraction outright.
    static let fractionWords: [String: Double] = [
        "half": 0.5, "halves": 0.5,
        "third": 1.0 / 3, "thirds": 1.0 / 3,
        "quarter": 0.25, "quarters": 0.25,
        "eighth": 0.125, "eighths": 0.125
    ]

    /// Vague amounts, mapped to the count they usually mean.
    ///
    /// These are guesses and are marked as such, so the UI can show them as
    /// approximate rather than presenting "a couple of biscuits" as exactly two.
    static let vagueCounts: [String: Double] = [
        "a": 1, "an": 1, "the": 1, "some": 1,
        "couple": 2, "pair": 2, "few": 3, "several": 3,
        "dozen": 12, "handful": 1, "bunch": 1
    ]

    /// Unicode fraction characters.
    static let vulgarFractions: [Character: Double] = [
        "½": 0.5, "⅓": 1.0 / 3, "⅔": 2.0 / 3, "¼": 0.25, "¾": 0.75,
        "⅕": 0.2, "⅖": 0.4, "⅗": 0.6, "⅘": 0.8,
        "⅙": 1.0 / 6, "⅚": 5.0 / 6, "⅛": 0.125, "⅜": 0.375,
        "⅝": 0.625, "⅞": 0.875
    ]

    // MARK: - Parsing

    /// Reads a quantity from the start of a token sequence.
    ///
    /// - Returns: the quantity and how many tokens it consumed, or nil if the
    ///   sequence doesn't begin with one.
    public static func parse(tokens: [String]) -> (quantity: Quantity, consumed: Int)? {
        guard !tokens.isEmpty else { return nil }

        // "2-3", "2 to 3": a stated range becomes its midpoint, carrying the
        // spread so the UI can admit it's approximate.
        if let range = parseRange(tokens: tokens) { return range }

        // "two and a half", "1 1/2"
        if let compound = parseCompound(tokens: tokens) { return compound }

        if let simple = parseSingle(tokens[0]) {
            return (simple, 1)
        }

        // "a couple of eggs" — the "of" is noise once the count is known.
        if let vague = vagueCounts[tokens[0]] {
            let consumed = (tokens.count > 1 && tokens[1] == "of") ? 2 : 1
            // "a"/"an"/"the" are articles rather than counts; treat the implied
            // one as a guess so a portion picker can offer something better.
            let isArticle = ["a", "an", "the", "some"].contains(tokens[0])
            return (Quantity(value: vague, uncertainty: isArticle ? 0 : 0.5, wasImplied: true), consumed)
        }

        return nil
    }

    /// A single token: "2", "2.5", "1/2", "½", "two", "half".
    static func parseSingle(_ token: String) -> Quantity? {
        if let value = Double(token) { return Quantity(value: value) }

        // "1/2"
        if token.contains("/") {
            let parts = token.split(separator: "/")
            if parts.count == 2,
               let numerator = Double(parts[0]), let denominator = Double(parts[1]),
               denominator != 0 {
                return Quantity(value: numerator / denominator)
            }
        }

        // A lone vulgar fraction, or a digit followed by one ("1½").
        if token.count == 1, let first = token.first, let value = vulgarFractions[first] {
            return Quantity(value: value)
        }
        if let last = token.last, let fraction = vulgarFractions[last],
           let whole = Double(token.dropLast()) {
            return Quantity(value: whole + fraction)
        }

        if let value = units[token] { return Quantity(value: value) }
        if let value = tens[token] { return Quantity(value: value) }
        if let value = fractionWords[token] {
            // "half a bagel" is exact about the half, not a guess.
            return Quantity(value: value)
        }
        return nil
    }

    /// "two and a half", "1 1/2", "twenty five".
    static func parseCompound(tokens: [String]) -> (Quantity, Int)? {
        guard tokens.count >= 2, let first = parseSingle(tokens[0]) else { return nil }

        // "1 1/2" or "1 ½"
        if let second = parseSingle(tokens[1]), second.value < 1, first.value >= 1 {
            return (Quantity(value: first.value + second.value), 2)
        }

        // "twenty five"
        if tens[tokens[0]] != nil, let second = tokens.count > 1 ? units[tokens[1]] : nil {
            return (Quantity(value: first.value + second), 2)
        }

        // "two and a half"
        if tokens.count >= 4, tokens[1] == "and",
           ["a", "an"].contains(tokens[2]),
           let fraction = fractionWords[tokens[3]] {
            return (Quantity(value: first.value + fraction), 4)
        }
        // "two and a half" written as "two and half"
        if tokens.count >= 3, tokens[1] == "and", let fraction = fractionWords[tokens[2]] {
            return (Quantity(value: first.value + fraction), 3)
        }

        return nil
    }

    /// "2-3", "2 to 3", "two or three".
    static func parseRange(tokens: [String]) -> (Quantity, Int)? {
        // Hyphenated, already one token.
        if let hyphenIndex = tokens[0].firstIndex(of: "-"), tokens[0].count > 2 {
            let lower = String(tokens[0][tokens[0].startIndex..<hyphenIndex])
            let upper = String(tokens[0][tokens[0].index(after: hyphenIndex)...])
            if let low = parseSingle(lower), let high = parseSingle(upper), high.value > low.value {
                return (midpoint(low.value, high.value), 1)
            }
        }

        // Three tokens: "2 to 3", "two or three".
        guard tokens.count >= 3, ["to", "or"].contains(tokens[1]),
              let low = parseSingle(tokens[0]), let high = parseSingle(tokens[2]),
              high.value > low.value
        else { return nil }

        return (midpoint(low.value, high.value), 3)
    }

    private static func midpoint(_ low: Double, _ high: Double) -> Quantity {
        Quantity(value: (low + high) / 2, uncertainty: (high - low) / 2)
    }
}
