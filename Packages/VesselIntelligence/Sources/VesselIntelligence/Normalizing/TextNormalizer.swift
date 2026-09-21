import Foundation
import VesselCore

/// Stage 1 of the pipeline: turns what someone said into something the rest of
/// the parser can reason about.
///
/// Everything here is hand-written and deterministic. That's deliberate — this
/// stage handles the parts of language that have exactly one right answer
/// ("two and a half" is 2.5, always), so learning them from data would be
/// strictly worse: slower, bigger, and capable of being wrong. The models later
/// in the pipeline handle the genuinely ambiguous parts.
public struct TextNormalizer: Sendable {

    private let timeParser: TimeExpressionParser
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
        self.timeParser = TimeExpressionParser(calendar: calendar)
    }

    /// The result of normalising one utterance.
    public struct Result: Sendable, Equatable {
        /// Cleaned, lowercased text with the time expression removed.
        public let text: String
        /// Tokens of `text`.
        public let tokens: [String]
        /// Separate foods found in the utterance.
        public let segments: [String]
        /// When the user said this happened, if they said.
        public let occurredAt: Date?
        /// The meal they named, if they named one.
        public let slot: MealSlot?
        /// True when the time came from a vague phrase rather than a clock.
        public let timeIsApproximate: Bool
        /// The original input, kept verbatim for display and for improving the
        /// parser against real usage later.
        public let original: String
    }

    // MARK: - Filler

    /// Words that carry no meaning in a food log and only confuse matching.
    ///
    /// Note what is *not* here: "with", "and", "no", "without". Those change
    /// meaning — "toast with butter" is not "toast butter", and dropping a
    /// negation would invert it.
    private static let fillers: Set<String> = [
        "um", "uh", "erm", "ah", "oh", "like", "just", "basically",
        "actually", "really", "kinda", "sorta", "maybe", "probably",
        "please", "okay", "ok", "so", "well", "right", "yeah", "yep"
    ]

    /// Leading phrases people open with, stripped whole.
    ///
    /// Matched as phrases rather than word-by-word because the individual words
    /// matter elsewhere: "had" appears in "I had", which is noise, but "half"
    /// must survive.
    /// Only the verb phrase is stripped, never a following article: "a" in
    /// "I ate a banana" is the quantity, and dropping it loses the implied one.
    private static let leadIns: [[String]] = [
        ["i", "just", "had"], ["i", "just", "ate"], ["i", "just", "drank"],
        ["i", "have", "had"],
        ["i", "had"], ["i", "ate"], ["i", "drank"], ["i", "am", "having"],
        ["im", "having"], ["i", "m", "having"], ["having"],
        ["log"], ["add"], ["record"], ["track"],
        ["can", "you", "log"], ["please", "log"],
        ["for", "me"]
    ]

    /// Trailing phrases that add nothing.
    private static let tailOffs: [[String]] = [
        ["please"], ["thanks"], ["thank", "you"], ["to", "my", "log"],
        ["in", "vessel"], ["to", "vessel"]
    ]

    // MARK: - Normalise

    public func normalize(_ input: String, now: Date = Date()) -> Result {
        let original = input.trimmingCharacters(in: .whitespacesAndNewlines)

        var tokens = Self.tokenize(original)
        tokens = Self.stripPhrases(Self.leadIns, from: tokens, atStart: true)
        tokens = Self.stripPhrases(Self.tailOffs, from: tokens, atStart: false)

        // Time is extracted before fillers are dropped, because some time
        // phrases contain words that look like filler ("this morning").
        let time = timeParser.parse(tokens: tokens, now: now)
        if let time {
            tokens.removeSubrange(time.range)
        }

        tokens = tokens.filter { !Self.fillers.contains($0) }
        tokens = Self.canonicaliseNumbers(tokens)

        let text = tokens.joined(separator: " ")

        return Result(
            text: text,
            tokens: tokens,
            segments: Segmenter.split(tokens: tokens),
            occurredAt: time?.date,
            slot: time?.slot,
            timeIsApproximate: time?.isApproximate ?? false,
            original: original
        )
    }

    // MARK: - Pieces

    /// Splits into lowercase word tokens, keeping the characters quantities need.
    ///
    /// Slashes, colons, decimal points and vulgar fractions survive because
    /// "1/2", "8:30", "1.5" and "½" are single meaningful tokens. Apostrophes
    /// are dropped so "I'm" becomes "im" rather than two tokens.
    static func tokenize(_ text: String) -> [String] {
        let lowered = text.lowercased()
            .folding(options: .diacriticInsensitive, locale: nil)
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "")

        var tokens: [String] = []
        var current = ""

        for character in lowered {
            if character.isLetter || character.isNumber
                || character == "/" || character == ":" || character == "."
                || character == "-" || NumberParser.vulgarFractions[character] != nil {
                current.append(character)
            } else {
                if !current.isEmpty { tokens.append(current); current = "" }
            }
        }
        if !current.isEmpty { tokens.append(current) }

        // A trailing period is sentence punctuation, not a decimal point.
        return tokens.map { token in
            token.hasSuffix(".") ? String(token.dropLast()) : token
        }.filter { !$0.isEmpty }
    }

    /// Removes the first matching phrase from the start or end.
    static func stripPhrases(_ phrases: [[String]], from tokens: [String], atStart: Bool) -> [String] {
        // Longest first, so "i just had" wins over "i had".
        for phrase in phrases.sorted(by: { $0.count > $1.count }) {
            guard tokens.count > phrase.count else { continue }
            if atStart, Array(tokens.prefix(phrase.count)) == phrase {
                return Array(tokens.dropFirst(phrase.count))
            }
            if !atStart, Array(tokens.suffix(phrase.count)) == phrase {
                return Array(tokens.dropLast(phrase.count))
            }
        }
        return tokens
    }

    /// Rewrites spelled-out quantities as digits.
    ///
    /// Done before tagging so the sequence model sees one consistent shape for
    /// a number instead of having to learn that "two", "2" and "a couple of"
    /// are the same thing.
    static func canonicaliseNumbers(_ tokens: [String]) -> [String] {
        var output: [String] = []
        var index = 0

        while index < tokens.count {
            let remaining = Array(tokens[index...])
            // Articles are only a quantity when a unit or food follows, and
            // rewriting every "a" to "1" makes the text read like a robot
            // wrote it. Leave them; the tagger handles the implied one.
            if ["a", "an", "the", "some"].contains(tokens[index]) {
                output.append(tokens[index])
                index += 1
                continue
            }

            if let (quantity, consumed) = NumberParser.parse(tokens: remaining), consumed > 0 {
                output.append(Self.format(quantity.value))
                index += consumed
                continue
            }

            output.append(tokens[index])
            index += 1
        }
        return output
    }

    static func format(_ value: Double) -> String {
        value == value.rounded()
            ? String(Int(value))
            : String(format: "%g", (value * 100).rounded() / 100)
    }
}
