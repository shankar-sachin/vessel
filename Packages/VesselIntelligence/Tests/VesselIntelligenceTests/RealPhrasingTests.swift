import Testing
import Foundation
@testable import VesselIntelligence
import VesselCore

/// The honest evaluation.
///
/// The training report says 99.5% intent accuracy and 0.98 macro F1, but those
/// are measured on held-out sentences from the *same generator* that produced
/// the training data. They prove the model learned the grammar it was taught;
/// they say nothing about whether that grammar resembles how people talk.
///
/// Every phrasing below was written by hand, deliberately in ways the generator
/// does not produce — contractions, slang, run-on sentences, British and
/// American idiom, and the sloppy half-sentences people actually dictate. This
/// is the number worth quoting.

private struct Case {
    let text: String
    let intent: ParsedEntry.Intent
    /// A word expected in one of the extracted foods, when relevant.
    let expectsFood: String?
    /// Further foods or drinks the utterance names, each of which must come back
    /// as a phrase of its own rather than absorbed into a neighbour's span.
    let expectsAlso: [String]
    /// Expected quantity on the first food, when the phrasing states one.
    let expectsQuantity: Double?

    init(_ text: String, _ intent: ParsedEntry.Intent, food: String? = nil,
         also: [String] = [], quantity: Double? = nil) {
        self.text = text
        self.intent = intent
        self.expectsFood = food
        self.expectsAlso = also
        self.expectsQuantity = quantity
    }

    var expectedFoods: [String] { (expectsFood.map { [$0] } ?? []) + expectsAlso }
}

