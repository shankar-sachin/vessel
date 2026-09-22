import Foundation
import VesselCore

/// Turns what someone said into a structured entry.
///
/// Six stages, each able to degrade into the next:
///
/// 1. **Normalize** — deterministic cleanup, numbers, time, segmentation
/// 2. **Classify intent** — trained model, with a keyword fallback
/// 3. **Tag entities** — trained sequence model, with a rule-based fallback
/// 4. **Assemble** — group labelled tokens into foods, drinks, symptoms
/// 5. **Score** — decide whether to fill in or ask
/// 6. *(callers)* resolve foods against the database
///
/// The fallbacks matter more than they look. A model that fails to load, or a
/// sentence the tagger can't align, must still produce a usable entry — the
/// alternative is an app that silently stops working for reasons the user
/// can't see or fix.
public struct ParsePipeline: Sendable {

    /// Above this, the parse is filled in directly. Below, the user confirms.
    public static let confidentThreshold = 0.72

    private let normalizer: TextNormalizer
    private let models: ParserModels
    private let calendar: Calendar

    public init(
        models: ParserModels = .shared,
        calendar: Calendar = .current
    ) {
        self.models = models
        self.calendar = calendar
        self.normalizer = TextNormalizer(calendar: calendar)
    }

    // MARK: - Parse

    public func parse(_ input: String, now: Date = Date()) -> ParsedEntry {
        let normalized = normalizer.normalize(input, now: now)
        guard !normalized.tokens.isEmpty else {
            return ParsedEntry(original: input, confidence: 0,
                               uncertainties: ["Nothing to read in that."])
        }

        let (intent, intentConfidence) = classify(normalized)
        var entry = ParsedEntry(
            intent: intent,
            occurredAt: normalized.occurredAt,
            slot: normalized.slot,
            original: normalized.original
        )

        let labels = tagLabels(for: normalized.tokens)
        let tagged = zip(normalized.tokens, labels).map { (token: $0, label: $1) }
        // Positions inside a compound dish name, which must not be split on.
        let protected = Segmenter.protectedIndices(tokens: normalized.tokens)

        switch intent {
        case .logFood, .correction:
            entry.foods = assembleFoods(from: tagged, segments: normalized.segments, protected: protected,
                                        boundaries: normalized.boundaries)
            // "toast and a coffee" is a meal that also names a drink; the sheet
            // saves both, but only if the drink was assembled at all.
            entry.drinks = assembleDrinks(from: tagged, boundaries: normalized.boundaries)
        case .logWater:
            entry.drinks = assembleDrinks(from: tagged, boundaries: normalized.boundaries)
            // "a coffee and a biscuit" is both a drink and a food. Only foods
            // the tagger actually found, though: the segment fallback turned
            // "bottle of water after my run" into a *food* spanning the whole
            // sentence, which the resolver dutifully matched to tonic water.
            entry.foods = assembleFoods(from: tagged, segments: [], protected: protected,
                                        boundaries: normalized.boundaries)
        case .logSymptom:
            entry.symptom = assembleSymptom(from: tagged)
        case .journalEntry, .query, .unknown:
            break
        }

        // The meal named in the text wins over one inferred from the clock.
        if entry.slot == nil, let occurredAt = entry.occurredAt {
            entry.slot = MealSlot.inferred(from: occurredAt, calendar: calendar)
        }

        let scored = score(entry: entry, intentConfidence: intentConfidence, usedModel: models.hasTaggerModel)
        entry.confidence = scored.confidence
        entry.uncertainties = scored.reasons
        return entry
    }

    // MARK: - Stage 2: intent

    private func classify(_ normalized: TextNormalizer.Result) -> (ParsedEntry.Intent, Double) {
        if let prediction = models.predictIntent(normalized.text),
           let intent = ParsedEntry.Intent(rawValue: prediction.label) {
            return (intent, prediction.confidence)
        }
        return (RuleBasedClassifier.classify(normalized), 0.5)
    }

    // MARK: - Stage 3: tagging

    private func tagLabels(for tokens: [String]) -> [String] {
        models.tagTokens(tokens) ?? RuleBasedTagger.tag(tokens: tokens)
    }

