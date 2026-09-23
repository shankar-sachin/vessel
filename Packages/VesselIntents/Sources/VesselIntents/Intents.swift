import AppIntents
import Foundation
import SwiftData
import VesselCore
import VesselIntelligence
import VesselNutrition

/// Log anything, the way you'd say it: "two eggs and toast", "a latte",
/// "bloated after lunch", "slept badly".
///
/// Runs the same pipeline and the same writer as the Quick log box. That is
/// the whole design of this phase — Siri is another way *in*, never another
/// parser.
public struct LogIntent: AppIntent {
    public static let title: LocalizedStringResource = "Log in Vessel"
    public static let description = IntentDescription(
        "Log a meal, drink, reaction or note, said the way you'd say it."
    )

    @Parameter(title: "What", requestValueDialog: "What would you like to log?")
    public var text: String

    /// Asked for only when the parse is ambiguous — "milk" could be whole or
    /// skim — and never shown in the Shortcuts editor.
    @Parameter(title: "Which one")
    public var variant: FoodEntity?

    public static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$text)")
    }

    public init() {}

    public init(text: String) {
        self.text = text
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let parsed = ParsePipeline().parse(text)

        // A question isn't something to log. "How much protein today" gets
        // the same answer as asking how the day is going.
        if parsed.intent == .query {
            let summary = IntakeSummary.today(in: IntentsRuntime.context).sentence
            return .result(value: summary, dialog: "\(summary)")
        }

        let resolver = EntryResolver()
        let resolved = resolver.resolve(parsed)

        // "Which milk?" — the same derived choices the app offers.
        var choices: [UUID: FoodRecord] = [:]
        for food in resolved where !food.variants.isEmpty {
            let options = food.variants.map {
                FoodEntity(record: $0, label: FoodVariants.distinguishingLabel(for: $0, term: food.phrase))
            }
            let chosen = try await $variant.requestDisambiguation(
                among: options,
                dialog: "Which \(food.phrase)?"
            )
            if let record = FoodDatabase.shared.food(withID: chosen.id) {
                choices[food.id] = record
            }
        }

        // An unsure parse is read back before it's saved. Saving a guess
        // silently is exactly what the in-app preview exists to prevent, and
        // a voice-only surface has no preview.
        if Self.needsConfirmation(parsed) {
            let heard = IntentDialog(stringLiteral: "I heard “\(parsed.original)” as \(Self.describe(parsed)). Save it?")
            try await requestConfirmation(actionName: .log, dialog: heard)
        }

        let context = IntentsRuntime.context
        let outcome = EntryWriter(context: context, resolver: resolver)
            .write(parsed, resolved: resolved, variantChoices: choices, source: .siri)
        await IntentsRuntime.didLog?(context)

        return .result(value: outcome.summary, dialog: "\(outcome.summary)")
    }

    /// Whether Siri should read the parse back before saving it.
    static func needsConfirmation(_ parsed: ParsedEntry) -> Bool {
        parsed.confidence < ParsePipeline.confidentThreshold
    }

    static func describe(_ parsed: ParsedEntry) -> String {
        switch parsed.intent {
        case .logFood, .correction:
            let foods = parsed.foods.map(\.phrase)
            return foods.isEmpty ? "a meal" : EntryWriter.Outcome.list(foods)
        case .logWater:
            return parsed.drinks.first.map { "a drink of \($0.name)" } ?? "a drink"
        case .logSymptom:
            return parsed.symptom.map { $0.kind.title.lowercased() } ?? "a reaction"
        case .journalEntry, .unknown:
            return "a journal note"
        case .query:
            return "a question"
        }
    }
}

/// "Log a bottle of water in Vessel."
public struct LogWaterIntent: AppIntent {
    public static let title: LocalizedStringResource = "Log Water"
    public static let description = IntentDescription("Add water to today's Water diary.")

    @Parameter(title: "Serving", default: .glass)
    public var serving: WaterServing

    @Parameter(title: "Millilitres", description: "Overrides the serving when given.",
               inclusiveRange: (1, 3000))
    public var millilitres: Int?

    public static var parameterSummary: some ParameterSummary {
        Summary("Log a \(\.$serving) of water") {
            \.$millilitres
        }
    }

    public init() {}

    public init(serving: WaterServing, millilitres: Int? = nil) {
        self.serving = serving
        self.millilitres = millilitres
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let volume = millilitres.map(Double.init) ?? serving.millilitres
        let context = IntentsRuntime.context
        context.insert(WaterEntry(
            volumeML: volume,
            source: .siri,
            containerName: WaterServing.caseDisplayRepresentations[serving].map { String(localized: $0.title) }?.capitalized
        ))
        try? context.save()
        await IntentsRuntime.didLog?(context)

        let summary = IntakeSummary.today(in: context)
        return .result(dialog: "Added \(Int(volume)) ml. \(summary.waterSentence)")
    }
}

/// "Log bloating in Vessel."
public struct LogSymptomIntent: AppIntent {
    public static let title: LocalizedStringResource = "Log a Reaction"
    public static let description = IntentDescription(
        "Record a symptom for the Date Log, timed from when you say it."
    )

    @Parameter(title: "Symptom", requestValueDialog: "What are you feeling?")
    public var symptom: SymptomChoice

    @Parameter(title: "Severity", default: .moderate)
    public var severity: SeverityChoice

    public static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$symptom), \(\.$severity)")
    }

    public init() {}

    public init(symptom: SymptomChoice, severity: SeverityChoice = .moderate) {
        self.symptom = symptom
        self.severity = severity
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = IntentsRuntime.context
        context.insert(SymptomEntry(kind: symptom.kind, severity: severity.severity, note: nil))
        try? context.save()
        await IntentsRuntime.didLog?(context)
        return .result(dialog: "Logged \(symptom.kind.title.lowercased()), \(severity.severity.title.lowercased()).")
    }
}

/// "Add a journal entry in Vessel."
public struct AddJournalEntryIntent: AppIntent {
    public static let title: LocalizedStringResource = "Add Journal Entry"
    public static let description = IntentDescription("Write a note in today's journal.")

    @Parameter(title: "Entry", inputOptions: String.IntentInputOptions(multiline: true),
               requestValueDialog: "What would you like to write?")
    public var text: String

    public static var parameterSummary: some ParameterSummary {
        Summary("Write \(\.$text) in the journal")
    }

    public init() {}

    public init(text: String) {
        self.text = text
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = IntentsRuntime.context
        context.insert(JournalEntry(body: text))
        try? context.save()
        return .result(dialog: "Added to your journal.")
    }
}

/// "How am I doing in Vessel?"
public struct CheckIntakeIntent: AppIntent {
    public static let title: LocalizedStringResource = "How Am I Doing"
    public static let description = IntentDescription(
        "Today's calories and water against your goals, and your streak."
    )

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let sentence = IntakeSummary.today(in: IntentsRuntime.context).sentence
        return .result(value: sentence, dialog: "\(sentence)")
    }
}

extension ConfirmationActionName {
    static var log: ConfirmationActionName { .add }
}
