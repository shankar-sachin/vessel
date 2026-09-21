import Foundation
import SwiftData

/// A complete, portable copy of everything Vessel holds.
///
/// Vessel stores your health history only on your device, which is good for
/// privacy and bad for everything else: a lost phone loses months of data with
/// nothing to restore from. Export is the safety net that makes local-first
/// storage a reasonable choice rather than a reckless one.
///
/// The format is plain JSON on purpose. It should be readable and usable by
/// something other than Vessel — it's the user's data, not ours.
public struct VesselArchive: Codable, Sendable {

    /// Bumped when the shape changes incompatibly. Import refuses anything newer
    /// than it understands rather than silently dropping fields.
    public static let currentFormatVersion = 1

    public let formatVersion: Int
    public let exportedAt: Date
    public let appVersion: String

    public var profile: ProfileDTO?
    public var foodEntries: [FoodEntryDTO]
    public var waterEntries: [WaterEntryDTO]
    public var journalEntries: [JournalEntryDTO]
    public var symptomEntries: [SymptomEntryDTO]
    public var learnedAliases: [LearnedAliasDTO]

    public init(
        formatVersion: Int = VesselArchive.currentFormatVersion,
        exportedAt: Date = Date(),
        appVersion: String = "1.0.0",
        profile: ProfileDTO? = nil,
        foodEntries: [FoodEntryDTO] = [],
        waterEntries: [WaterEntryDTO] = [],
        journalEntries: [JournalEntryDTO] = [],
        symptomEntries: [SymptomEntryDTO] = [],
        learnedAliases: [LearnedAliasDTO] = []
    ) {
        self.formatVersion = formatVersion
        self.exportedAt = exportedAt
        self.appVersion = appVersion
        self.profile = profile
        self.foodEntries = foodEntries
        self.waterEntries = waterEntries
        self.journalEntries = journalEntries
        self.symptomEntries = symptomEntries
        self.learnedAliases = learnedAliases
    }

    public var totalEntryCount: Int {
        foodEntries.count + waterEntries.count + journalEntries.count + symptomEntries.count
    }
}

// MARK: - Transfer objects
//
// Kept separate from the `@Model` classes rather than making those Codable.
// The persisted shape is free to change for storage reasons; the archive format
// is a contract with the user's exported files and changes only deliberately.

public struct FoodEntryDTO: Codable, Sendable {
    public var id: UUID
    public var loggedAt: Date
    public var slot: String
    public var source: String
    public var rawInput: String?
    public var parseConfidence: Double
    public var note: String?
    public var items: [FoodItemDTO]
    /// Base64 photo, omitted unless images were requested.
    public var photoBase64: String?
}

public struct FoodItemDTO: Codable, Sendable {
    public var id: UUID
    public var foodID: String?
    public var displayName: String
    public var brand: String?
    public var quantity: Double
    public var unit: String
    public var grams: Double?
    public var nutrients: Nutrients
    public var tags: [String]
}

public struct WaterEntryDTO: Codable, Sendable {
    public var id: UUID
    public var loggedAt: Date
    public var volumeML: Double
    public var source: String
    public var containerName: String?
    public var containsCaffeine: Bool
    public var containsAlcohol: Bool
}

public struct JournalEntryDTO: Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var title: String?
    public var body: String
    public var mood: Int?
    public var tags: [String]
    public var imageBase64: String?
}

public struct SymptomEntryDTO: Codable, Sendable {
    public var id: UUID
    public var occurredAt: Date
    public var loggedAt: Date
    public var kind: String
    public var severity: Int
    public var note: String?
    public var durationMinutes: Int?
    public var suspectedFoodEntryIDs: [UUID]
}

public struct ProfileDTO: Codable, Sendable {
    public var fastingPlan: FastingPlan
    public var goals: DailyGoals
    public var unitSystem: String
    public var dayRolloverHour: Int
    public var streakWarningLeadHours: Double
    public var allowedRestDaysPerWeek: Int
    public var liveActivityEnabled: Bool
    public var streakReminderEnabled: Bool
    public var countsFoodWaterTowardHydration: Bool
}