    // MARK: - Stage 4: assembly

    private typealias Tagged = (token: String, label: String)

    /// Groups labelled tokens into foods.
    ///
    /// A new food starts at a quantity or at a food word that follows a
    /// non-food, which handles "2 eggs and toast" without needing the segmenter
    /// to have got the split perfectly right.
    private func assembleFoods(
        from tagged: [Tagged],
        segments: [String],
        protected: Set<Int>,
        boundaries: Set<Int>
    ) -> [ParsedFood] {
        var foods: [ParsedFood] = []
        var current: ParsedFood?
        var pendingQuantity: NumberParser.Quantity?
        var pendingUnit: MeasurementUnit?
        var pendingPrep: [String] = []
        var pendingBrand: String?
        var negateNext = false
        // Set when a word that isn't part of a food name follows the current
        // food, so the next food word starts a new one.
        var brokeSinceLastFood = false

        func flush() {
            if var food = current, !food.phrase.isEmpty {
                food.preparation = pendingPrep
                food.brand = pendingBrand
                foods.append(food)
            }
            current = nil
            pendingQuantity = nil
            pendingUnit = nil
            pendingPrep = []
            pendingBrand = nil
        }

        for (index, item) in tagged.enumerated() {
            switch item.label {
            case "QTY":
                let parsed = NumberParser.parseSingle(item.token)
                    ?? NumberParser.parse(tokens: [item.token])?.quantity

                if current != nil {
                    // A quantity after a food begins the next one.
                    flush()
                    pendingQuantity = parsed
                } else if let existing = pendingQuantity,
                          !existing.wasImplied,
                          parsed?.wasImplied == true {
                    // "half an avocado": the article is part of the phrase, not
                    // a second quantity. Letting it through replaces an explicit
                    // 0.5 with an implied 1 — a silent doubling of what was
                    // logged, which is exactly the error class that matters most.
                    break
                } else {
                    pendingQuantity = parsed
                }

            case "UNIT":
                pendingUnit = UnitVocabulary.unit(for: item.token)

            case "PREP":
                pendingPrep.append(item.token)

            case "BRAND":
                pendingBrand = item.token

            case "NEG":
                negateNext = true

            case "FOOD":
                if current != nil, brokeSinceLastFood || boundaries.contains(index) {
                    // "baguette with butter" is two foods. The tagger labels
                    // "with" NONE; appending straight past it made one phrase
                    // that the resolver matched to butter, losing the baguette.
                    flush()
                }
                brokeSinceLastFood = false
                if current == nil {
                    current = ParsedFood(
                        phrase: item.token,
                        quantity: pendingQuantity?.value,
                        quantityIsApproximate: pendingQuantity?.isApproximate ?? false,
                        unit: pendingUnit,
                        isNegated: negateNext
                    )
                    negateNext = false
                } else {
                    current?.phrase += " " + item.token
                }

            default:
                // A connector ends the current food — unless it's the "and"
                // inside "macaroni and cheese".
                if current != nil,
                   !protected.contains(index),
                   ["and", "plus", "then", "also"].contains(item.token) {
                    flush()
                } else if current != nil, !protected.contains(index) {
                    brokeSinceLastFood = true
                }
            }
        }
        flush()

        // Nothing was tagged FOOD — fall back to the normalizer's segments so
        // an unrecognised food still reaches the resolver.
        if foods.isEmpty, !segments.isEmpty {
            return segments.map { ParsedFood(phrase: $0) }
        }
        return foods
    }

    private static let drinkEdgeWords: Set<String> = ["with", "my", "of", "a", "an", "the", "some", "and"]

