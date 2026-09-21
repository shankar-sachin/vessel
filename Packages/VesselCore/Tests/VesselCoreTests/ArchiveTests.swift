import Testing
import Foundation
import SwiftData
@testable import VesselCore

/// Export and import are the only thing standing between a lost phone and a
/// lost year of health data, so they're tested for *fidelity*, not just for
/// "didn't throw".

@MainActor
private func makeContext() throws -> ModelContext {
    let container = try ModelContainer(
        for: VesselStore.schema,
        configurations: [ModelConfiguration(schema: VesselStore.schema, isStoredInMemoryOnly: true)]
    )
    return ModelContext(container)
}

@Suite("Archive round trip")
@MainActor
struct ArchiveRoundTripTests {

    @Test("A full database survives export and re-import into an empty store")
    func fullRoundTrip() throws {
        let source = try makeContext()
        SampleData.seed(into: source)

        let originalFood = try source.fetchCount(FetchDescriptor<FoodEntry>())
        let originalWater = try source.fetchCount(FetchDescriptor<WaterEntry>())
        let originalJournal = try source.fetchCount(FetchDescriptor<JournalEntry>())
        let originalSymptom = try source.fetchCount(FetchDescriptor<SymptomEntry>())

        let data = try ArchiveService.exportData(from: source)

        let destination = try makeContext()
        let summary = try ArchiveService.importData(data, into: destination)

        #expect(summary.added == originalFood + originalWater + originalJournal + originalSymptom)
        #expect(try destination.fetchCount(FetchDescriptor<FoodEntry>()) == originalFood)
        #expect(try destination.fetchCount(FetchDescriptor<WaterEntry>()) == originalWater)
        #expect(try destination.fetchCount(FetchDescriptor<JournalEntry>()) == originalJournal)
        #expect(try destination.fetchCount(FetchDescriptor<SymptomEntry>()) == originalSymptom)
    }

    @Test("Nutrition values survive exactly, not approximately")
    func nutrientFidelity() throws {
        let source = try makeContext()
        let entry = FoodEntry(loggedAt: Date(), slot: .lunch, source: .voice, rawInput: "test meal")
        let nutrients = Nutrients(
            kilocalories: 273.5, proteinG: 51.25, carbohydrateG: 46.75, fatG: 6.125,
            fiberG: 3.5, sugarG: 1.25, sodiumMG: 125.5, potassiumMG: 400, waterML: 105.75
        )
        entry.items = [FoodItem(
            foodID: "fdc:171705", displayName: "Chicken breast", brand: "Store",
            quantity: 165, unit: .gram, grams: 165, nutrients: nutrients, tags: ["poultry", "lean"]
        )]
        source.insert(entry)
        try source.save()

        let data = try ArchiveService.exportData(from: source)
        let destination = try makeContext()
        try ArchiveService.importData(data, into: destination)

        let restored = try #require(try destination.fetch(FetchDescriptor<FoodEntry>()).first)
        let item = try #require(restored.resolvedItems.first)

        // Whole-value equality: a silently dropped micronutrient is exactly the
        // kind of bug an "it imported fine" check would miss.
        #expect(item.nutrients == nutrients)
        #expect(item.foodID == "fdc:171705")
        #expect(item.brand == "Store")
        #expect(item.quantity == 165)
        #expect(item.unit == .gram)
        #expect(item.resolvedTags == ["poultry", "lean"])
        #expect(restored.rawInput == "test meal")
        #expect(restored.slot == .lunch)
        #expect(restored.source == .voice)
    }

    @Test("Timestamps survive to the second")
    func timestampFidelity() throws {
        let source = try makeContext()
        // A time with no sub-second component, since ISO-8601 encoding drops it —
        // asserting otherwise would be testing a guarantee we don't make.
        let occurred = Date(timeIntervalSince1970: 1_780_000_000)
        source.insert(SymptomEntry(
            occurredAt: occurred, kind: .bloating, severity: .strong,
            note: "two hours after dinner", durationMinutes: 95
        ))
        try source.save()

        let data = try ArchiveService.exportData(from: source)
        let destination = try makeContext()
        try ArchiveService.importData(data, into: destination)

        let restored = try #require(try destination.fetch(FetchDescriptor<SymptomEntry>()).first)
        #expect(restored.occurredAt == occurred)
        #expect(restored.kind == .bloating)
        #expect(restored.severity == .strong)
        #expect(restored.durationMinutes == 95)
        #expect(restored.note == "two hours after dinner")
    }