private let realPhrasings: [Case] = [
    // Everyday food logging, phrased naturally
    Case("had a bowl of porridge with berries this morning", .logFood, food: "porridge", also: ["berries"]),
    Case("two slices of toast and a boiled egg", .logFood, food: "toast", also: ["egg"], quantity: 2),
    Case("just finished a chicken salad", .logFood, food: "chicken"),
    Case("grabbed a banana on the way out", .logFood, food: "banana"),
    Case("leftover curry for lunch", .logFood, food: "curry"),
    Case("big bowl of pasta last night", .logFood, food: "pasta"),
    Case("half an avocado on sourdough", .logFood, food: "avocado", also: ["sourdough"], quantity: 0.5),
    Case("three scrambled eggs", .logFood, food: "eggs", quantity: 3),
    Case("a handful of almonds", .logFood, food: "almonds"),
    Case("roast chicken and potatoes for dinner", .logFood, food: "chicken", also: ["potatoes"]),
    Case("bowl of cereal", .logFood, food: "cereal"),
    Case("chicken breast with rice and broccoli", .logFood, food: "chicken", also: ["rice", "broccoli"]),
    Case("couple of biscuits with my tea", .logFood, food: "biscuits", also: ["tea"]),
    Case("greek yogurt and honey", .logFood, food: "yogurt", also: ["honey"]),
    Case("slice of cheesecake, was very good", .logFood, food: "cheesecake"),
    Case("1.5 cups of cooked quinoa", .logFood, food: "quinoa", quantity: 1.5),
    Case("some leftover pizza around 11", .logFood, food: "pizza"),
    Case("peanut butter on toast before the gym", .logFood, food: "toast", also: ["peanut butter"]),
    Case("steak and salad", .logFood, food: "steak", also: ["salad"]),
    Case("a few crackers with cheese", .logFood, food: "crackers", also: ["cheese"]),

    // Drinks
    Case("glass of water", .logWater, food: "water"),
    Case("just had a coffee", .logWater),
    Case("drank about a litre of water this morning", .logWater, food: "water"),
    Case("two cups of green tea", .logWater, food: "tea"),
    Case("a big glass of orange juice", .logWater, food: "orange juice"),
    Case("sparkling water with lunch", .logWater, food: "water"),
    Case("another coffee", .logWater),
    Case("bottle of water after my run", .logWater, food: "water"),

    // Symptoms, phrased the way people complain
    Case("feeling really bloated", .logSymptom),
    Case("my stomach is killing me", .logSymptom),
    Case("bit of heartburn after dinner", .logSymptom),
    Case("got a headache again", .logSymptom),
    Case("so gassy today", .logSymptom),
    Case("feeling nauseous", .logSymptom),
    Case("stomach cramps since lunch", .logSymptom),
    Case("really tired this afternoon", .logSymptom),
    Case("bloated again after the pasta", .logSymptom),
    Case("terrible indigestion", .logSymptom),

    // Journal
    Case("felt pretty good today, slept well for once", .journalEntry),
    Case("stressful day, didn't eat properly", .journalEntry),
    Case("energy was up and down all day", .journalEntry),
    Case("quiet weekend, went for a long walk", .journalEntry),
    Case("mood has been better this week", .journalEntry),

    // Questions
    Case("how many calories have I had today", .query),
    Case("what did I eat yesterday", .query),
    Case("how much water have I drunk", .query),
    Case("what's my streak at", .query),
    Case("did I log dinner", .query),

    // Corrections
    Case("no I meant two eggs", .correction),
    Case("actually it was a large coffee", .correction),
    Case("change that to three slices", .correction),

    // --- Second batch ---------------------------------------------------
    // Added after the first evaluation round, deliberately testing phrasings
    // the grammar was *not* extended to cover. Without these the eval would
    // only measure how well the generator learned its own new rules.
    Case("smashed a protein shake after training", .logFood, food: "protein"),
    Case("picked at some leftovers", .logFood),
    Case("massive fry up this morning", .logFood),
    Case("just a piece of fruit", .logFood, food: "fruit"),
    Case("takeaway noodles", .logFood, food: "noodles"),
    Case("four rice cakes", .logFood, food: "rice", quantity: 4),
    Case("a quarter of a melon", .logFood, food: "melon", quantity: 0.25),
    Case("porridge, black coffee", .logFood, food: "porridge", also: ["coffee"]),
    Case("had seconds of the lasagne", .logFood, food: "lasagne"),
    Case("downed a pint of water", .logWater, food: "water"),
    Case("herbal tea before bed", .logWater, food: "tea"),
    Case("half a litre of water", .logWater, food: "water"),
    Case("guts are churning", .logSymptom),
    Case("skin has flared up again", .logSymptom),
    Case("bit windy after that", .logSymptom),
    Case("slept badly, felt flat all morning", .journalEntry),
    Case("nothing much to report today", .journalEntry),
    Case("how am I doing on protein", .query),
    Case("what was my dinner on Tuesday", .query),
    Case("sorry I meant the large one", .correction),

    // --- Third batch ----------------------------------------------------
    // Written before the v1.5.1 grammar work, against the failure classes the
    // second round exposed, and deliberately *not* the phrasings that were
    // failing. Fixing "a quarter of a melon" by teaching the generator that
    // exact sentence would prove nothing; these are different members of the
    // same classes, so they only pass if the change generalized.

    // Partitives and portions of food — the construction that was being read
    // as a drink, because "a <vessel> of <drink>" was the only "X of Y" the
    // grammar had ever produced.
    Case("the last of the leftover rice", .logFood, food: "rice"),
    Case("a wedge of brie", .logFood, food: "brie"),
    Case("third of a pizza", .logFood, food: "pizza"),
    Case("half a pack of biscuits", .logFood, food: "biscuits", quantity: 0.5),
    Case("a bit of leftover chicken", .logFood, food: "chicken"),
    Case("small portion of chips", .logFood, food: "chips"),
    Case("the rest of the soup", .logFood, food: "soup"),

    // Colloquial eating verbs, which carried no food signal at all.
    Case("demolished a burrito", .logFood, food: "burrito"),
    Case("grabbed a sausage roll at the station", .logFood, food: "sausage"),
    Case("picked at a salad", .logFood, food: "salad"),
    Case("polished off the lasagne", .logFood, food: "lasagne"),

    // Ordinary food logging, for balance — an eval made only of hard cases
    // measures something no user experiences.
    Case("two poached eggs on toast", .logFood, food: "eggs", also: ["toast"], quantity: 2),
    Case("beans on toast", .logFood, food: "beans"),
    Case("an apple and a handful of nuts", .logFood, food: "apple", also: ["nuts"]),
    Case("chicken tikka masala with naan", .logFood, food: "chicken", also: ["naan"]),
    Case("some grapes while cooking", .logFood, food: "grapes"),
    Case("a bowl of soup and a roll", .logFood, food: "soup", also: ["roll"]),
    Case("toast with jam", .logFood, food: "toast", also: ["jam"]),
    Case("shepherd's pie for tea", .logFood, food: "pie"),
    Case("two boiled eggs and spinach", .logFood, food: "eggs", also: ["spinach"], quantity: 2),

    // Food alongside a named drink, which used to tip the whole utterance
    // into a water log.
    Case("croissant and a flat white", .logFood, food: "croissant", also: ["flat white"]),
    Case("cereal, orange juice", .logFood, food: "cereal", also: ["orange juice"]),

    // Drinks
    Case("a mug of tea", .logWater, food: "tea"),
    Case("large flat white", .logWater),
    Case("just water with dinner", .logWater, food: "water"),
    Case("pint of orange juice", .logWater, food: "orange juice"),
    Case("can of diet coke", .logWater),
    Case("sipping on green tea", .logWater),

    // Symptoms described rather than named.
    Case("stomach's been playing up", .logSymptom),
    Case("my eczema has flared up", .logSymptom),
    Case("really puffy after that meal", .logSymptom),
    Case("cramping up again", .logSymptom),
    Case("reflux is back", .logSymptom),
    Case("feel sick", .logSymptom),
    Case("head's banging", .logSymptom),
    Case("bit queasy this evening", .logSymptom),

    // Journal, including the non-event — every journal opener the generator
    // knew described something happening.
    Case("nothing eventful, just work", .journalEntry),
    Case("same as usual really", .journalEntry),
    Case("went for a swim and felt great after", .journalEntry),
    Case("long day, glad it's over", .journalEntry),
    Case("been a strange week", .journalEntry),
    Case("trying to be more consistent", .journalEntry),

    // Queries
    Case("how many carbs so far", .query),
    Case("what have i eaten today", .query),
    Case("am i drinking enough", .query),
    Case("when did i last log", .query),
    Case("show me last week", .query),

    // Corrections
    Case("no that was a small one", .correction),
    Case("actually make it two", .correction),
    Case("that should say chicken not turkey", .correction),

    // --- Fourth batch ---------------------------------------------------
    // Written after the v1.5.1 grammar work but before the retrain that
    // followed it, so they are held out from the fixes aimed at the third
    // batch's failures. Weighted toward the two things the corpus finds
    // hardest: telling a drink from a meal, and telling a complaint from a
    // diary entry.

    Case("packet of crisps at my desk", .logFood, food: "crisps"),
    Case("a tub of yogurt", .logFood, food: "yogurt"),
    Case("scrambled eggs on sourdough", .logFood, food: "eggs", also: ["sourdough"]),
    Case("reheated the curry from last night", .logFood, food: "curry"),
    Case("nicked a few chips off her plate", .logFood, food: "chips"),
    Case("two sausages and mash", .logFood, food: "sausages", also: ["mash"], quantity: 2),
    Case("a banana before my run", .logFood, food: "banana"),
    Case("bowl of granola with milk", .logFood, food: "granola", also: ["milk"]),
    Case("half a baguette with butter", .logFood, food: "baguette", also: ["butter"], quantity: 0.5),
    Case("some olives while cooking dinner", .logFood, food: "olives"),

    // Drinks that sit next to a meal — the construction that keeps tipping
    // the classifier the wrong way in both directions.
    Case("orange juice with breakfast", .logWater, food: "orange juice"),
    Case("a beer with dinner", .logWater, food: "beer"),
    Case("black coffee, nothing else", .logWater),
    Case("two more glasses of water", .logWater, quantity: 2),
    Case("decaf after dinner", .logWater, food: "decaf"),
    Case("smoothie on the way to work", .logWater, food: "smoothie"),

    // Complaints
    Case("gut has been off all day", .logSymptom),
    Case("bit of a sore throat", .logSymptom),
    Case("proper stomach ache tonight", .logSymptom),
    Case("keep burping", .logSymptom),
    Case("my joints ache today", .logSymptom),
    Case("felt lightheaded standing up", .logSymptom),

    // Diary
    Case("busy one, barely sat down", .journalEntry),
    Case("caught up with an old friend", .journalEntry),
    Case("slept nine hours and still tired", .journalEntry),
    Case("work was fine, weather was not", .journalEntry),
    Case("reading more this month", .journalEntry),

    // Questions
    Case("did i hit my water goal", .query),
    Case("whats my longest streak", .query),
    Case("how much sugar today", .query),

    // Corrections
    Case("not two, three", .correction),
    Case("scratch that last one", .correction),
    // v1.5.1, second round — written after the screenshots showed spans the
    // intent score could not see. Preparations after the food, lists with a
    // colon or commas, drinks with company, and trigger questions.
    Case("eggs, scrambled, with a bit of toast", .logFood, food: "eggs", also: ["toast"]),
    Case("chicken, grilled, and some rice", .logFood, food: "chicken", also: ["rice"]),
    Case("toast, buttered", .logFood, food: "toast"),
    Case("made a stir fry with tofu and peppers", .logFood, food: "tofu", also: ["peppers"]),
    Case("for breakfast i had yoghurt with granola", .logFood, food: "yoghurt", also: ["granola"]),
    Case("lunch was a tuna sandwich", .logFood, food: "sandwich"),
    Case("dinner: salmon, rice, green beans", .logFood, food: "salmon", also: ["rice", "green beans"]),
    Case("ate way too much pizza", .logFood, food: "pizza"),
    Case("snacked on some crackers", .logFood, food: "crackers"),
    Case("munched a handful of cashews", .logFood, food: "cashews"),
    Case("two pieces of fried chicken", .logFood, food: "chicken", quantity: 2),
    Case("a slice of banana bread with my coffee", .logFood, food: "banana bread", also: ["coffee"]),
    Case("a bagel with cream cheese", .logFood, food: "bagel", also: ["cream cheese"]),
    Case("had some soup for lunch", .logFood, food: "soup"),
    Case("an orange", .logFood, food: "orange"),
    Case("some dark chocolate after dinner", .logFood, food: "chocolate"),
    Case("the kids leftover fish fingers", .logFood, food: "fish fingers"),
    Case("bowl of ramen", .logFood, food: "ramen"),
    Case("three pancakes with syrup", .logFood, food: "pancakes", also: ["syrup"], quantity: 3),
    Case("overnight oats", .logFood, food: "oats"),
    Case("hummus with carrot sticks", .logFood, food: "hummus", also: ["carrot"]),
    Case("ice cream after dinner", .logFood, food: "ice cream"),
    Case("a pint of beer with the lads", .logWater, food: "beer"),
    Case("cup of tea with breakfast", .logWater, food: "tea"),
    Case("had an espresso", .logWater, food: "espresso"),
    Case("iced latte", .logWater, food: "latte"),
    Case("300ml of water", .logWater, food: "water", quantity: 300),
    Case("finished my water bottle", .logWater, food: "water"),
    Case("glass of milk before bed", .logWater, food: "milk"),
    Case("lemonade at lunch", .logWater, food: "lemonade"),
    Case("a bottle of kombucha", .logWater, food: "kombucha"),
    Case("two glasses of red wine", .logWater, food: "wine", quantity: 2),
    Case("bloated after the pizza", .logSymptom),
    Case("stomach feels tight", .logSymptom),
    Case("heartburn again tonight", .logSymptom),
    Case("loose stools this morning", .logSymptom),
    Case("feel a bit off after lunch", .logSymptom),
    Case("constipated for two days now", .logSymptom),
    Case("belly ache after the milkshake", .logSymptom),
    Case("migraine coming on", .logSymptom),
    Case("itchy after the prawns", .logSymptom),
    Case("feeling motivated this week", .journalEntry),
    Case("rest day today", .journalEntry),
    Case("anxious about the exam tomorrow", .journalEntry),
    Case("lovely evening with family", .journalEntry),
    Case("had a good chat with my sister", .journalEntry),
    Case("how much protein did i have yesterday", .query),
    Case("what did i have for lunch", .query),
    Case("how many glasses of water today", .query),
    Case("what usually upsets my stomach", .query),
    Case("is dairy a trigger for me", .query),
    Case("wait, it was three not two", .correction),
    Case("make that a large", .correction),
    Case("oops that was yesterday", .correction),
    Case("undo that", .correction),
    Case("i said tea not coffee", .correction),
    // A percentage names a kind of milk, not an amount. "2% milk" was read as
    // two servings of whole milk.
    Case("2% milk", .logWater, food: "milk"),
    Case("a glass of skim milk", .logWater, food: "milk"),
    Case("two cups of 1% milk", .logWater, food: "milk", quantity: 2),
    Case("two percent milk in my coffee", .logWater, food: "milk"),
    Case("0% greek yogurt with honey", .logFood, food: "yogurt", also: ["honey"]),
    Case("a latte with oat milk", .logWater, food: "latte")
]