    private func assembleDrinks(from tagged: [Tagged], boundaries: Set<Int>) -> [ParsedDrink] {
        var drinks: [ParsedDrink] = []
        var quantity: Double?
        var unit: MeasurementUnit?
        var name: [String] = []
        // The container word, kept apart from the name: it says how much, and
        // `DrinkVolume` needs it to tell a bottle from a glass.
        var vessel: String?

        func flush() {
            // The tagger sometimes lets the words around a drink into it
            // ("a beer with", "with my tea"). None of them can begin or end a
            // drink's name.
            while let first = name.first, Self.drinkEdgeWords.contains(first) { name.removeFirst() }
            while let last = name.last, Self.drinkEdgeWords.contains(last) { name.removeLast() }
            // Nothing named yet: keep any quantity and vessel for the drink that
            // follows, as in "bottle of water".
            guard !name.isEmpty else { return }
            let joined = name.joined(separator: " ")
            drinks.append(ParsedDrink(
                name: joined,
                quantity: quantity,
                unit: unit,
                millilitres: DrinkVolume.millilitres(
                    quantity: quantity, unit: unit,
                    name: [vessel, joined].compactMap { $0 }.joined(separator: " ")
                )
            ))
            name = []
            quantity = nil
            unit = nil
            vessel = nil
        }

        for (index, item) in tagged.enumerated() {
            if boundaries.contains(index) { flush() }
            switch item.label {
            case "QTY":
                flush()
                quantity = NumberParser.parseSingle(item.token)?.value
                    ?? NumberParser.parse(tokens: [item.token])?.quantity.value
            case "UNIT":
                unit = UnitVocabulary.unit(for: item.token)
                vessel = item.token
            case "DRINK":
                if name.isEmpty, let asUnit = UnitVocabulary.unit(for: item.token) {
                    vessel = item.token
                    // "glass of water" tagged DRINK throughout: the glass is how
                    // much, not what. Leaving it in the name also lost the 250 ml.
                    unit = asUnit
                } else {
                    name.append(item.token)
                }
            default:
                // "a beer with dinner" — whatever follows the drink is not it.
                flush()
            }
        }
        flush()
        return drinks
    }

    private func assembleSymptom(from tagged: [Tagged]) -> ParsedSymptom? {
        let symptomWords = tagged.filter { $0.label == "SYMPTOM" }.map(\.token)
        guard !symptomWords.isEmpty,
              let kind = SymptomVocabulary.kind(for: symptomWords.joined(separator: " "))
        else { return nil }

        let severityWords = tagged.filter { $0.label == "SEVERITY" }.map(\.token)
        let food = tagged.filter { $0.label == "FOOD" }.map(\.token)

        return ParsedSymptom(
            kind: kind,
            severity: SymptomVocabulary.severity(for: severityWords),
            attributedTo: food.isEmpty ? nil : food.joined(separator: " ")
        )
    }

    // MARK: - Stage 5: scoring

    /// Decides how much to trust the parse, and says why when it doesn't.
    ///
    /// Confidence is deliberately pessimistic. Filling in the wrong food
    /// silently is far worse than asking — the user may not notice for weeks,
    /// and by then the Date Log's correlations are built on it.
    private func score(
        entry: ParsedEntry,
        intentConfidence: Double,
        usedModel: Bool
    ) -> (confidence: Double, reasons: [String]) {
        var reasons: [String] = []
        var confidence = intentConfidence

        if !usedModel {
            confidence *= 0.75
            reasons.append("Read using simple rules rather than the full parser.")
        }

        if entry.isEmpty, entry.intent != .journalEntry, entry.intent != .query {
            confidence *= 0.4
            reasons.append("Couldn't pick out what you had.")
        }

        // A food with no quantity isn't wrong, just incomplete — we'll offer a
        // default portion, which the user should see rather than inherit.
        let missingQuantity = entry.foods.filter { $0.quantity == nil }
        if !missingQuantity.isEmpty {
            confidence *= 0.9
            reasons.append(missingQuantity.count == 1
                ? "No amount given for \(missingQuantity[0].phrase)."
                : "No amounts given for \(missingQuantity.count) items.")
        }

        let vague = entry.foods.filter { $0.quantityIsApproximate }
        if !vague.isEmpty {
            confidence *= 0.95
            reasons.append("Some amounts were approximate.")
        }

        if entry.foods.count > 3 {
            // Long lists are where segmentation most often goes wrong.
            confidence *= 0.9
            reasons.append("That's a long list — worth checking the split.")
        }

        return (max(0, min(1, confidence)), reasons)
    }
}
