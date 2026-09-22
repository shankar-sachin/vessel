import Foundation
import VesselCore

/// Turns the stored log into the plain values the engine reasons about.
///
/// The seam exists so the statistics never touch SwiftData. A correlation rule
/// that can only be exercised through a persistent container is a rule that
/// won't be exercised.
public enum History {

    /// Reduces a food entry to its triggers.
    ///
    /// Groups come from the tags denormalized onto each item at log time, which
    /// is why they are stored there rather than looked up: a meal logged last
    /// year has to keep the tags it was logged with, or correcting the food
    /// database silently rewrites someone's history.
    public static func observations(from entries: [FoodEntry]) -> [MealObservation] {
        entries.map { entry in
            let items = entry.resolvedItems
            return MealObservation(
                id: entry.id,
                at: entry.loggedAt,
                groups: Set(items.flatMap(\.resolvedTags)),
                foods: Set(items.map { foodKey($0.displayName) })
            )
        }
    }

    public static func observations(from entries: [SymptomEntry]) -> [SymptomObservation] {
        entries.map {
            SymptomObservation(id: $0.id, at: $0.occurredAt, kind: $0.kind, severity: $0.severity)
        }
    }

    /// Caffeinated and alcoholic drinks are potential triggers too, and they're
    /// logged in the Water diary rather than the Diet one. Leaving them out
    /// would mean a coffee drinker's log can never implicate coffee.
    public static func observations(from entries: [WaterEntry]) -> [MealObservation] {
        entries.compactMap { entry in
            var groups: Set<String> = []
            if entry.containsCaffeine { groups.insert("caffeine") }
            if entry.containsAlcohol { groups.insert("alcohol") }
            guard !groups.isEmpty else { return nil }
            return MealObservation(
                id: entry.id,
                at: entry.loggedAt,
                groups: groups,
                foods: Set([entry.containerName.map(foodKey)].compactMap { $0 })
            )
        }
    }

    /// The name a food is grouped under.
    ///
    /// USDA names carry their qualifiers — "Yogurt, Greek, whole milk, plain" —
    /// and grouping on the whole string would treat every variant as a separate
    /// suspect, splitting the evidence exactly when it needs to accumulate.
    /// The clause before the first comma is what the food is.
    static func foodKey(_ displayName: String) -> String {
        let clause = displayName.components(separatedBy: ",").first ?? displayName
        return clause.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
