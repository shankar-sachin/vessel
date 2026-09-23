import Testing
import Foundation
import SwiftData
@testable import VesselIntents
import VesselCore
import VesselIntelligence

/// The intents' `perform()`, run directly against an in-memory store.
///
/// Siri itself can't be driven from a test — and the simulator's Siri is
/// unreliable anyway — so this checks everything up to the system boundary:
/// that each intent writes what it says, and says what it wrote.
@MainActor
@Suite("Siri intents", .serialized)
struct IntentTests {

    private let container: ModelContainer

    init() throws {
        container = try VesselStore.makeContainer(inMemory: true)
        IntentsRuntime.container = container
        IntentsRuntime.didLog = nil
    }

    private func count<T: PersistentModel>(_ type: T.Type) -> Int {
        (try? container.mainContext.fetchCount(FetchDescriptor<T>())) ?? 0
    }

    @Test("Every symptom the app knows can be said to Siri")
    func symptomsCovered() {
        for kind in SymptomKind.allCases {
            #expect(SymptomChoice(rawValue: kind.rawValue) != nil, "\(kind) has no Siri counterpart")
        }
    }

    @Test("Water by serving, or by an exact amount")
    func water() async throws {
        _ = try await LogWaterIntent(serving: .bottle).perform()
        _ = try await LogWaterIntent(serving: .glass, millilitres: 330).perform()
        let volumes = try container.mainContext.fetch(FetchDescriptor<WaterEntry>()).map(\.volumeML).sorted()
        #expect(volumes == [330, 500])
    }

    @Test("A reaction is logged with its severity")
    func symptom() async throws {
        _ = try await LogSymptomIntent(symptom: .heartburn, severity: .strong).perform()
        let entry = try #require(try container.mainContext.fetch(FetchDescriptor<SymptomEntry>()).first)
        #expect(entry.kind == .heartburn)
        #expect(entry.severity == .strong)
    }

    @Test("A journal entry keeps its words")
    func journal() async throws {
        _ = try await AddJournalEntryIntent(text: "Long walk, felt good").perform()
        #expect(try container.mainContext.fetch(FetchDescriptor<JournalEntry>()).first?.body == "Long walk, felt good")
    }

    @Test("Free text goes through the same parser and writer as the app")
    func freeText() async throws {
        _ = try await LogIntent(text: "two slices of toast").perform()
        let meal = try #require(try container.mainContext.fetch(FetchDescriptor<FoodEntry>()).first)
        #expect(meal.source == .siri)
        #expect(meal.items?.first?.quantity == 2)
        #expect((meal.items?.first?.nutrients.kilocalories ?? 0) > 0)
    }

    @Test("An unsure parse is read back before it's saved")
    func confirmation() {
        let pipeline = ParsePipeline()
        #expect(LogIntent.needsConfirmation(pipeline.parse("an apple")),
                "a low-confidence parse must be confirmed, not saved silently")
        #expect(!LogIntent.needsConfirmation(pipeline.parse("two slices of toast")))
    }

    @Test("A question is answered, not logged")
    func question() async throws {
        _ = try await LogIntent(text: "how many calories today").perform()
        #expect(count(FoodEntry.self) == 0)
        #expect(count(JournalEntry.self) == 0)
    }

    @Test("The day's summary matches what was logged")
    func summary() async throws {
        _ = try await LogWaterIntent(serving: .bottle).perform()
        let summary = IntakeSummary.today(in: container.mainContext)
        #expect(summary.waterML == 500)
        #expect(summary.sentence.contains("0.5"))
    }

    @Test("The journal schema intent writes a real entry")
    func journalSchema() async throws {
        var intent = CreateJournalEntryIntent()
        intent.title = "Sunday"
        intent.message = AttributedString("Cooked for everyone, felt good")
        intent.mediaItems = []
        _ = try await intent.perform()
        let entry = try #require(try container.mainContext.fetch(FetchDescriptor<JournalEntry>()).first)
        #expect(entry.title == "Sunday")
        #expect(entry.body == "Cooked for everyone, felt good")
    }

    @Test("The streak hook runs after a log")
    func hook() async throws {
        var calls = 0
        IntentsRuntime.didLog = { _ in calls += 1 }
        _ = try await LogWaterIntent(serving: .glass).perform()
        #expect(calls == 1)
    }
}
