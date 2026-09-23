import AppIntents
import VesselCore

// Siri's parameter types.
//
// App Intents reads display names at *build* time, from literals, so these
// can't be generated from `SymptomKind.allCases`: each case has to be written
// out. Each maps straight onto the app's own type, and a test checks that
// every `SymptomKind` has a counterpart here, so the two can't drift silently.

/// A symptom, as Siri offers it.
public enum SymptomChoice: String, AppEnum {
    case bloating, gas, crampingPain, nausea, heartburn
    case diarrhea, constipation, urgency
    case headache, fatigue, brainFog
    case skinFlareUp, itching, congestion
    case jointPain, racingHeart, other

    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Symptom"

    public static let caseDisplayRepresentations: [SymptomChoice: DisplayRepresentation] = [
        .bloating: DisplayRepresentation(title: "Bloating", synonyms: ["bloated", "puffy"]),
        .gas: DisplayRepresentation(title: "Gas", synonyms: ["wind", "gassy"]),
        .crampingPain: DisplayRepresentation(title: "Cramping", synonyms: ["cramps", "stomach ache", "stomach pain"]),
        .nausea: DisplayRepresentation(title: "Nausea", synonyms: ["nauseous", "feeling sick", "queasy"]),
        .heartburn: DisplayRepresentation(title: "Heartburn", synonyms: ["reflux", "indigestion"]),
        .diarrhea: DisplayRepresentation(title: "Diarrhea", synonyms: ["diarrhoea", "loose stools"]),
        .constipation: DisplayRepresentation(title: "Constipation", synonyms: ["constipated"]),
        .urgency: DisplayRepresentation(title: "Urgency"),
        .headache: DisplayRepresentation(title: "Headache", synonyms: ["migraine"]),
        .fatigue: DisplayRepresentation(title: "Fatigue", synonyms: ["tired", "exhausted"]),
        .brainFog: DisplayRepresentation(title: "Brain fog", synonyms: ["foggy"]),
        .skinFlareUp: DisplayRepresentation(title: "Skin flare-up", synonyms: ["rash", "eczema", "hives"]),
        .itching: DisplayRepresentation(title: "Itching", synonyms: ["itchy"]),
        .congestion: DisplayRepresentation(title: "Congestion", synonyms: ["stuffy nose", "congested"]),
        .jointPain: DisplayRepresentation(title: "Joint pain", synonyms: ["achy joints"]),
        .racingHeart: DisplayRepresentation(title: "Racing heart", synonyms: ["palpitations"]),
        .other: DisplayRepresentation(title: "Something else")
    ]

    public var kind: SymptomKind { SymptomKind(rawValue: rawValue) ?? .other }
}

/// How bad it is, in the app's own five steps.
public enum SeverityChoice: String, AppEnum {
    case trace, mild, moderate, strong, severe

    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Severity"

    public static let caseDisplayRepresentations: [SeverityChoice: DisplayRepresentation] = [
        .trace: DisplayRepresentation(title: "Barely there", synonyms: ["slight", "faint"]),
        .mild: DisplayRepresentation(title: "Mild", synonyms: ["a bit", "a little"]),
        .moderate: DisplayRepresentation(title: "Moderate"),
        .strong: DisplayRepresentation(title: "Disruptive", synonyms: ["bad", "strong"]),
        .severe: DisplayRepresentation(title: "Severe", synonyms: ["terrible", "awful"])
    ]

    public var severity: Severity {
        switch self {
        case .trace: return .trace
        case .mild: return .mild
        case .moderate: return .moderate
        case .strong: return .strong
        case .severe: return .severe
        }
    }
}

/// The containers on the Water screen, so "a bottle" means the same 500 ml
/// whether it's tapped or said.
public enum WaterServing: String, AppEnum {
    case glass, bottle, large, mug

    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Serving"

    public static let caseDisplayRepresentations: [WaterServing: DisplayRepresentation] = [
        .glass: DisplayRepresentation(title: "glass", subtitle: "250 ml", synonyms: ["cup"]),
        .bottle: DisplayRepresentation(title: "bottle", subtitle: "500 ml"),
        .large: DisplayRepresentation(title: "large bottle", subtitle: "750 ml", synonyms: ["big bottle"]),
        .mug: DisplayRepresentation(title: "mug", subtitle: "300 ml")
    ]

    public var millilitres: Double {
        switch self {
        case .glass: return 250
        case .bottle: return 500
        case .large: return 750
        case .mug: return 300
        }
    }
}
