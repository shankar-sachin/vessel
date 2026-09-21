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
            entry.foods = assembleFoods(from: tagged, segments: normalized.segments, protected: protected)
        case .logWater:
            entry.drinks = assembleDrinks(from: tagged)
            // "a coffee and a biscuit" is both a drink and a food.
            entry.foods = assembleFoods(from: tagged, segments: normalized.segments, protected: protected)
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
        protected: Set<Int>
    ) -> [ParsedFood] {
        var foods: [ParsedFood] = []
        var current: ParsedFood?
        var pendingQuantity: NumberParser.Quantity?
        var pendingUnit: MeasurementUnit?
        var pendingPrep: [String] = []
        var pendingBrand: String?
        var negateNext = false

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

    private func assembleDrinks(from tagged: [Tagged]) -> [ParsedDrink] {
        var drinks: [ParsedDrink] = []
        var quantity: Double?
        var unit: MeasurementUnit?
        var name: [String] = []

        func flush() {
            guard !name.isEmpty else { return }
            let joined = name.joined(separator: " ")
            drinks.append(ParsedDrink(
                name: joined,
                quantity: quantity,
                unit: unit,
                millilitres: DrinkVolume.millilitres(quantity: quantity, unit: unit, name: joined)
            ))
            name = []
            quantity = nil
            unit = nil
        }

        for item in tagged {
            switch item.label {
            case "QTY":
                flush()
                quantity = NumberParser.parseSingle(item.token)?.value
                    ?? NumberParser.parse(tokens: [item.token])?.quantity.value
            case "UNIT":
                unit = UnitVocabulary.unit(for: item.token)
            case "DRINK":
                name.append(item.token)
            default:
                break
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
