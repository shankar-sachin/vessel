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
    /// Expected quantity on the first food, when the phrasing states one.
    let expectsQuantity: Double?

    init(_ text: String, _ intent: ParsedEntry.Intent, food: String? = nil, quantity: Double? = nil) {
        self.text = text
        self.intent = intent
        self.expectsFood = food
        self.expectsQuantity = quantity
    }
}

private let realPhrasings: [Case] = [
    // Everyday food logging, phrased naturally
    Case("had a bowl of porridge with berries this morning", .logFood, food: "porridge"),
    Case("two slices of toast and a boiled egg", .logFood, food: "toast", quantity: 2),
    Case("just finished a chicken salad", .logFood, food: "chicken"),
    Case("grabbed a banana on the way out", .logFood, food: "banana"),
    Case("leftover curry for lunch", .logFood, food: "curry"),
    Case("big bowl of pasta last night", .logFood, food: "pasta"),
    Case("half an avocado on sourdough", .logFood, food: "avocado", quantity: 0.5),
    Case("three scrambled eggs", .logFood, food: "eggs", quantity: 3),
    Case("a handful of almonds", .logFood, food: "almonds"),
    Case("roast chicken and potatoes for dinner", .logFood, food: "chicken"),
    Case("bowl of cereal", .logFood, food: "cereal"),
    Case("chicken breast with rice and broccoli", .logFood, food: "chicken"),
    Case("couple of biscuits with my tea", .logFood, food: "biscuits"),
    Case("greek yogurt and honey", .logFood, food: "yogurt"),
    Case("slice of cheesecake, was very good", .logFood, food: "cheesecake"),
    Case("1.5 cups of cooked quinoa", .logFood, food: "quinoa", quantity: 1.5),
    Case("some leftover pizza around 11", .logFood, food: "pizza"),
    Case("peanut butter on toast before the gym", .logFood, food: "toast"),
    Case("steak and salad", .logFood, food: "steak"),
    Case("a few crackers with cheese", .logFood, food: "crackers"),

    // Drinks
    Case("glass of water", .logWater),
    Case("just had a coffee", .logWater),
    Case("drank about a litre of water this morning", .logWater),
    Case("two cups of green tea", .logWater),
    Case("a big glass of orange juice", .logWater),
    Case("sparkling water with lunch", .logWater),
    Case("another coffee", .logWater),
    Case("bottle of water after my run", .logWater),

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
    Case("porridge, black coffee", .logFood, food: "porridge"),
    Case("had seconds of the lasagne", .logFood, food: "lasagne"),
    Case("downed a pint of water", .logWater),
    Case("herbal tea before bed", .logWater),
    Case("half a litre of water", .logWater),
    Case("guts are churning", .logSymptom),
    Case("skin has flared up again", .logSymptom),
    Case("bit windy after that", .logSymptom),
    Case("slept badly, felt flat all morning", .journalEntry),
    Case("nothing much to report today", .journalEntry),
    Case("how am I doing on protein", .query),
    Case("what was my dinner on Tuesday", .query),
    Case("sorry I meant the large one", .correction)
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
        let foodCases = realPhrasings.filter { $0.expectsFood != nil }
        var found = 0
        var misses: [String] = []

        for testCase in foodCases {
            let parsed = pipeline.parse(testCase.text)
            let phrases = (parsed.foods.map(\.phrase) + parsed.drinks.map(\.name))
                .joined(separator: " | ")
                .lowercased()

            if phrases.contains(testCase.expectsFood!.lowercased()) {
                found += 1
            } else {
                misses.append("  \"\(testCase.text)\" → [\(phrases)], expected '\(testCase.expectsFood!)'")
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

    @Test("Stated quantities are read correctly")
    func quantityExtraction() {
        let quantityCases = realPhrasings.filter { $0.expectsQuantity != nil }
        var correct = 0
        var misses: [String] = []

        for testCase in quantityCases {
            let parsed = pipeline.parse(testCase.text)
            let quantity: Double? = parsed.foods.first?.quantity
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