public struct LearnedAliasDTO: Codable, Sendable {
    public var id: UUID
    public var phrase: String
    public var foodID: String
    public var displayName: String
    public var confirmations: Int
    public var rejections: Int
}

// MARK: - Export / import

public enum ArchiveError: LocalizedError, Equatable {
    case unsupportedVersion(found: Int, supported: Int)
    case malformed(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let found, let supported):
            return "This backup was made by a newer version of Vessel (format \(found); this version reads up to \(supported)). Update Vessel and try again."
        case .malformed(let detail):
            return "That file doesn't look like a Vessel backup. \(detail)"
        }
    }
}

public enum ArchiveService {

    /// Result of importing, so the UI can report what actually happened rather
    /// than a bare "done".
    public struct ImportSummary: Sendable, Equatable {
        public var added = 0
        public var skipped = 0
        public var profileRestored = false

        public init(added: Int = 0, skipped: Int = 0, profileRestored: Bool = false) {
            self.added = added
            self.skipped = skipped
            self.profileRestored = profileRestored
        }
    }

    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // ISO-8601 so timestamps are legible and unambiguous outside Vessel.
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    // MARK: Export

    @MainActor
    public static func export(from context: ModelContext, includingImages: Bool = true) throws -> VesselArchive {
        var archive = VesselArchive()

        let foods = (try? context.fetch(FetchDescriptor<FoodEntry>(sortBy: [SortDescriptor(\.loggedAt)]))) ?? []
        archive.foodEntries = foods.map { entry in
            FoodEntryDTO(
                id: entry.id,
                loggedAt: entry.loggedAt,
                slot: entry.slotRaw,
                source: entry.sourceRaw,
                rawInput: entry.rawInput,
                parseConfidence: entry.parseConfidence,
                note: entry.note,
                items: entry.resolvedItems.map { item in
                    FoodItemDTO(
                        id: item.id,
                        foodID: item.foodID,
                        displayName: item.displayName,
                        brand: item.brand,
                        quantity: item.quantity,
                        unit: item.unitRaw,
                        grams: item.grams,
                        nutrients: item.nutrients,
                        tags: item.resolvedTags
                    )
                },
                photoBase64: includingImages ? entry.photoData?.base64EncodedString() : nil
            )
        }

        let waters = (try? context.fetch(FetchDescriptor<WaterEntry>(sortBy: [SortDescriptor(\.loggedAt)]))) ?? []
        archive.waterEntries = waters.map {
            WaterEntryDTO(
                id: $0.id, loggedAt: $0.loggedAt, volumeML: $0.volumeML, source: $0.sourceRaw,
                containerName: $0.containerName, containsCaffeine: $0.containsCaffeine,
                containsAlcohol: $0.containsAlcohol
            )
        }

        let journals = (try? context.fetch(FetchDescriptor<JournalEntry>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        archive.journalEntries = journals.map {
            JournalEntryDTO(
                id: $0.id, createdAt: $0.createdAt, updatedAt: $0.updatedAt, title: $0.title,
                body: $0.body, mood: $0.moodRaw, tags: $0.resolvedTags,
                imageBase64: includingImages ? $0.imageData?.base64EncodedString() : nil
            )
        }

        let symptoms = (try? context.fetch(FetchDescriptor<SymptomEntry>(sortBy: [SortDescriptor(\.occurredAt)]))) ?? []
        archive.symptomEntries = symptoms.map {
            SymptomEntryDTO(
                id: $0.id, occurredAt: $0.occurredAt, loggedAt: $0.loggedAt, kind: $0.kindRaw,
                severity: $0.severityRaw, note: $0.note, durationMinutes: $0.durationMinutes,
                suspectedFoodEntryIDs: $0.suspectedFoodEntryIDs ?? []
            )
        }

        let aliases = (try? context.fetch(FetchDescriptor<LearnedAlias>())) ?? []
        archive.learnedAliases = aliases.map {
            LearnedAliasDTO(
                id: $0.id, phrase: $0.phrase, foodID: $0.foodID, displayName: $0.displayName,
                confirmations: $0.confirmations, rejections: $0.rejections
            )
        }

        if let profile = try? context.fetch(FetchDescriptor<UserProfile>(sortBy: [SortDescriptor(\.createdAt)])).first {
            archive.profile = ProfileDTO(
                fastingPlan: profile.fastingPlan,
                goals: profile.goals,
                unitSystem: profile.unitSystemRaw,
                dayRolloverHour: profile.dayRolloverHour,
                streakWarningLeadHours: profile.streakWarningLeadHours,
                allowedRestDaysPerWeek: profile.allowedRestDaysPerWeek,
                liveActivityEnabled: profile.liveActivityEnabled,
                streakReminderEnabled: profile.streakReminderEnabled,
                countsFoodWaterTowardHydration: profile.countsFoodWaterTowardHydration
            )
        }

        return archive
    }

    @MainActor
    public static func exportData(from context: ModelContext, includingImages: Bool = true) throws -> Data {
        try makeEncoder().encode(export(from: context, includingImages: includingImages))
    }

    // MARK: Import

    /// Merges an archive into the store.
    ///
    /// Merge, not replace: entries already present (matched by id) are left
    /// alone rather than duplicated, so importing the same file twice is
    /// harmless and importing an old backup alongside newer data doesn't
    /// destroy the newer data. Restoring onto a wiped device and merging two
    /// devices' histories are the same operation.
    @MainActor
    @discardableResult
    public static func importArchive(
        _ archive: VesselArchive,
        into context: ModelContext,
        restoringSettings: Bool = true
    ) throws -> ImportSummary {
        guard archive.formatVersion <= VesselArchive.currentFormatVersion else {
            throw ArchiveError.unsupportedVersion(
                found: archive.formatVersion,
                supported: VesselArchive.currentFormatVersion
            )
        }

        var summary = ImportSummary()

        let existingFood = Set(((try? context.fetch(FetchDescriptor<FoodEntry>())) ?? []).map(\.id))
        for dto in archive.foodEntries where !existingFood.contains(dto.id) {
            let entry = FoodEntry(
                id: dto.id,
                loggedAt: dto.loggedAt,
                slot: MealSlot(rawValue: dto.slot) ?? .snack,
                source: EntrySource(rawValue: dto.source) ?? .manual,
                rawInput: dto.rawInput,
                parseConfidence: dto.parseConfidence,
                note: dto.note
            )
            entry.photoData = dto.photoBase64.flatMap { Data(base64Encoded: $0) }
            context.insert(entry)

            entry.items = dto.items.map { itemDTO in
                let item = FoodItem(
                    id: itemDTO.id,
                    foodID: itemDTO.foodID,
                    displayName: itemDTO.displayName,
                    brand: itemDTO.brand,
                    quantity: itemDTO.quantity,
                    unit: MeasurementUnit(rawValue: itemDTO.unit) ?? .serving,
                    grams: itemDTO.grams,
                    nutrients: itemDTO.nutrients,
                    tags: itemDTO.tags
                )
                context.insert(item)
                return item
            }
            summary.added += 1
        }
        summary.skipped += archive.foodEntries.count - (archive.foodEntries.filter { !existingFood.contains($0.id) }.count)

        let existingWater = Set(((try? context.fetch(FetchDescriptor<WaterEntry>())) ?? []).map(\.id))
        for dto in archive.waterEntries where !existingWater.contains(dto.id) {
            context.insert(WaterEntry(
                id: dto.id, loggedAt: dto.loggedAt, volumeML: dto.volumeML,
                source: EntrySource(rawValue: dto.source) ?? .manual,
                containerName: dto.containerName,
                containsCaffeine: dto.containsCaffeine, containsAlcohol: dto.containsAlcohol
            ))
            summary.added += 1
        }
        summary.skipped += archive.waterEntries.filter { existingWater.contains($0.id) }.count

        let existingJournal = Set(((try? context.fetch(FetchDescriptor<JournalEntry>())) ?? []).map(\.id))
        for dto in archive.journalEntries where !existingJournal.contains(dto.id) {
            let entry = JournalEntry(
                id: dto.id, createdAt: dto.createdAt, title: dto.title, body: dto.body,
                mood: dto.mood.flatMap(Mood.init(rawValue:)), tags: dto.tags
            )
            entry.updatedAt = dto.updatedAt
            entry.imageData = dto.imageBase64.flatMap { Data(base64Encoded: $0) }
            context.insert(entry)
            summary.added += 1
        }
        summary.skipped += archive.journalEntries.filter { existingJournal.contains($0.id) }.count

        let existingSymptom = Set(((try? context.fetch(FetchDescriptor<SymptomEntry>())) ?? []).map(\.id))
        for dto in archive.symptomEntries where !existingSymptom.contains(dto.id) {
            let entry = SymptomEntry(
                id: dto.id, occurredAt: dto.occurredAt,
                kind: SymptomKind(rawValue: dto.kind) ?? .other,
                severity: Severity(rawValue: dto.severity) ?? .moderate,
                note: dto.note, durationMinutes: dto.durationMinutes,
                suspectedFoodEntryIDs: dto.suspectedFoodEntryIDs
            )
            entry.loggedAt = dto.loggedAt
            context.insert(entry)
            summary.added += 1
        }
        summary.skipped += archive.symptomEntries.filter { existingSymptom.contains($0.id) }.count

        let existingAliases = Set(((try? context.fetch(FetchDescriptor<LearnedAlias>())) ?? []).map(\.id))
        for dto in archive.learnedAliases where !existingAliases.contains(dto.id) {
            let alias = LearnedAlias(
                id: dto.id, phrase: dto.phrase, foodID: dto.foodID, displayName: dto.displayName
            )
            alias.confirmations = dto.confirmations
            alias.rejections = dto.rejections
            context.insert(alias)
        }

        if restoringSettings, let dto = archive.profile {
            let profile = UserProfile.current(in: context)
            profile.fastingPlan = dto.fastingPlan
            profile.goals = dto.goals
            profile.unitSystemRaw = dto.unitSystem
            profile.dayRolloverHour = dto.dayRolloverHour
            profile.streakWarningLeadHours = dto.streakWarningLeadHours
            profile.allowedRestDaysPerWeek = dto.allowedRestDaysPerWeek
            profile.liveActivityEnabled = dto.liveActivityEnabled
            profile.streakReminderEnabled = dto.streakReminderEnabled
            profile.countsFoodWaterTowardHydration = dto.countsFoodWaterTowardHydration
            summary.profileRestored = true
        }

        try context.save()
        return summary
    }

    @MainActor
    @discardableResult
    public static func importData(
        _ data: Data,
        into context: ModelContext,
        restoringSettings: Bool = true
    ) throws -> ImportSummary {
        let archive: VesselArchive
        do {
            archive = try makeDecoder().decode(VesselArchive.self, from: data)
        } catch let error as DecodingError {
            throw ArchiveError.malformed(Self.describe(error))
        }
        return try importArchive(archive, into: context, restoringSettings: restoringSettings)
    }

    /// Turns a `DecodingError` into something a person can act on.
    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, _):   return "A required field (\(key.stringValue)) is missing."
        case .typeMismatch(_, let ctx):  return "A field has the wrong type at \(ctx.codingPath.map(\.stringValue).joined(separator: "."))."
        case .valueNotFound(_, let ctx): return "A required value is empty at \(ctx.codingPath.map(\.stringValue).joined(separator: "."))."
        case .dataCorrupted:             return "The file isn't valid JSON."
        @unknown default:                return "It couldn't be read."
        }
    }
}
