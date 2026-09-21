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
        #expect(parsed.foods.count >= 2, "got \(parsed.foods.map(\.phrase))")
    }

    @Test("A compound dish name stays one food")
    func compoundStaysWhole() {
        // "macaroni and cheese" must not become macaroni plus cheese.
        let parsed = pipeline.parse("macaroni and cheese")
        #expect(parsed.foods.count == 1, "got \(parsed.foods.map(\.phrase))")
    }
}
