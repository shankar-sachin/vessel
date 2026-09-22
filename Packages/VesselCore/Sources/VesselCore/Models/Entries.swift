import Foundation
import SwiftData

// Every model here follows the rules that keep a SwiftData schema CloudKit-ready,
// even though sync is off today:
//
//   • every stored property has a default value or is optional
//   • no `.unique` attributes (CloudKit cannot enforce uniqueness)
//   • every relationship is optional and has an explicit inverse
//   • `id` is a plain UUID we assign, not a database-generated identity
//
// Following them now costs nothing. Retrofitting them later means a schema
// migration on a database full of someone's health history.

/// One eating occasion — a meal or a snack, containing one or more foods.
@Model
public final class FoodEntry {
    public var id: UUID = UUID()
    public var loggedAt: Date = Date()
    public var slotRaw: String = MealSlot.snack.rawValue
    public var sourceRaw: String = EntrySource.manual.rawValue

    /// What the user actually said or typed, kept verbatim.
    ///
    /// Worth its storage twice over: it lets the user see why we parsed something
    /// the way we did, and it gives us real-world examples to improve the parser
    /// against — the app's own logs become its evaluation set.
    public var rawInput: String?

    /// Our parser's confidence, 0...1. Low values get a "check this" affordance.
    public var parseConfidence: Double = 1.0

    /// Set when the user edited what the parser produced. These are the training
    /// signal for the personal ranker.
    public var wasCorrectedByUser: Bool = false

    public var note: String?

    /// Photo of the meal, stored externally so the database file stays small and
    /// queries stay fast.
    @Attribute(.externalStorage) public var photoData: Data?

    @Relationship(deleteRule: .cascade, inverse: \FoodItem.entry)
    public var items: [FoodItem]? = []

    public init(
        id: UUID = UUID(),
        loggedAt: Date = Date(),
        slot: MealSlot = .snack,
        source: EntrySource = .manual,
        rawInput: String? = nil,
        parseConfidence: Double = 1.0,
        note: String? = nil
    ) {
        self.id = id
        self.loggedAt = loggedAt
        self.slotRaw = slot.rawValue
        self.sourceRaw = source.rawValue
        self.rawInput = rawInput
        self.parseConfidence = parseConfidence
        self.note = note
        self.items = []
    }

    // Raw strings are what's persisted (enums aren't CloudKit-safe as stored
    // types), but nothing outside this file should have to know that.
    public var slot: MealSlot {
        get { MealSlot(rawValue: slotRaw) ?? .snack }
        set { slotRaw = newValue.rawValue }
    }

