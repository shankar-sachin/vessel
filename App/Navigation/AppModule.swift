import SwiftUI
import VesselDesign

/// The app's top-level sections.
///
/// One enum drives the iPhone tab bar, the iPad sidebar, Spotlight, and Siri
/// destinations — so a new section can't appear in one navigation surface and
/// quietly go missing from another.
public enum AppModule: String, CaseIterable, Identifiable, Hashable, Sendable {
    case today
    case diet
    case water
    case journal
    case dateLog

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .today:   return "Today"
        case .diet:    return "Diet"
        case .water:   return "Water"
        case .journal: return "Journal"
        case .dateLog: return "Date Log"
        }
    }

    /// Used where there's room to be clearer than the tab label.
    var longTitle: String {
        switch self {
        case .today:   return "Today"
        case .diet:    return "Diet Tracker"
        case .water:   return "Water Diary"
        case .journal: return "Journal"
        case .dateLog: return "Date Log"
        }
    }

    var symbol: String {
        switch self {
        case .today:   return "sun.horizon"
        case .diet:    return "fork.knife"
        case .water:   return "drop"
        case .journal: return "book.closed"
        case .dateLog: return "stethoscope"
        }
    }

    var selectedSymbol: String {
        switch self {
        case .today:   return "sun.horizon.fill"
        case .diet:    return "fork.knife"
        case .water:   return "drop.fill"
        case .journal: return "book.closed.fill"
        case .dateLog: return "stethoscope"
        }
    }

    /// The module's accent. Every screen in a section tints from this one value.
    var tint: Color {
        switch self {
        case .today:   return Palette.streak
        case .diet:    return Palette.diet
        case .water:   return Palette.water
        case .journal: return Palette.journal
        case .dateLog: return Palette.symptom
        }
    }

    /// Shown under the sidebar entry on iPad, where there's room to explain.
    var subtitle: String {
        switch self {
        case .today:   return "Your day at a glance"
        case .diet:    return "What you ate"
        case .water:   return "What you drank"
        case .journal: return "How it felt"
        case .dateLog: return "How your body reacted"
        }
    }
}
