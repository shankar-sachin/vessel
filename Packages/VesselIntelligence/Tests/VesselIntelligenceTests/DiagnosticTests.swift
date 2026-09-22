import Testing
import Foundation
@testable import VesselIntelligence

/// Regression tests for parses that were once wrong in ways nobody would
/// notice from a passing build.

@Suite("Multi-food parsing")
struct MultiFoodTests {

    private let pipeline = ParsePipeline()

    private func foods(_ text: String) -> [String] {
        pipeline.parse(text).foods.map(\.phrase)
    }

    @Test("A bare food at the start of a sentence isn't dropped")
    func bareLeadingFoodSurvives() {
        // This regressed silently: the corpus almost always opened with a
        // lead-in or a quantity, so the tagger learned that the first token of
        // a sentence is filler — and quietly threw away the eggs in "eggs and
        // toast", one of the most ordinary phrasings there is.
        #expect(foods("eggs and toast").count == 2, "got \(foods("eggs and toast"))")
        #expect(foods("porridge and a banana").count == 2)
        #expect(foods("chicken salad").count == 1)
    }

    @Test("A quantity before the first food still splits correctly")
    func quantifiedFoodsSplit() {
        let parsed = pipeline.parse("two eggs and toast")
        #expect(parsed.foods.count == 2, "got \(parsed.foods.map(\.phrase))")
        #expect(parsed.foods.first?.quantity == 2)
        // The quantity belongs to the eggs, not to the toast.
        #expect(parsed.foods.last?.quantity == nil)
    }

    @Test("Three foods in one sentence all survive")
    func threeFoods() {
        let parsed = pipeline.parse("eggs, toast and a banana")
        #expect(parsed.foods.map(\.phrase) == ["eggs", "toast", "banana"],
                "got \(parsed.foods.map(\.phrase))")
    }

    @Test("'with' between two foods makes two foods")
    func withSeparatesFoods() {
        // The tagger labelled these correctly all along — FOOD, NONE, FOOD —
        // and assembly glued them back together, so "baguette with butter"
        // resolved to butter and the baguette was never logged.
        #expect(foods("half a baguette with butter") == ["baguette", "butter"])
        #expect(foods("had a bowl of porridge with berries this morning") == ["porridge", "berries"])
        #expect(foods("chicken tikka masala with naan") == ["chicken tikka masala", "naan"])
    }

    @Test("A comma separates foods without turning into a word")
    func commaSeparates() {
        #expect(pipeline.parse("porridge, black coffee").drinks.map(\.name) == ["black coffee"]
                || foods("porridge, black coffee").count == 2)
        // But a trailing detail stays with its food, and a pause is nothing.
        let scrambled = pipeline.parse("two eggs, scrambled")
        #expect(scrambled.foods.count == 1, "got \(scrambled.foods.map(\.phrase))")
        #expect(pipeline.parse("um, like, two eggs").foods.map(\.phrase) == ["eggs"])
    }

    @Test("A drink named alongside a meal is kept")
    func drinkInAMeal() {
        let parsed = pipeline.parse("croissant and a flat white")
        #expect(parsed.foods.map(\.phrase) == ["croissant"])
        #expect(parsed.drinks.map(\.name) == ["flat white"])
    }

    @Test("A drink is never also logged as a food spanning the sentence")
    func drinkIsNotAFood() {
        // The segment fallback used to turn this into a food named for the
        // whole sentence, which the resolver matched to tonic water.
        let parsed = pipeline.parse("bottle of water after my run")
        #expect(parsed.intent == .logWater)
        #expect(parsed.foods.isEmpty, "got \(parsed.foods.map(\.phrase))")
        #expect(parsed.drinks.map(\.name) == ["water"])
    }

    @Test("The vessel sets the volume, not the name")
    func vesselVolume() {
        // "bottle" is tagged UNIT, so it never reached the name that
        // `DrinkVolume` reads — a bottle of water was logged as a 250 ml glass.
        #expect(pipeline.parse("bottle of water after my run").drinks.first?.millilitres == 500)
        let glass = pipeline.parse("glass of water").drinks.first
        #expect(glass?.name == "water")
        #expect(glass?.millilitres == 250)
    }

    @Test("A compound dish name stays one food")
    func compoundStaysWhole() {
        // "macaroni and cheese" must not become macaroni plus cheese.
        let parsed = pipeline.parse("macaroni and cheese")
        #expect(parsed.foods.count == 1, "got \(parsed.foods.map(\.phrase))")
    }
}
