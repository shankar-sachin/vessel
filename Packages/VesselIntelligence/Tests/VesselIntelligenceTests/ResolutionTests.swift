import Testing
@testable import VesselIntelligence

/// Parse all the way to grams, the number that is actually logged.
@Suite("Resolution to a weight")
struct ResolutionTests {

    private let pipeline = ParsePipeline()
    private let resolver = EntryResolver()

    private func resolved(_ text: String) -> [EntryResolver.ResolvedFood] {
        resolver.resolve(pipeline.parse(text))
    }

    @Test("A bare count is never read as grams")
    func countsAreNotGrams() throws {
        // "a quarter of a melon" was logged as 0.25 g and 0 kcal: the chosen
        // row had no portion data, and a unitless count fell back to grams.
        let melon = try #require(resolved("a quarter of a melon").first)
        #expect((melon.grams ?? 0) > 20, "got \(melon.grams ?? 0) g of \(melon.food?.name ?? "nothing")")
        #expect(melon.nutrients.kilocalories > 0)

        let eggs = try #require(resolved("two eggs").first)
        #expect((eggs.grams ?? 0) >= 80, "got \(eggs.grams ?? 0) g of \(eggs.food?.name ?? "nothing")")
    }

    @Test("Two foods joined by 'with' both resolve")
    func withResolvesBoth() {
        let foods = resolved("toast with jam").compactMap(\.food)
        #expect(foods.count == 2, "got \(foods.map(\.name))")
    }
}
