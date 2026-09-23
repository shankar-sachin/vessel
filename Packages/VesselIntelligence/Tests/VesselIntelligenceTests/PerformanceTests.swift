import Testing
import Foundation
@testable import VesselIntelligence
import VesselNutrition

/// Budgets for the work done on every keystroke.
///
/// Quick log re-parses 180 ms after typing stops, so parsing, resolving and
/// searching together have to fit comfortably inside that on a phone. Measured
/// on an M-series Mac in release: parse 0.2 ms, parse + resolve 3.4 ms, a
/// search 5 ms. The budgets below allow for a debug build and a slower device,
/// and exist to catch a regression by an order of magnitude — a ranker change
/// that scans the whole table, say — not to benchmark.
@Suite("Performance budgets", .serialized)
struct PerformanceTests {

    private static func p95(_ runs: Int, _ work: () -> Void) -> Double {
        work()  // warm caches and the database handle
        let times = (0..<runs).map { _ -> Double in
            let start = Date()
            work()
            return Date().timeIntervalSince(start) * 1000
        }.sorted()
        return times[Int(Double(runs) * 0.95)]
    }

    @Test("Parsing an utterance stays under 20 ms")
    func parse() {
        let pipeline = ParsePipeline()
        let ms = Self.p95(40) { _ = pipeline.parse("a bowl of porridge with berries and a coffee") }
        #expect(ms < 20, "p95 \(ms) ms")
    }

    @Test("Parse and resolve stays under 100 ms")
    func resolve() {
        let pipeline = ParsePipeline()
        let resolver = EntryResolver()
        let ms = Self.p95(20) { _ = resolver.resolve(pipeline.parse("grilled chicken breast and rice")) }
        #expect(ms < 100, "p95 \(ms) ms")
    }

    @Test("A food search stays under 60 ms")
    func search() {
        let search = FoodSearch()
        let ms = Self.p95(30) { _ = search.search("chicken") }
        #expect(ms < 60, "p95 \(ms) ms")
    }
}
