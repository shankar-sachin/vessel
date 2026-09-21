import Foundation

/// One labelled training example.
///
/// Carries both the sentence and its per-token labels, which is the whole point
/// of generating rather than collecting: the generator knows what it produced,
/// so the labels come for free. Hand-labelling 50,000 utterances is a project;
/// writing the grammar that emits them is an afternoon.
struct Example {
    var tokens: [String]
    var labels: [Grammar.Label]
    var intent: Grammar.Intent

    var text: String { tokens.joined(separator: " ") }

    /// Appends a phrase, giving every one of its tokens the same label.
    mutating func append(_ phrase: String, _ label: Grammar.Label) {
        let parts = phrase.split(separator: " ").map(String.init)
        guard !parts.isEmpty else { return }
        tokens.append(contentsOf: parts)
        labels.append(contentsOf: Array(repeating: label, count: parts.count))
    }
}

/// Builds the corpus.
struct Generator {

    let foods: [FoodName]
    var rng: SeededGenerator

    /// A food name split into the form a sentence would use it in.
    struct FoodName {
        /// "chicken breast, grilled" → "grilled chicken breast"
        let spoken: String
        /// Whether the name already contains a preparation word, so the
        /// generator doesn't produce "grilled grilled chicken".
        let hasPrep: Bool
    }

    init(foods: [FoodName], seed: UInt64) {
        self.foods = foods
        self.rng = SeededGenerator(seed: seed)
    }

    // MARK: - Entry point

    mutating func generate(count: Int) -> [Example] {
        // Weighted by how often each intent actually occurs. Food logging
        // dominates real usage, and training on a uniform split would make the
        // classifier far too eager to see a symptom or a query.
        let weights: [(Grammar.Intent, Int)] = [
            (.logFood, 52), (.logWater, 16), (.logSymptom, 14),
            (.journalEntry, 8), (.query, 6), (.correction, 4)
        ]
        let total = weights.reduce(0) { $0 + $1.1 }

        var examples: [Example] = []
        examples.reserveCapacity(count)

        for _ in 0..<count {
            let roll = rng.next(upperBound: UInt64(total))
            var cursor = 0
            var chosen = Grammar.Intent.logFood
            for (intent, weight) in weights {
                cursor += weight
                if roll < UInt64(cursor) { chosen = intent; break }
            }

            var example = build(chosen)
            applyNoise(&example)
            guard !example.tokens.isEmpty else { continue }
            examples.append(example)
        }
        return examples
    }

    private mutating func build(_ intent: Grammar.Intent) -> Example {
        switch intent {
        case .logFood:      return buildFood()
        case .logWater:     return buildWater()
        case .logSymptom:   return buildSymptom()
        case .journalEntry: return buildJournal()
        case .query:        return buildQuery()
        case .correction:   return buildCorrection()
        }
    }

    // MARK: - Food

    private mutating func buildFood() -> Example {
        var example = Example(tokens: [], labels: [], intent: .logFood)

        // A bare food with no lead-in and no quantity — "eggs and toast",
        // "porridge", "chicken salad".
        //
        // Given its own branch because the generator otherwise almost never
        // puts a FOOD token first: lead-ins and quantities crowd the opening
        // position, and the tagger learned that a sentence-initial word is
        // filler. It then dropped the first food of "eggs and toast" entirely,
        // which is about as common a phrasing as exists.
        if roll(16) {
            let itemCount = roll(60) ? 1 : 2
            for index in 0..<itemCount {
                if index > 0 { example.append("and", .none) }
                if roll(25), !foods.isEmpty { example.append(pick(Grammar.preps), .prep) }
                example.append(pick(foods).spoken, .food)
            }
            if roll(20) { example.append(pick(Grammar.timePhrases), .time) }
            if roll(20) { example.append(pick(Grammar.mealPhrases), .meal) }
            return example
        }

        example.append(pick(Grammar.leadIns), .none)

        let itemCount = roll(70) ? 1 : (roll(75) ? 2 : 3)
        for index in 0..<itemCount {
            if index > 0 { example.append(roll(80) ? "and" : "plus", .none) }
            appendFoodItem(to: &example)
        }

        // Time and meal are each mentioned in a minority of real utterances.
        if roll(22) { example.append(pick(Grammar.timePhrases), .time) }
        if roll(18) { example.append(pick(Grammar.mealPhrases), .meal) }

        // A drink named alongside the food, which must stay a *food* log.
        if roll(12) { example.append(pick(Grammar.accompanyingDrinks), .drink) }
        // An offhand remark about the food.
        if roll(14) { example.append(pick(Grammar.foodAsides), .none) }

        example.append(pick(Grammar.tailOffs), .none)
        return example
    }

    private mutating func appendFoodItem(to example: inout Example) {
        let food = pick(foods)

        // Quantity, in one of the shapes people use.
        if roll(62) {
            example.append(pick(Grammar.quantityForms), .quantity)
            if roll(45) {
                example.append(pick(Grammar.allUnits), .unit)
                if roll(70) { example.append("of", .none) }
            }
        } else if roll(50) {
            example.append(pick(Grammar.articles), .quantity)
        }

        if roll(10) { example.append(pick(Grammar.brands), .brand) }
        if roll(18), !food.hasPrep { example.append(pick(Grammar.preps), .prep) }

        example.append(food.spoken, .food)

        // "with no sugar", "without butter"
        if roll(8) {
            example.append(pick(Grammar.negations), .negation)
            example.append(pick(foods).spoken, .food)
        }
    }