    @Test("Settings come back with the data")
    func settingsRestored() throws {
        let source = try makeContext()
        let profile = UserProfile.current(in: source)
        profile.fastingPlan = .sixteenEight
        profile.goals = DailyGoals(kilocalories: 2400, proteinG: 150, waterML: 3000)
        profile.dayRolloverHour = 4
        profile.allowedRestDaysPerWeek = 1
        try source.save()

        let data = try ArchiveService.exportData(from: source)
        let destination = try makeContext()
        let summary = try ArchiveService.importData(data, into: destination)

        #expect(summary.profileRestored)
        let restored = UserProfile.current(in: destination)
        #expect(restored.fastingPlan.style == .timeRestricted)
        #expect(restored.fastingPlan.eatingWindowHours == 8)
        #expect(restored.goals.kilocalories == 2400)
        #expect(restored.dayRolloverHour == 4)
        #expect(restored.allowedRestDaysPerWeek == 1)
    }
}

@Suite("Archive merge behaviour")
@MainActor
struct ArchiveMergeTests {

    @Test("Importing the same file twice adds nothing the second time")
    func importIsIdempotent() throws {
        let source = try makeContext()
        SampleData.seed(into: source)
        let data = try ArchiveService.exportData(from: source)

        let destination = try makeContext()
        let first = try ArchiveService.importData(data, into: destination)
        let countAfterFirst = try destination.fetchCount(FetchDescriptor<FoodEntry>())

        let second = try ArchiveService.importData(data, into: destination)

        // This is what makes folder-based backup safe to run on every launch.
        #expect(first.added > 0)
        #expect(second.added == 0)
        #expect(second.skipped > 0)
        #expect(try destination.fetchCount(FetchDescriptor<FoodEntry>()) == countAfterFirst)
    }

    @Test("Merging preserves entries the incoming file doesn't have")
    func mergeKeepsLocalData() throws {
        let source = try makeContext()
        source.insert(FoodEntry(loggedAt: Date(), slot: .breakfast, source: .manual, note: "from phone"))
        try source.save()
        let data = try ArchiveService.exportData(from: source)

        let destination = try makeContext()
        destination.insert(FoodEntry(loggedAt: Date(), slot: .dinner, source: .manual, note: "from iPad"))
        try destination.save()

        try ArchiveService.importData(data, into: destination)

        // Two devices' histories must union, not overwrite.
        let notes = try destination.fetch(FetchDescriptor<FoodEntry>()).compactMap(\.note).sorted()
        #expect(notes == ["from iPad", "from phone"])
    }

    @Test("Settings can be left alone when merging another device's file")
    func mergeCanSkipSettings() throws {
        let source = try makeContext()
        let sourceProfile = UserProfile.current(in: source)
        sourceProfile.goals = DailyGoals(kilocalories: 9999, waterML: 1000)
        try source.save()
        let data = try ArchiveService.exportData(from: source)

        let destination = try makeContext()
        let localProfile = UserProfile.current(in: destination)
        localProfile.goals = DailyGoals(kilocalories: 2200, waterML: 2500)
        try destination.save()

        try ArchiveService.importData(data, into: destination, restoringSettings: false)

        // An iPad's backup must not silently rewrite the iPhone's goals.
        #expect(UserProfile.current(in: destination).goals.kilocalories == 2200)
    }
}

@Suite("Archive errors")
@MainActor
struct ArchiveErrorTests {

    @Test("A future format version is refused rather than partially read")
    func futureVersionRejected() throws {
        let archive = VesselArchive(formatVersion: VesselArchive.currentFormatVersion + 1)
        let data = try ArchiveService.makeEncoder().encode(archive)
        let context = try makeContext()

        #expect(throws: ArchiveError.self) {
            try ArchiveService.importData(data, into: context)
        }
    }

    @Test("Garbage input reports a readable error instead of crashing")
    func malformedInputRejected() throws {
        let context = try makeContext()
        let data = Data("this is definitely not a backup".utf8)

        #expect(throws: ArchiveError.self) {
            try ArchiveService.importData(data, into: context)
        }
    }
}