@Suite("Real phrasings — generalization")
struct RealPhrasingTests {

    private let pipeline = ParsePipeline()

    @Test("Intent accuracy on hand-written phrasings meets the gate")
    func intentGeneralizes() {
        var correct = 0
        var misses: [String] = []

        for testCase in realPhrasings {
            let parsed = pipeline.parse(testCase.text)
            if parsed.intent == testCase.intent {
                correct += 1
            } else {
                misses.append("  \"\(testCase.text)\" → \(parsed.intent.rawValue), expected \(testCase.intent.rawValue)")
            }
        }

        let accuracy = Double(correct) / Double(realPhrasings.count)
        print(String(format: "REAL-PHRASING intent accuracy: %.1f%% (%d/%d)",
                     accuracy * 100, correct, realPhrasings.count))
        for miss in misses { print("   miss:\(miss)") }

        // Deliberately lower than the synthetic gate. Real speech is harder
        // than any grammar, and a bar set at the synthetic number would just be
        // a bar we'd learn to game.
        #expect(
            accuracy >= 0.80,
            """
            Real-phrasing intent accuracy \(String(format: "%.1f%%", accuracy * 100)) \
            (\(correct)/\(realPhrasings.count)). Misses:
            \(misses.joined(separator: "\n"))
            """
        )
    }

    @Test("Foods are extracted from natural phrasings")
    func foodExtraction() {
        let foodCases = realPhrasings.filter { !$0.expectedFoods.isEmpty }
        var found = 0
        var misses: [String] = []

        for testCase in foodCases {
            let parsed = pipeline.parse(testCase.text)
            let phrases = (parsed.foods.map(\.phrase) + parsed.drinks.map(\.name))
                .map { $0.lowercased() }

            // Each expected food must own a phrase, and no two may share one.
            // Checking a substring of every phrase joined together scored
            // "baguette with butter" as finding the baguette, while the app
            // resolved that span to butter and dropped the baguette entirely.
            var unclaimed = phrases
            var missing: [String] = []
            for food in testCase.expectedFoods {
                if let index = unclaimed.firstIndex(where: { Self.phrase($0, cleanlyNames: food) }) {
                    unclaimed.remove(at: index)
                } else {
                    missing.append(food)
                }
            }

            if missing.isEmpty {
                found += 1
            } else {
                misses.append("  \"\(testCase.text)\" → [\(phrases.joined(separator: " | "))], missing \(missing)")
            }
        }

        let rate = Double(found) / Double(max(1, foodCases.count))
        print(String(format: "REAL-PHRASING food extraction: %.1f%% (%d/%d)",
                     rate * 100, found, foodCases.count))
        for miss in misses { print("   miss:\(miss)") }
        #expect(
            rate >= 0.75,
            """
            Food extraction \(String(format: "%.1f%%", rate * 100)) (\(found)/\(foodCases.count)). Misses:
            \(misses.joined(separator: "\n"))
            """
        )
    }

    /// Words that join a food to its context. One inside a span means the
    /// tagger ran past the food's edge — "water after my run", "baguette with
    /// butter" — unless the expected name itself contains it.
    private static let spanLeaks: Set<String> = ["with", "and", "after", "before", "my", "for", "at", "of", "on"]

    private static func phrase(_ phrase: String, cleanlyNames food: String) -> Bool {
        let words = phrase.split(separator: " ").map(String.init)
        let expected = food.split(separator: " ").map(String.init)
        guard phrase.contains(food) else { return false }
        return words.allSatisfy { !spanLeaks.contains($0) || expected.contains($0) }
    }

    @Test("Stated quantities are read correctly")
    func quantityExtraction() {
        let quantityCases = realPhrasings.filter { $0.expectsQuantity != nil }
        var correct = 0
        var misses: [String] = []

        for testCase in quantityCases {
            let parsed = pipeline.parse(testCase.text)
            // A drink's quantity lives on the drink, not the food. Reading only
            // foods marked "two more glasses of water" as a miss while the
            // parser had it right all along.
            let quantity: Double? = parsed.foods.first?.quantity ?? parsed.drinks.first?.quantity
            let expected: Double = testCase.expectsQuantity ?? 0
            if let quantity, abs(quantity - expected) < 0.01 {
                correct += 1
            } else {
                let got: String = quantity.map { "\($0)" } ?? "nothing"
                misses.append("  \"\(testCase.text)\" → \(got), expected \(expected)")
            }
        }

        // A wrong quantity is the most damaging error the parser can make, so
        // this bar is the highest of the three.
        #expect(
            correct == quantityCases.count,
            """
            Quantity accuracy \(correct)/\(quantityCases.count). Misses:
            \(misses.joined(separator: "\n"))
            """
        )
    }

    @Test("The parser is honest about when it's unsure")
    func confidenceIsCalibrated() {
        // A clear, complete utterance should be confident.
        let clear = pipeline.parse("two slices of toast")
        // A vague one should not be.
        let vague = pipeline.parse("some stuff")

        #expect(clear.confidence > vague.confidence,
                "a specific entry should score higher than a vague one")
        #expect(!vague.uncertainties.isEmpty,
                "an unsure parse should say why")
    }
}