    // MARK: - Water

    private mutating func buildWater() -> Example {
        var example = Example(tokens: [], labels: [], intent: .logWater)
        example.append(pick(Grammar.leadIns), .none)

        if roll(70) {
            example.append(pick(Grammar.quantityForms), .quantity)
            example.append(pick(Grammar.drinkVessels), .unit)
            if roll(80) { example.append("of", .none) }
        } else {
            example.append(pick(Grammar.articles), .quantity)
            if roll(60) {
                example.append(pick(Grammar.drinkVessels), .unit)
                example.append("of", .none)
            }
        }

        example.append(pick(Grammar.drinkNouns), .drink)
        if roll(18) { example.append(pick(Grammar.timePhrases), .time) }
        example.append(pick(Grammar.tailOffs), .none)
        return example
    }

    // MARK: - Symptoms

    private mutating func buildSymptom() -> Example {
        var example = Example(tokens: [], labels: [], intent: .logSymptom)

        example.append(pick(Grammar.symptomLeadIns), .none)
        if roll(35) { example.append(pick(Grammar.severityWords), .severity) }

        let symptom = pick(Grammar.symptomPhrases)
        example.tokens.append(contentsOf: symptom.tokens)
        example.labels.append(contentsOf: Array(repeating: .symptom, count: symptom.tokens.count))

        if roll(30) { example.append(pick(Grammar.timePhrases), .time) }

        // "after the pasta" — the link the Date Log cares about most.
        if roll(28) {
            example.append("after", .none)
            if roll(50) { example.append("the", .none) }
            example.append(pick(foods).spoken, .food)
        }
        return example
    }

    // MARK: - Journal, queries, corrections

    private mutating func buildJournal() -> Example {
        var example = Example(tokens: [], labels: [], intent: .journalEntry)
        example.append(pick(Grammar.journalOpeners), .none)
        if roll(45) {
            example.append(roll(50) ? "," : "and", .none)
            example.append(pick(Grammar.journalContinuations), .none)
        }
        return example
    }

    private mutating func buildQuery() -> Example {
        var example = Example(tokens: [], labels: [], intent: .query)
        example.append(pick(Grammar.queryTemplates), .none)
        return example
    }

    private mutating func buildCorrection() -> Example {
        var example = Example(tokens: [], labels: [], intent: .correction)
        example.append(pick(Grammar.correctionOpeners), .none)
        if roll(55) {
            example.append(pick(Grammar.quantityForms), .quantity)
            if roll(40) { example.append(pick(Grammar.allUnits), .unit) }
        }
        example.append(pick(foods).spoken, .food)
        return example
    }

    // MARK: - Noise
    //
    // Clean training text produces a model that only works on clean input.
    // Real input arrives from dictation and thumbs, so the corpus has to look
    // like that too.

    private mutating func applyNoise(_ example: inout Example) {
        guard roll(30) else { return }

        let index = Int(rng.next(upperBound: UInt64(max(1, example.tokens.count))))
        guard example.tokens.indices.contains(index) else { return }
        var token = example.tokens[index]
        guard token.count > 3 else { return }

        switch rng.next(upperBound: 4) {
        case 0:
            // Dropped character — the commonest typo.
            let position = token.index(token.startIndex, offsetBy: Int(rng.next(upperBound: UInt64(token.count))))
            token.remove(at: position)
        case 1:
            // Transposed pair.
            let position = Int(rng.next(upperBound: UInt64(token.count - 1)))
            var characters = Array(token)
            characters.swapAt(position, position + 1)
            token = String(characters)
        case 2:
            // Doubled character.
            let position = token.index(token.startIndex, offsetBy: Int(rng.next(upperBound: UInt64(token.count))))
            token.insert(token[position], at: position)
        default:
            // Dictation running two words together.
            guard index + 1 < example.tokens.count else { return }
            example.tokens[index] = token + example.tokens[index + 1]
            example.tokens.remove(at: index + 1)
            example.labels.remove(at: index + 1)
            return
        }
        example.tokens[index] = token
    }

    // MARK: - Helpers

    private mutating func pick<T>(_ options: [T]) -> T {
        options[Int(rng.next(upperBound: UInt64(options.count)))]
    }

    /// True `percent` of the time.
    private mutating func roll(_ percent: Int) -> Bool {
        rng.next(upperBound: 100) < UInt64(percent)
    }
}

/// A small deterministic PRNG.
///
/// Seeded so a corpus is reproducible: the same seed gives the same 50,000
/// sentences, which means a change in model accuracy can be attributed to the
/// model rather than to different training data.
struct SeededGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    /// xorshift64*
    mutating func next() -> UInt64 {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 0x2545F4914F6CDD1D
    }

    mutating func next(upperBound: UInt64) -> UInt64 {
        upperBound == 0 ? 0 : next() % upperBound
    }
}
