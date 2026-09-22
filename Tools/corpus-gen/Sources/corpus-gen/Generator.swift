import Foundation
import VesselIntelligence

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
    /// Bare head nouns, most-covered first — how people actually name food.
    let heads: [String]
    /// Ingredient groups from the database, for questions about triggers.
    let triggerGroups: [String]
    var rng: SeededGenerator

    /// A food name split into the form a sentence would use it in.
    struct FoodName {
        /// "chicken breast, grilled" → "grilled chicken breast"
        let spoken: String
        /// Whether the name already contains a preparation word, so the
        /// generator doesn't produce "grilled grilled chicken".
        let hasPrep: Bool
    }

    init(foods: [FoodName], heads: [String], triggerGroups: [String], seed: UInt64) {
        self.foods = foods
        self.heads = heads
        self.triggerGroups = triggerGroups
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
            digitizeQuantities(&example)
            applyNoise(&example)
            guard !example.tokens.isEmpty,
                  let normalized = CorpusNormalizer.apply(example) else { continue }
            examples.append(normalized)
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
                if index > 0 { example.append(roll(70) ? "and" : ",", .none) }
                // "an orange", "a banana" — a lone food with only an article.
                if roll(25) { example.append(pick(Grammar.articles), .quantity) }
                let prepFirst = roll(25)
                if prepFirst { example.append(pick(Grammar.preps), .prep) }
                example.append(pickFoodPhrase(), .food)
                if !prepFirst, roll(12) { example.append(pick(Grammar.preps), .prep) }
            }
            if roll(20) { example.append(pick(Grammar.timePhrases), .time) }
            if roll(20) { example.append(pick(Grammar.mealPhrases), .meal) }
            return example
        }

        // A portion *of* something — "a wedge of brie", "the rest of the soup".
        //
        // Deliberately its own branch and deliberately common. Until this
        // existed, every "<x> of <y>" the model had ever seen was a drink.
        if roll(14) {
            if roll(35) { example.append(pick(Grammar.eatingVerbs), .none) }
            example.append(pick(Grammar.foodPortions), .quantity)
            example.append("of", .none)
            if roll(70) { example.append(roll(50) ? "the" : "a", .none) }
            if roll(20) { example.append(pick(Grammar.preps), .prep) }
            example.append(pickFoodPhrase(), .food)
            if roll(22) { example.append(pick(Grammar.trailingClauses), .none) }
            if roll(15) { example.append(pick(Grammar.timePhrases), .time) }
            return example
        }

        // Food with a drink named beside it, as a bare list. "cereal, orange
        // juice" is a food log; the drink is incidental, and reading the whole
        // utterance as a water log loses the meal entirely.
        if roll(16) {
            if roll(30) { example.append(pick(Grammar.leadIns), .none) }
            if roll(40) { example.append(pick(Grammar.quantityForms), .quantity) }
            example.append(pickFoodPhrase(), .food)
            example.append(roll(55) ? "," : "and", .none)
            if roll(45) { example.append(roll(50) ? "a" : "some", .none) }
            if roll(30) { example.append(pick(Grammar.drinkModifiers), .none) }
            example.append(pick(Grammar.drinkNouns), .drink)
            if roll(18) { example.append(pick(Grammar.trailingClauses), .none) }
            return example
        }

        // "toast with jam", "chicken with rice" — one food joined to another.
        if roll(20) {
            if roll(35) { example.append(pick(Grammar.leadIns), .none) }
            if roll(45) { example.append(pick(Grammar.quantityForms), .quantity) }
            example.append(pickFoodPhrase(), .food)
            example.append(pick(Grammar.foodConnectors), .none)
            if roll(25) { example.append(pick(Grammar.articles), .quantity) }
            example.append(roll(35) ? pick(Grammar.condiments) : pickFoodPhrase(), .food)
            if roll(20) { example.append(pick(Grammar.mealPhrases), .meal) }
            if roll(15) { example.append(pick(Grammar.trailingClauses), .none) }
            return example
        }

        // "smashed a protein shake", "picked at some leftovers".
        if roll(12) {
            example.append(pick(Grammar.eatingVerbs), .none)
            if roll(60) { example.append(pick(Grammar.articles), .quantity) }
            if roll(25) { example.append(pick(Grammar.preps), .prep) }
            example.append(pickFoodPhrase(), .food)
            if roll(28) { example.append(pick(Grammar.trailingClauses), .none) }
            if roll(18) { example.append(pick(Grammar.mealPhrases), .meal) }
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
        if roll(12) { appendAccompanyingDrink(to: &example) }
        // An offhand remark about the food.
        if roll(14) { example.append(pick(Grammar.foodAsides), .none) }
        // Where or when it was eaten — meaningless, and previously tagged FOOD.
        if roll(16) { example.append(pick(Grammar.trailingClauses), .none) }

        example.append(pick(Grammar.tailOffs), .none)
        return example
    }

    /// A food from the database, biased toward the ones people actually eat.
    ///
    /// `FoodLoader` returns names ordered by staple rank then popularity, but
    /// the generator was sampling them uniformly — so "bread" appeared no more
    /// often than the two-thousandth row, and common words ended up too rare
    /// for the tagger to learn. Squaring a uniform draw pulls the distribution
    /// toward the front of that ordering, which is the shape of real speech:
    /// a few hundred foods make up almost everything anybody logs.
    private mutating func pickCommonFood() -> Generator.FoodName {
        guard !foods.isEmpty else { return Generator.FoodName(spoken: "food", hasPrep: false) }
        let uniform = Double(rng.next(upperBound: 10_000)) / 10_000
        let index = Int(uniform * uniform * Double(foods.count))
        return foods[min(index, foods.count - 1)]
    }

    /// A food name — usually from the database, sometimes the colloquial dish.
    ///
    /// Mixed rather than separated so the two occupy the same slots in the same
    /// sentences: the point is that "fry up" behaves grammatically exactly like
    /// "scrambled eggs", not that it gets its own sentence shapes.
    private mutating func pickFoodPhrase() -> String {
        if roll(18) { return pick(Grammar.colloquialDishes) }
        if roll(30), !heads.isEmpty { return pickHead() }
        // A word the tagger has never seen, in a food's position. Real input is
        // full of foods the database doesn't spell — "lasagne", "porridge",
        // "katsu" — and the tagger must learn that "a quarter of a ___" is food
        // from the frame alone, not only from a vocabulary it memorised.
        if roll(4) { return inventedWord() }
        return pickCommonFood().spoken
    }

    /// A head noun, biased toward the ones covering the most rows.
    private mutating func pickHead() -> String {
        let uniform = Double(rng.next(upperBound: 10_000)) / 10_000
        return heads[min(Int(uniform * uniform * Double(heads.count)), heads.count - 1)]
    }

    /// A pronounceable nonsense word, two or three syllables.
    private mutating func inventedWord() -> String {
        let onsets = ["b", "d", "f", "g", "k", "l", "m", "n", "p", "r", "s", "t", "v", "z", "ch", "sh", "br", "tr", "pl"]
        let vowels = ["a", "e", "i", "o", "u", "ai", "ee", "oo"]
        let codas = ["", "", "n", "r", "l", "s", "k", "tt"]
        let syllables = roll(60) ? 2 : 3
        return (0..<syllables).map { _ in pick(onsets) + pick(vowels) + pick(codas) }.joined()
    }

    private mutating func appendFoodItem(to example: inout Example) {
        let food = pickCommonFood()

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

        // "eggs, scrambled", "chicken, grilled" — the preparation after the
        // food. Every prep in the corpus used to come first, so a trailing one
        // was tagged FOOD and became a second food called "scrambled".
        if roll(9), !food.hasPrep { example.append(pick(Grammar.preps), .prep) }

        // "with no sugar", "without butter"
        if roll(8) {
            example.append(pick(Grammar.negations), .negation)
            example.append(pickCommonFood().spoken, .food)
        }
    }

    /// "with my tea": only the drink is DRINK. Labelling the whole phrase
    /// taught the tagger that "with" and "my" are part of a drink's name, and it
    /// duly returned drinks called "with my tea".
    private mutating func appendAccompanyingDrink(to example: inout Example) {
        let function: Set<String> = ["with", "my", "a", "an", "some", "and", "alongside", "the"]
        for word in pick(Grammar.accompanyingDrinks).split(separator: " ").map(String.init) {
            example.append(word, function.contains(word) ? .none : .drink)
        }
    }

    // MARK: - Water

    private mutating func buildWater() -> Example {
        var example = Example(tokens: [], labels: [], intent: .logWater)

        // "large flat white", "just water with dinner" — ordered by name, with
        // no vessel, no "of" and often no quantity. The corpus had no drink
        // utterance of this shape, so the classifier had nothing to go on but
        // the words, and read them as food.
        if roll(22) {
            if roll(30) { example.append("just", .none) }
            if roll(55) { example.append(pick(Grammar.drinkModifiers), .none) }
            example.append(pick(Grammar.drinkNouns), .drink)
            if roll(34) { example.append(pick(Grammar.mealPhrases), .meal) }
            if roll(20) { example.append(pick(Grammar.timePhrases), .time) }
            if roll(20) { example.append(pick(Grammar.trailingClauses), .none) }
            return example
        }

        // "finished my water bottle", "refilled my flask" — the vessel after
        // the drink, owned rather than counted.
        if roll(8) {
            example.append(pick(["finished", "drained", "emptied", "refilled", "downed", "got through"]), .none)
            example.append(pick(["my", "the", "a", "another"]), .none)
            example.append(pick(Grammar.drinkNouns), .drink)
            example.append(pick(Grammar.drinkVessels), .unit)
            if roll(25) { example.append(pick(Grammar.trailingClauses), .none) }
            return example
        }

        example.append(pick(Grammar.leadIns), .none)

        if roll(70) {
            example.append(pick(Grammar.quantityForms), .quantity)
            if roll(14) { example.append(pick(Grammar.quantityFillers), .none) }
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
        // A drink is had *with lunch* and *on the way to work* just as often as
        // food is. Only food ever carried these, which is most of why a drink
        // beside a meal was read as one.
        if roll(24) { example.append(pick(Grammar.mealPhrases), .meal) }
        if roll(16) { example.append(pick(Grammar.trailingClauses), .none) }
        example.append(pick(Grammar.tailOffs), .none)
        return example
    }

    // MARK: - Symptoms

    private mutating func buildSymptom() -> Example {
        var example = Example(tokens: [], labels: [], intent: .logSymptom)

        // "my eczema has flared up", "stomach's been playing up".
        if roll(26) {
            example.append(pick(Grammar.symptomSubjects), .none)
            if roll(75) { example.append(pick(Grammar.symptomLinkers), .none) }
            if roll(25) { example.append(pick(Grammar.severityWords), .severity) }
            // A third of the time, a complaint that only makes sense here.
            let idiom = roll(30) ? pick(Grammar.subjectSymptoms) : pick(Grammar.symptomPhrases)
            example.tokens.append(contentsOf: idiom.tokens)
            example.labels.append(contentsOf: Array(repeating: .symptom, count: idiom.tokens.count))
            if roll(30) { example.append(roll(50) ? "again" : "today", .none) }
            else if roll(20) { example.append(pick(Grammar.symptomVagueTails), .none) }
            if roll(20) { example.append(pick(Grammar.timePhrases), .time) }
            return example
        }

        example.append(pick(Grammar.symptomLeadIns), .none)
        if roll(35) { example.append(pick(Grammar.severityWords), .severity) }

        // Mostly the grammar's own phrasings; sometimes a word straight from
        // the app's symptom vocabulary, so every word the app files as a
        // symptom is one the classifier has actually seen.
        let symptomTokens = roll(20)
            ? pick(SymptomVocabulary.phrases).split(separator: " ").map(String.init)
            : pick(Grammar.symptomPhrases).tokens
        example.tokens.append(contentsOf: symptomTokens)
        example.labels.append(contentsOf: Array(repeating: .symptom, count: symptomTokens.count))

        if roll(30) { example.append(pick(Grammar.timePhrases), .time) }

        // "after the pasta" — the link the Date Log cares about most.
        if roll(28) {
            example.append("after", .none)
            if roll(50) { example.append("the", .none) }
            example.append(pickCommonFood().spoken, .food)
        } else if roll(18) {
            // "puffy after that meal" — "that" otherwise only opened corrections.
            example.append(pick(Grammar.symptomVagueTails), .none)
        }
        return example
    }

    // MARK: - Journal, queries, corrections

    private mutating func buildJournal() -> Example {
        var example = Example(tokens: [], labels: [], intent: .journalEntry)

        // "feeling motivated this week" — a mood, not a symptom.
        if roll(14) {
            example.append(pick(Grammar.journalMoodLeadIns), .none)
            if roll(25) { example.append(pick(["really", "quite", "pretty", "a lot more", "much"]), .none) }
            example.append(pick(Grammar.journalMoods), .none)
            example.append(pick(Grammar.journalMoodTails), .none)
            return example
        }

        // "had a good chat with my sister" — "had" not introducing food.
        if roll(10) {
            example.append(pick(["had a", "had a really", "just had a", "we had a"]), .none)
            example.append(pick(Grammar.journalHadAdjectives), .none)
            example.append(pick(Grammar.journalHadEvents), .none)
            example.append(pick(Grammar.journalCompanions), .none)
            if roll(25) { example.append(pick(Grammar.journalActivityTails), .none) }
            return example
        }

        // A day with nothing in it is still a journal entry.
        if roll(18) {
            example.append(pick(Grammar.journalNonEvents), .none)
            if roll(35) {
                example.append(roll(50) ? "," : "and", .none)
                example.append(pick(Grammar.journalContinuations), .none)
            }
            return example
        }

        // Something done, and how it felt after — the "felt" that is not a symptom.
        if roll(16) {
            example.append(pick(Grammar.journalActivities), .none)
            if roll(70) { example.append(pick(Grammar.journalActivityTails), .none) }
            return example
        }

        // A day summed up, sometimes with what filled it.
        if roll(16) {
            example.append(pick(Grammar.journalDayDescriptors), .none)
            if roll(45) {
                example.append(roll(60) ? "," : "and", .none)
                example.append(roll(50) ? pick(Grammar.journalSocial)
                                       : pick(Grammar.journalContinuations), .none)
            }
            return example
        }

        if roll(12) {
            example.append(pick(Grammar.journalSocial), .none)
            if roll(30) { example.append(pick(Grammar.journalActivityTails), .none) }
            return example
        }

        // An intention, which otherwise reads as a correction.
        if roll(12) {
            example.append(pick(Grammar.journalIntentions), .none)
            return example
        }

        example.append(pick(Grammar.journalOpeners), .none)
        if roll(45) {
            example.append(roll(50) ? "," : "and", .none)
            example.append(pick(Grammar.journalContinuations), .none)
        }
        return example
    }

    private mutating func buildQuery() -> Example {
        var example = Example(tokens: [], labels: [], intent: .query)
        switch rng.next(upperBound: 6) {
        case 0:
            example.append(pick(Grammar.queryTemplates), .none)
        case 1:
            example.append(pick(Grammar.queryAmountStems), .none)
            example.append(pick(Grammar.queryMetrics), .none)
            example.append(pick(Grammar.queryRanges), .none)
        case 2:
            example.append(pick(Grammar.queryRecallStems), .none)
            if roll(50) { example.append(pick(Grammar.queryRanges), .none) }
            else if roll(50) { example.append(pick(Grammar.mealPhrases), .none) }
        case 3:
            example.append(pick(Grammar.queryCheckStems), .none)
            example.append(pick(Grammar.queryGoals), .none)
            if roll(40) { example.append(pick(Grammar.queryRanges), .none) }
        case 4:
            // "is dairy a trigger for me" — a food inside a question.
            let frame = pick(Grammar.queryTriggerFrames)
            example.append(frame.before, .none)
            example.append(roll(35) && !triggerGroups.isEmpty ? pick(triggerGroups) : pickCommonFood().spoken, .food)
            example.append(frame.after, .none)
        default:
            example.append(pick(Grammar.querySymptomFrames), .none)
            if roll(25) { example.append(pick(["lately", "recently", "this week", "usually"]), .none) }
        }
        return example
    }

    private mutating func buildCorrection() -> Example {
        var example = Example(tokens: [], labels: [], intent: .correction)

        // A correction about a number, with nothing named at all — "not two,
        // three". The corpus always ended a correction with a food, so a bare
        // quantity fix was read as a food log.
        if roll(18) {
            if roll(60) { example.append(pick(Grammar.correctionOpeners), .none) }
            else { example.append("not", .none) }
            example.append(pick(Grammar.quantityForms), .quantity)
            example.append(roll(50) ? "," : "it was", .none)
            example.append(pick(Grammar.quantityForms), .quantity)
            if roll(35) { example.append(pick(Grammar.allUnits), .unit) }
            return example
        }

        example.append(pick(Grammar.correctionOpeners), .none)
        if roll(55) {
            example.append(pick(Grammar.quantityForms), .quantity)
            if roll(40) { example.append(pick(Grammar.allUnits), .unit) }
        }
        // Corrections are about drinks as often as meals — "actually it was a
        // large coffee" was being read as a water log for want of any
        // correction in the corpus that mentioned a drink.
        if roll(28) {
            if roll(50) { example.append(pick(Grammar.drinkModifiers), .none) }
            example.append(pick(Grammar.drinkNouns), .drink)
        } else {
            example.append(pickFoodPhrase(), .food)
        }
        return example
    }

    // MARK: - Noise
    //
    // Clean training text produces a model that only works on clean input.
    // Real input arrives from dictation and thumbs, so the corpus has to look
    // like that too.

    /// Rewrites some spoken numerals as digits, mirroring `TextNormalizer`.
    ///
    /// Applied after the sentence is built so it catches every quantity in
    /// every branch, and applied only some of the time so both surfaces stay in
    /// the corpus — the tagger has to handle whichever it is given.
    private mutating func digitizeQuantities(_ example: inout Example) {
        for index in example.tokens.indices where example.labels[index] == .quantity {
            guard let digits = Grammar.spokenNumerals[example.tokens[index].lowercased()] else { continue }
            if roll(50) { example.tokens[index] = digits }
        }
    }

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
