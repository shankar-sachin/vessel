import AppIntents
import CoreSpotlight
import Foundation
import SwiftData
import VesselCore
import VesselNutrition

/// A food from the bundled database, so Siri can ask "which milk?" and offer
/// real rows to choose between.
public struct FoodEntity: AppEntity, Identifiable {
    public let id: String
    public let title: String
    public let detail: String?

    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Food"
    public static let defaultQuery = FoodEntityQuery()

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: detail.map { "\($0)" }
        )
    }

    public init(record: FoodRecord, label: String? = nil) {
        let name = FoodName(record.displayName)
        id = record.id
        // In a "which one?" list the distinguishing words are the answer, so
        // they lead: "Reduced fat (2%)", not "Milk".
        title = label.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? name.title
        detail = "\(Int(record.nutrientsPer100g.kilocalories.rounded())) kcal per 100 g"
    }
}

public struct FoodEntityQuery: EntityStringQuery {
    public init() {}

    public func entities(for identifiers: [String]) async throws -> [FoodEntity] {
        identifiers.compactMap { FoodDatabase.shared.food(withID: $0) }.map { FoodEntity(record: $0) }
    }

    public func entities(matching string: String) async throws -> [FoodEntity] {
        FoodSearch().search(string, limit: 8).map { FoodEntity(record: $0.food) }
    }

    public func suggestedEntities() async throws -> [FoodEntity] {
        FoodSearch().suggestions(limit: 12).map { FoodEntity(record: $0.food) }
    }
}

/// A logged meal, indexed in Spotlight so searching "porridge" on the home
/// screen finds the mornings it was eaten.
public struct MealEntity: IndexedEntity, Identifiable {
    public let id: UUID
    public let title: String
    public let when: Date
    public let calories: Int

    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Meal"
    public static let defaultQuery = MealEntityQuery()

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(when.formatted(date: .abbreviated, time: .shortened)) · \(calories) kcal",
            image: .init(systemName: "fork.knife")
        )
    }

    public var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet()
        attributes.title = title
        attributes.contentDescription = "\(when.formatted(date: .abbreviated, time: .shortened)) · \(calories) kcal"
        attributes.keywords = title.lowercased().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        return attributes
    }

    @MainActor
    public init(entry: FoodEntry) {
        let items = entry.items ?? []
        id = entry.id
        title = items.map { FoodName($0.displayName).title }.joined(separator: ", ")
        when = entry.loggedAt
        calories = Int(items.reduce(0) { $0 + $1.nutrients.kilocalories }.rounded())
    }
}

public struct MealEntityQuery: EntityQuery {
    public init() {}

    @MainActor
    public func entities(for identifiers: [UUID]) async throws -> [MealEntity] {
        let wanted = Set(identifiers)
        let descriptor = FetchDescriptor<FoodEntry>(predicate: #Predicate { wanted.contains($0.id) })
        return ((try? IntentsRuntime.context.fetch(descriptor)) ?? []).map(MealEntity.init(entry:))
    }
}

/// Keeps Spotlight in step with what's been logged.
public enum MealIndex {
    /// Indexes a meal. Failures are ignored: Spotlight is a convenience, and a
    /// meal that isn't searchable is still logged.
    @MainActor
    public static func index(_ entry: FoodEntry) {
        let entity = MealEntity(entry: entry)
        Task.detached { try? await CSSearchableIndex.default().indexAppEntities([entity]) }
    }
}

/// Opens the Diet log at a meal found in Spotlight.
public struct OpenMealIntent: OpenIntent {
    public static let title: LocalizedStringResource = "Open Meal"

    @Parameter(title: "Meal")
    public var target: MealEntity

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        IntentsRuntime.openMeal?(target.id)
        return .result()
    }
}
