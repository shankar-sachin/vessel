import Foundation

/// Which sitting a food entry belongs to.
///
/// Deliberately a small fixed set rather than free text: the streak rule counts
/// *distinct slots*, so "three meals" can't be satisfied by logging the same
/// coffee three times.
public enum MealSlot: String, Codable, Sendable, CaseIterable, Identifiable {
    case breakfast, lunch, dinner, snack

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .breakfast: return "Breakfast"
        case .lunch:     return "Lunch"
        case .dinner:    return "Dinner"
        case .snack:     return "Snack"
        }
    }

    public var symbol: String {
        switch self {
        case .breakfast: return "sunrise.fill"
        case .lunch:     return "sun.max.fill"
        case .dinner:    return "moon.stars.fill"
        case .snack:     return "carrot.fill"
        }
    }

    /// Slots that count toward a "proper meal" requirement. Snacks are logged and
    /// counted nutritionally, but grazing shouldn't quietly satisfy a 3-meal goal.
    public static let primarySlots: [MealSlot] = [.breakfast, .lunch, .dinner]

    /// Best guess for a given time of day, used to pre-select the slot when
    /// logging. Always user-overridable.
    public static func inferred(from date: Date, calendar: Calendar = .current) -> MealSlot {
        switch calendar.component(.hour, from: date) {
        case 4..<11:  return .breakfast
        case 11..<16: return .lunch
        case 16..<22: return .dinner
        default:      return .snack
        }
    }
}

/// How an entry got into the app. Tracked so we can measure which input methods
/// people actually use, and so a low-confidence parse can be shown for review.
public enum EntrySource: String, Codable, Sendable, CaseIterable {
    case manual, text, voice, photo, barcode, siri, quickAdd

    public var symbol: String {
        switch self {
        case .manual:   return "hand.tap"
        case .text:     return "text.cursor"
        case .voice:    return "waveform"
        case .photo:    return "camera"
        case .barcode:  return "barcode.viewfinder"
        case .siri:     return "mic.circle"
        case .quickAdd: return "bolt"
        }
    }
}

/// Digestive and dietary reactions tracked by the Date Log.
///
/// A fixed vocabulary matters here: the correlation engine needs to group the
/// same symptom across weeks, and free text would fragment "bloated" / "bloating"
/// / "so bloated" into three unrelated series.
public enum SymptomKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case bloating, gas, crampingPain, nausea, heartburn
    case diarrhea, constipation, urgency
    case headache, fatigue, brainFog
    case skinFlareUp, itching, congestion
    case jointPain, racingHeart, other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .bloating:     return "Bloating"
        case .gas:          return "Gas"
        case .crampingPain: return "Cramping or pain"
        case .nausea:       return "Nausea"
        case .heartburn:    return "Heartburn or reflux"
        case .diarrhea:     return "Diarrhea"
        case .constipation: return "Constipation"
        case .urgency:      return "Urgency"
        case .headache:     return "Headache"
        case .fatigue:      return "Fatigue"
        case .brainFog:     return "Brain fog"
        case .skinFlareUp:  return "Skin flare-up"
        case .itching:      return "Itching"
        case .congestion:   return "Congestion"
        case .jointPain:    return "Joint pain"
        case .racingHeart:  return "Racing heart"
        case .other:        return "Other"
        }
    }

    public var symbol: String {
        switch self {
        case .bloating, .gas:            return "wind"
        case .crampingPain, .jointPain:  return "bolt.horizontal"
        case .nausea, .heartburn:        return "flame"
        case .diarrhea, .constipation, .urgency: return "drop.triangle"
        case .headache, .brainFog:       return "brain.head.profile"
        case .fatigue:                   return "zzz"
        case .skinFlareUp, .itching:     return "allergens"
        case .congestion:                return "nose"
        case .racingHeart:               return "heart"
        case .other:                     return "questionmark.circle"
        }
    }

    /// Grouping used when presenting the picker.
    public var category: String {
        switch self {
        case .bloating, .gas, .crampingPain, .nausea, .heartburn,
             .diarrhea, .constipation, .urgency:
            return "Digestive"
        case .headache, .fatigue, .brainFog:
            return "Systemic"
        case .skinFlareUp, .itching, .congestion:
            return "Allergic"
        case .jointPain, .racingHeart, .other:
            return "Other"
        }
    }
}

/// How strongly a symptom presented. Five points, each with a plain-language
/// anchor so "3" means the same thing in March as it did in January — otherwise
/// severity drifts and the correlation numbers become noise.
public enum Severity: Int, Codable, Sendable, CaseIterable, Identifiable {
    case trace = 1, mild = 2, moderate = 3, strong = 4, severe = 5

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .trace:    return "Barely there"
        case .mild:     return "Mild"
        case .moderate: return "Moderate"
        case .strong:   return "Disruptive"
        case .severe:   return "Severe"
        }
    }

    public var detail: String {
        switch self {
        case .trace:    return "I only notice it if I think about it"
        case .mild:     return "Present, but I can ignore it"
        case .moderate: return "Hard to ignore, but I carried on"
        case .strong:   return "It changed what I did"
        case .severe:   return "I had to stop what I was doing"
        }
    }
}

/// Mood recorded alongside a journal entry.
public enum Mood: Int, Codable, Sendable, CaseIterable, Identifiable {
    case low = 1, subdued = 2, steady = 3, good = 4, great = 5

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .low:     return "Low"
        case .subdued: return "Subdued"
        case .steady:  return "Steady"
        case .good:    return "Good"
        case .great:   return "Great"
        }
    }

    public var symbol: String {
        switch self {
        case .low:     return "cloud.rain.fill"
        case .subdued: return "cloud.fill"
        case .steady:  return "cloud.sun.fill"
        case .good:    return "sun.max.fill"
        case .great:   return "sparkles"
        }
    }
}
