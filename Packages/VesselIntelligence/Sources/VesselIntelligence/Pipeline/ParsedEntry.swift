import Foundation
import VesselCore

/// What the parser understood from one utterance.
public struct ParsedEntry: Sendable, Equatable {

    /// What the user was trying to do.
    public enum Intent: String, Sendable, CaseIterable {
        case logFood, logWater, logSymptom, journalEntry, query, correction, unknown
    }

    public var intent: Intent
    /// Foods found, in the order they were said.
    public var foods: [ParsedFood]
    /// Drinks found, for water logging.
    public var drinks: [ParsedDrink]
    /// Symptom, when the utterance was a reaction.
    public var symptom: ParsedSymptom?
    /// When the user said it happened, if they said.
    public var occurredAt: Date?
    /// The meal they named, if they named one.
    public var slot: MealSlot?
    /// The text as spoken, kept for display and for improving the parser.
    public var original: String

    /// 0...1. Below `ParsePipeline.confidentThreshold` the UI asks the user to
    /// confirm rather than filling the entry in silently.
    public var confidence: Double

    /// Why the parser is unsure, in words the UI can show.
    public var uncertainties: [String]

    public init(
        intent: Intent = .unknown,
        foods: [ParsedFood] = [],
        drinks: [ParsedDrink] = [],
        symptom: ParsedSymptom? = nil,
        occurredAt: Date? = nil,
        slot: MealSlot? = nil,
        original: String = "",
        confidence: Double = 0,
        uncertainties: [String] = []
    ) {
        self.intent = intent
        self.foods = foods
        self.drinks = drinks
        self.symptom = symptom
        self.occurredAt = occurredAt
        self.slot = slot
        self.original = original
        self.confidence = confidence
        self.uncertainties = uncertainties
    }

    public var isEmpty: Bool {
        foods.isEmpty && drinks.isEmpty && symptom == nil
    }
}

/// One food the parser extracted, before it's matched to the database.
public struct ParsedFood: Sendable, Equatable {
    /// The words naming the food, e.g. "scrambled eggs".
    public var phrase: String
    public var quantity: Double?
    /// True when the quantity was implied or vague rather than stated.
    public var quantityIsApproximate: Bool
    public var unit: MeasurementUnit?
    /// Preparation words found alongside, e.g. "grilled".
    public var preparation: [String]
    public var brand: String?
    /// True when the phrase was preceded by a negation ("no butter").
    public var isNegated: Bool

    public init(
        phrase: String,
        quantity: Double? = nil,
        quantityIsApproximate: Bool = false,
        unit: MeasurementUnit? = nil,
        preparation: [String] = [],
        brand: String? = nil,
        isNegated: Bool = false
    ) {
        self.phrase = phrase
        self.quantity = quantity
        self.quantityIsApproximate = quantityIsApproximate
        self.unit = unit
        self.preparation = preparation
        self.brand = brand
        self.isNegated = isNegated
    }
}

/// A drink, for the Water Diary.
public struct ParsedDrink: Sendable, Equatable {
    public var name: String
    public var quantity: Double?
    public var unit: MeasurementUnit?
    /// Resolved volume, when the quantity and unit allow it.
    public var millilitres: Double?

    public init(name: String, quantity: Double? = nil, unit: MeasurementUnit? = nil, millilitres: Double? = nil) {
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.millilitres = millilitres
    }
}

/// A reaction, for the Date Log.
public struct ParsedSymptom: Sendable, Equatable {
    public var kind: SymptomKind
    public var severity: Severity?
    /// A food the user blamed, if they named one.
    public var attributedTo: String?

    public init(kind: SymptomKind, severity: Severity? = nil, attributedTo: String? = nil) {
        self.kind = kind
        self.severity = severity
        self.attributedTo = attributedTo
    }
}
