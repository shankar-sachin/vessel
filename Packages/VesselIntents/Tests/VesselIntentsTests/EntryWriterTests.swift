import Testing
import Foundation
import SwiftData
@testable import VesselIntents
import VesselCore
import VesselIntelligence

/// The shared save path, against an in-memory store.
@MainActor
@Suite("Writing a parse to the store")
struct EntryWriterTests {

    private let pipeline = ParsePipeline()

    /// Holds each store for the life of the test. An in-memory container that
    /// deallocates destroys every model it held, and the assertions run after
    /// `write` returns.
    private final class Stores { var all: [ModelContainer] = [] }
    private let stores = Stores()

    private func write(_ text: String) throws -> (EntryWriter.Outcome, ModelContext) {
        let container = try VesselStore.makeContainer(inMemory: true)
        stores.all.append(container)
        let outcome = EntryWriter(context: container.mainContext).write(pipeline.parse(text), source: .siri)
        return (outcome, container.mainContext)
    }

    @Test("A meal is saved with real nutrition")
    func meal() throws {
        let (outcome, _) = try write("two eggs and toast")
        let items = try #require(outcome.meal?.items)
        #expect(items.count == 2)
        #expect(items.allSatisfy { $0.nutrients.kilocalories > 0 })
        #expect(outcome.meal?.source == .siri)
    }

    @Test("Milk is food, not water")
    func milkIsFood() throws {
        // A glass of milk used to reach only the Water diary, logging no energy.
        let (outcome, _) = try write("a glass of milk")
        #expect(outcome.drinks.isEmpty, "milk should not be filed as water")
        let milk = try #require(outcome.meal?.items?.first)
        #expect(milk.nutrients.kilocalories > 80, "250 ml of milk has energy; got \(milk.nutrients.kilocalories)")
        #expect(milk.unit == .milliliter && milk.quantity == 250)
    }

    @Test("Only water goes to the Water diary")
    func waterIsWater() throws {
        let (bottle, _) = try write("a bottle of water")
        #expect(bottle.drinks.first?.volumeML == 500)
        #expect(bottle.meal == nil)
        let (sparkling, _) = try write("sparkling water with lunch")
        #expect(sparkling.drinks.count == 1 && sparkling.meal == nil)
    }

    @Test("Water with energy in it is a drink like any other")
    func tonicIsFood() throws {
        let (outcome, _) = try write("a glass of tonic water")
        #expect(outcome.drinks.isEmpty)
        #expect((outcome.meal?.items?.first?.nutrients.kilocalories ?? 0) > 0)
    }

    @Test("Coffee is food, and carries its caffeine tag")
    func coffee() throws {
        let (outcome, _) = try write("a cup of coffee")
        #expect(outcome.drinks.isEmpty)
        #expect(outcome.meal?.items?.first?.tags?.contains("caffeine") == true)
    }

    @Test("A reaction and a journal note land where they belong")
    func otherIntents() throws {
        let (symptom, _) = try write("really bloated after lunch")
        #expect(symptom.symptom?.kind == .bloating)
        let (journal, _) = try write("slept badly, felt flat all morning")
        #expect(journal.journal != nil)
    }

    @Test("The summary reads back what was saved")
    func summary() throws {
        let (outcome, _) = try write("two eggs and toast")
        #expect(outcome.summary.hasPrefix("Logged "))
        #expect(outcome.summary.contains("calories"))
    }
}