    public var source: EntrySource {
        get { EntrySource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    public var resolvedItems: [FoodItem] { items ?? [] }

    /// Total nutrition across every item in the entry.
    public var totalNutrients: Nutrients {
        Nutrients.sum(resolvedItems.map(\.nutrients))
    }

    /// A short summary for lists and the Dynamic Island, e.g. "Eggs, toast +1".
    public var summary: String {
        let names = resolvedItems.map(\.displayName)
        switch names.count {
        case 0: return note ?? "Empty entry"
        case 1, 2: return names.joined(separator: ", ")
        default: return "\(names[0]), \(names[1]) +\(names.count - 2)"
        }
    }

    /// Flags an entry worth a second look before it pollutes the correlation data.
    public var needsReview: Bool {
        parseConfidence < 0.6 || totalNutrients.hasImplausibleEnergy
    }
}

/// A single food within an entry.
@Model
public final class FoodItem {
    public var id: UUID = UUID()

    /// Stable identifier in the bundled database, or an Open Food Facts barcode.
    /// Nil for a purely manual item that matched nothing.
    public var foodID: String?

    /// What we show. May differ from the database name when the user renamed it.
    public var displayName: String = ""

    /// Brand, when the item came from a packaged product.
    public var brand: String?

    public var quantity: Double = 1
    public var unitRaw: String = MeasurementUnit.serving.rawValue

    /// Resolved mass in grams — the common currency all nutrition maths runs in.
    /// Nil when we genuinely couldn't convert (e.g. "a handful" of something with
    /// no density), in which case nutrients are taken per serving instead.
    public var grams: Double?

    /// Denormalized nutrition for this exact portion. See `Nutrients`.
    public var nutrientsData: Data?

    /// Ingredient and allergen tags used by the correlation engine — "dairy",
    /// "gluten", "allium". Populated from the food database at log time.
    public var tags: [String]? = []

    @Relationship public var entry: FoodEntry?

    public init(
        id: UUID = UUID(),
        foodID: String? = nil,
        displayName: String,
        brand: String? = nil,
        quantity: Double = 1,
        unit: MeasurementUnit = .serving,
        grams: Double? = nil,
        nutrients: Nutrients = .zero,
        tags: [String] = []
    ) {
        self.id = id
        self.foodID = foodID
        self.displayName = displayName
        self.brand = brand
        self.quantity = quantity
        self.unitRaw = unit.rawValue
        self.grams = grams
        self.tags = tags
        self.nutrients = nutrients
    }

    public var unit: MeasurementUnit {
        get { MeasurementUnit(rawValue: unitRaw) ?? .serving }
        set { unitRaw = newValue.rawValue }
    }

    /// Nutrients are stored as encoded JSON rather than 17 separate columns —
    /// it keeps the schema small and lets us add a micronutrient later without
    /// a migration.
    public var nutrients: Nutrients {
        get {
            guard let nutrientsData,
                  let decoded = try? JSONDecoder().decode(Nutrients.self, from: nutrientsData)
            else { return .zero }
            return decoded
        }
        set { nutrientsData = try? JSONEncoder().encode(newValue) }
    }

    public var resolvedTags: [String] { tags ?? [] }

    /// "2 slices", "180 g", "1 serving".
    public var quantityDescription: String {
        let formatted = quantity.formatted(.number.precision(.fractionLength(0...2)))
        return "\(formatted) \(unit.shortName(for: quantity))"
    }
}

/// One drink.
@Model
public final class WaterEntry {
    public var id: UUID = UUID()
    public var loggedAt: Date = Date()
    public var volumeML: Double = 0
    public var sourceRaw: String = EntrySource.quickAdd.rawValue

    /// What it was drunk from, so the quick-add buttons can mirror the user's
    /// real glasses and bottles rather than abstract millilitres.
    public var containerName: String?

    /// Caffeinated and alcoholic drinks are logged as hydration but flagged,
    /// because the Date Log cares about them as potential symptom triggers.
    public var containsCaffeine: Bool = false
    public var containsAlcohol: Bool = false

    public init(
        id: UUID = UUID(),
        loggedAt: Date = Date(),
        volumeML: Double,
        source: EntrySource = .quickAdd,
        containerName: String? = nil,
        containsCaffeine: Bool = false,
        containsAlcohol: Bool = false
    ) {
        self.id = id
        self.loggedAt = loggedAt
        self.volumeML = volumeML
        self.sourceRaw = source.rawValue
        self.containerName = containerName
        self.containsCaffeine = containsCaffeine
        self.containsAlcohol = containsAlcohol
    }

    public var source: EntrySource {
        get { EntrySource(rawValue: sourceRaw) ?? .quickAdd }
        set { sourceRaw = newValue.rawValue }
    }
}

/// A written journal entry.
@Model
public final class JournalEntry {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var title: String?
    public var body: String = ""
    public var moodRaw: Int?
    public var tags: [String]? = []

    @Attribute(.externalStorage) public var imageData: Data?

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        title: String? = nil,
        body: String = "",
        mood: Mood? = nil,
        tags: [String] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.title = title
        self.body = body
        self.moodRaw = mood?.rawValue
        self.tags = tags
    }

    public var mood: Mood? {
        get { moodRaw.flatMap(Mood.init(rawValue:)) }
        set { moodRaw = newValue?.rawValue }
    }

    public var resolvedTags: [String] { tags ?? [] }

    /// First line, for list rows.
    public var preview: String {
        if let title, !title.isEmpty { return title }
        let firstLine = body.split(separator: "\n").first.map(String.init) ?? ""
        return firstLine.isEmpty ? "Untitled entry" : firstLine
    }

    public var wordCount: Int {
        body.split { $0.isWhitespace || $0.isNewline }.count
    }
}

/// A Date Log record: something that happened to your body, which we will try to
/// connect back to what you ate.
@Model
public final class SymptomEntry {
    public var id: UUID = UUID()

    /// When the symptom was *felt* — not when it was typed. The distinction is
    /// the whole basis of the correlation window, so the UI always lets the user
    /// backdate it.
    public var occurredAt: Date = Date()
    public var loggedAt: Date = Date()

    public var kindRaw: String = SymptomKind.other.rawValue
    public var severityRaw: Int = Severity.moderate.rawValue

    /// Free text for anything the fixed vocabulary can't express.
    public var note: String?

    /// How long it lasted, in minutes, when known.
    public var durationMinutes: Int?

    /// Foods the user explicitly blamed. Kept separate from the statistical
    /// correlations — a hunch and a computed association are different kinds of
    /// evidence and shouldn't be mixed.
    public var suspectedFoodEntryIDs: [UUID]? = []

    public init(
        id: UUID = UUID(),
        occurredAt: Date = Date(),
        kind: SymptomKind = .other,
        severity: Severity = .moderate,
        note: String? = nil,
        durationMinutes: Int? = nil,
        suspectedFoodEntryIDs: [UUID] = []
    ) {
        self.id = id
        self.occurredAt = occurredAt
        self.loggedAt = Date()
        self.kindRaw = kind.rawValue
        self.severityRaw = severity.rawValue
        self.note = note
        self.durationMinutes = durationMinutes
        self.suspectedFoodEntryIDs = suspectedFoodEntryIDs
    }

    public var kind: SymptomKind {
        get { SymptomKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    public var severity: Severity {
        get { Severity(rawValue: severityRaw) ?? .moderate }
        set { severityRaw = newValue.rawValue }
    }
}

// MARK: - Streak participation

/// Lets the streak engine count food entries without `VesselCore`'s streak rules
/// having to know anything about SwiftData.
extension FoodEntry: MealLoggable {}
