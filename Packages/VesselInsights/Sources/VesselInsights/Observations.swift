import Foundation
import VesselCore

/// Something a symptom might be blamed on.
///
/// Deliberately not "a food". Pizza is never the answer — dairy or gluten is,
/// and those cut across dishes that share no name. But a group is not always
/// the answer either: someone whose problem is coffee specifically is not
/// helped by being told "caffeine", and someone reacting to onions is not
/// helped by being told "FODMAPs". So both are candidates, ranked against each
/// other on the same evidence, and whichever the data actually supports wins.
public enum Trigger: Hashable, Sendable, Codable {
    /// An ingredient or food group tag from the food database — "dairy", "allium".
    case group(String)
    /// One food, keyed by its normalized name.
    case food(String)

    public var name: String {
        switch self {
        case .group(let value), .food(let value): return value
        }
    }

    /// Title case for display, without shouting.
    public var title: String {
        name.prefix(1).uppercased() + name.dropFirst()
    }

    public var isGroup: Bool {
        if case .group = self { return true }
        return false
    }
}

/// One eating occasion, reduced to what the engine needs.
///
/// A plain struct rather than the SwiftData model, so every rule in here can be
/// tested against a synthetic history with no persistent container — which is
/// the only way to test a statistical claim, because you have to know the right
/// answer in advance to check whether it was found.
public struct MealObservation: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let at: Date
    /// Ingredient groups present, e.g. `["dairy", "gluten"]`.
    public let groups: Set<String>
    /// Normalized names of the individual foods.
    public let foods: Set<String>

    public init(id: UUID = UUID(), at: Date, groups: Set<String> = [], foods: Set<String> = []) {
        self.id = id
        self.at = at
        self.groups = groups
        self.foods = foods
    }

    public var triggers: Set<Trigger> {
        Set(groups.map(Trigger.group)).union(foods.map(Trigger.food))
    }
}

/// One recorded reaction.
public struct SymptomObservation: Sendable, Hashable, Identifiable {
    public let id: UUID
    /// When it was *felt*, not when it was typed.
    public let at: Date
    public let kind: SymptomKind
    public let severity: Severity

    public init(id: UUID = UUID(), at: Date, kind: SymptomKind, severity: Severity = .moderate) {
        self.id = id
        self.at = at
        self.kind = kind
        self.severity = severity
    }
}

/// An eating occasion as the engine counts it: one or more meals close enough
/// together to be a single exposure.
///
/// Without this, a cheese sandwich at noon and a latte at one are two dairy
/// exposures, and one bout of bloating at three is a hit for both. The
/// denominator inflates, the numerator inflates, and the engine ends up more
/// confident from a habit of snacking than from any relationship with food.
struct Occasion: Sendable, Hashable {
    let start: Date
    let mealIDs: [UUID]
}

/// Knobs, all in one place, with the reasoning attached.
public struct InsightsConfiguration: Sendable, Hashable {

    /// How long after eating a symptom still counts as possibly related.
    ///
    /// Six hours by default. Digestive reactions mostly land inside that;
    /// stretching to 24 makes almost everything follow almost everything, which
    /// looks like more evidence and is less.
    public var window: TimeInterval

    /// Meals closer together than this are one exposure.
    public var occasionMergeWindow: TimeInterval

    /// Exposures required before a trigger can be named at all.
    ///
    /// Five. Four out of four looks overwhelming and is roughly as likely as
    /// four coin flips landing heads.
    public var minimumExposures: Int

    /// Occasions *without* the trigger required before the comparison means
    /// anything. Someone who has dairy at every meal has no control group, and
    /// the honest answer there is "this log can't tell you", not a number.
    public var minimumControls: Int

    /// Weight of the prior, in imaginary occasions.
    public var priorStrength: Double

    /// Posterior probability that the trigger's rate genuinely exceeds the
    /// user's base rate, required before anything is shown.
    public var minimumConfidence: Double

    /// How much higher than the base rate it has to be to be worth saying.
    /// A trigger that raises a 40% base rate to 44% is not a finding.
    public var minimumLift: Double

    /// Above this overlap, two triggers cannot be told apart by this data.
    public var confounderOverlap: Double

    public init(
        window: TimeInterval = 6 * 3600,
        occasionMergeWindow: TimeInterval = 3 * 3600,
        minimumExposures: Int = 5,
        minimumControls: Int = 5,
        priorStrength: Double = 8,
        minimumConfidence: Double = 0.9,
        minimumLift: Double = 1.5,
        confounderOverlap: Double = 0.8
    ) {
        // The window is clamped rather than trusted: the settings screen offers
        // 0.5–48h and a value outside that produces nonsense quietly.
        self.window = min(max(window, 1800), 48 * 3600)
        self.occasionMergeWindow = max(0, occasionMergeWindow)
        self.minimumExposures = max(1, minimumExposures)
        self.minimumControls = max(0, minimumControls)
        self.priorStrength = max(0.1, priorStrength)
        self.minimumConfidence = min(max(minimumConfidence, 0.5), 0.999)
        self.minimumLift = max(1, minimumLift)
        self.confounderOverlap = min(max(confounderOverlap, 0.1), 1)
    }

    public static let `default` = InsightsConfiguration()
}
