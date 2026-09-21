import Foundation
import VesselCore

/// What the pipeline uses when the trained classifier isn't available.
///
/// Keyword rules, which are far weaker than the model but never fail to load.
/// The point is that a missing model degrades the app rather than breaking it.
enum RuleBasedClassifier {

    static func classify(_ normalized: TextNormalizer.Result) -> ParsedEntry.Intent {
        let text = normalized.text
        let tokens = Set(normalized.tokens)

        // Questions first: they contain food words too, and misreading one as a
        // log would silently add food the user never ate.
        let questionOpeners = ["how", "what", "when", "did", "am", "is", "show", "whats"]
        if let first = normalized.tokens.first, questionOpeners.contains(first) {
            return .query
        }

        if !tokens.isDisjoint(with: ["no", "actually", "meant", "correction", "change"]),
           tokens.contains("meant") || text.hasPrefix("no i") || text.hasPrefix("actually") {
            return .correction
        }

        if SymptomVocabulary.kind(for: text) != nil { return .logSymptom }

        let drinkWords: Set<String> = ["water", "coffee", "tea", "juice", "soda", "milk",
                                       "smoothie", "latte", "lemonade", "espresso"]
        if !tokens.isDisjoint(with: drinkWords) {
            // "coffee and a biscuit" is a food log that mentions a drink; a bare
            // "a glass of water" is a water log.
            let vessels: Set<String> = ["glass", "glasses", "bottle", "cup", "mug", "can", "sip"]
            if tokens.contains("water") || !tokens.isDisjoint(with: vessels) { return .logWater }
        }

        // Journal entries read like sentences about a day, not about food.
        let journalWords: Set<String> = ["felt", "feeling", "day", "slept", "mood",
                                         "stressed", "anxious", "energy", "today"]
        if !tokens.isDisjoint(with: journalWords), tokens.count > 3 { return .journalEntry }

        return .logFood
    }
}

/// A rule-based stand-in for the trained tagger.
///
/// Recognises quantities, units and the obvious closed-class words, and calls
/// everything else food. Crude, but it keeps the common case — "2 eggs" —
/// working with no model at all.
enum RuleBasedTagger {

    static func tag(tokens: [String]) -> [String] {
        var labels: [String] = []
        labels.reserveCapacity(tokens.count)

        let preps: Set<String> = [
            "grilled", "fried", "baked", "boiled", "steamed", "roasted", "raw",
            "scrambled", "poached", "toasted", "cooked", "fresh", "frozen"
        ]
        let negations: Set<String> = ["no", "without", "not", "hold"]
        let connectors: Set<String> = ["and", "with", "of", "plus", "then", "also", "the", "a", "an"]
        let drinks: Set<String> = ["water", "coffee", "tea", "juice", "soda", "milk",
                                   "smoothie", "latte", "espresso", "lemonade"]

        for token in tokens {
            if NumberParser.parseSingle(token) != nil {
                labels.append("QTY")
            } else if UnitVocabulary.unit(for: token) != nil {
                labels.append("UNIT")
            } else if negations.contains(token) {
                labels.append("NEG")
            } else if preps.contains(token) {
                labels.append("PREP")
            } else if drinks.contains(token) {
                labels.append("DRINK")
            } else if SymptomVocabulary.kind(for: token) != nil {
                labels.append("SYMPTOM")
            } else if connectors.contains(token) {
                labels.append("NONE")
            } else {
                labels.append("FOOD")
            }
        }
        return labels
    }
}
