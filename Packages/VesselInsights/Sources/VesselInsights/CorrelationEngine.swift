import Foundation
import VesselCore

/// One thing the log appears to show, with everything needed to judge it.
///
/// Every field a reader would need to disbelieve this is on the struct. That is
/// the design: a finding that can only be presented as a percentage is a
/// finding that can't be argued with, and health data that can't be argued with
/// is how people end up cutting out bread for a year on the strength of three
/// coincidences.
public struct Finding: Sendable, Hashable, Identifiable {

    public let trigger: Trigger
    public let symptom: SymptomKind

    /// Occasions on which the trigger was eaten.
    public let exposures: Int
    /// Of those, how many were followed by the symptom inside the window.
    public let hits: Int

    /// How often this symptom follows *any* meal, for this person.
    public let baseRate: Double
    /// Smoothed estimate of how often it follows this trigger.
    public let estimatedRate: Double
    /// 90% credible interval on that estimate.
    public let interval: ClosedRange<Double>
    /// Posterior probability the rate really is above the base rate.
    public let confidence: Double

    /// Median hours from eating to the symptom, and the middle half of them.
    public let onsetMedianHours: Double
    public let onsetRangeHours: ClosedRange<Double>

    /// Triggers that turned up on so nearly the same occasions that this data
    /// cannot separate them. Presented alongside, never silently discarded.
    public let indistinguishableFrom: [Trigger]

    public var id: String { "\(trigger.name)|\(symptom.rawValue)" }

    /// How much more often than usual, e.g. 2.1×.
    public var lift: Double { baseRate > 0 ? estimatedRate / baseRate : 0 }

    /// "7 of 9 occasions, typical onset 2.5h".
    ///
    /// The sample size leads. A bare "78%" is the same sentence with the only
    /// part that tells you whether to believe it removed.
    public var summary: String {
        let onset = onsetMedianHours < 1
            ? "\(Int((onsetMedianHours * 60).rounded())) min"
            : "\(onsetMedianHours.formatted(.number.precision(.fractionLength(0...1))))h"
        return "\(hits) of \(exposures) occasions, typical onset \(onset)"
    }
}

/// What the engine could say, and what it could not.
public struct InsightsReport: Sendable {
    public let findings: [Finding]
    /// Reactions logged in the period examined.
    public let symptomCount: Int
    /// Eating occasions examined.
    public let occasionCount: Int
    public let spanDays: Int
    public let configuration: InsightsConfiguration

    /// Why there is nothing to show, when there isn't — so the screen can say
    /// something truer than "no patterns found".
    public enum Silence: Sendable, Equatable {
        case noSymptoms
        case notEnoughHistory(daysSoFar: Int)
        case nothingStandsOut
    }

    public var silence: Silence? {
        guard findings.isEmpty else { return nil }
        if symptomCount == 0 { return .noSymptoms }
        if spanDays < 14 { return .notEnoughHistory(daysSoFar: spanDays) }
        return .nothingStandsOut
    }

    public static let empty = InsightsReport(
        findings: [], symptomCount: 0, occasionCount: 0, spanDays: 0, configuration: .default
    )
}

/// Connects what was eaten to what happened next.
///
/// The hard part is not finding correlations — with 22 ingredient groups and a
/// few hundred meals, something always correlates with something. The hard part
/// is refusing to report the ones that are noise, and every choice here is
/// pointed at that:
///
/// * **Denominators.** Dairy preceding seven headaches means nothing until you
///   know how many dairy days passed without one.
/// * **A prior from the person's own base rate.** If bloating follows half of
///   all meals, then dairy at 60% is unremarkable, and the maths has to know
///   that before it starts.
/// * **A floor on support.** Below five exposures nothing is reported, however
///   striking, because at n=2 the striking cases are the likely ones.
/// * **Named confounders.** Bread and butter arrive together; picking whichever
///   scored higher would be inventing a distinction the data does not contain.
///
/// Pure, with the clock injected, for the same reason `StreakEngine` is.
public struct CorrelationEngine: Sendable {

    public let configuration: InsightsConfiguration

    public init(configuration: InsightsConfiguration = .default) {
        self.configuration = configuration
    }

    // MARK: - Entry point

    public func report(meals: [MealObservation], symptoms: [SymptomObservation]) -> InsightsReport {
        let meals = meals.sorted { $0.at < $1.at }
        let symptoms = symptoms.sorted { $0.at < $1.at }

        let allOccasions = occasions(from: meals)
        let span = spanDays(meals: meals, symptoms: symptoms)

        guard !allOccasions.isEmpty, !symptoms.isEmpty else {
            return InsightsReport(
                findings: [], symptomCount: symptoms.count, occasionCount: allOccasions.count,
                spanDays: span, configuration: configuration
            )
        }

        // Occasions per trigger, computed once. A trigger's occasions are its
        // own meals coalesced — not the global occasions filtered — so that two
        // dairy meals three hours apart count once whatever else was eaten.
        var occasionsByTrigger: [Trigger: [Occasion]] = [:]
        for trigger in Set(meals.flatMap(\.triggers)) {
            let relevant = meals.filter { $0.triggers.contains(trigger) }
            occasionsByTrigger[trigger] = occasions(from: relevant)
        }

        var findings: [Finding] = []
        var comparisons = 0
        for kind in Set(symptoms.map(\.kind)) {
            let ofKind = symptoms.filter { $0.kind == kind }
            let base = baseRate(occasions: allOccasions, symptoms: ofKind)

            for (trigger, triggerOccasions) in occasionsByTrigger {
                guard let finding = evaluate(
                    trigger: trigger,
                    occasions: triggerOccasions,
                    totalOccasions: allOccasions.count,
                    symptoms: ofKind,
                    kind: kind,
                    baseRate: base
                ) else { continue }
                findings.append(finding)
                comparisons += 1
            }
        }

        // Correct for how many questions were asked.
        //
        // Every trigger is tested against every symptom. With twenty ingredient
        // groups and a dozen symptoms that is hundreds of questions, and at a
        // flat 90% bar roughly one in ten of the *pure noise* ones clears it —
        // so a log with no relationship in it at all still produces a confident
        // headline. Dividing the tolerated error among the comparisons made is
        // the oldest fix there is, and the conservative direction is the right
        // one to be wrong in here.
        let tolerated = (1 - configuration.minimumConfidence) / Double(max(comparisons, 1))
        findings = findings.filter { $0.confidence >= 1 - tolerated }

        findings = annotateConfounders(findings, occasionsByTrigger: occasionsByTrigger)

        // Strongest evidence first, not largest effect: a 3× lift from five
        // occasions should not outrank a 2× lift from forty.
        findings.sort {
            $0.confidence == $1.confidence ? $0.lift > $1.lift : $0.confidence > $1.confidence
        }

        return InsightsReport(
            findings: findings, symptomCount: symptoms.count,
            occasionCount: allOccasions.count, spanDays: span, configuration: configuration
        )
    }

    // MARK: - One trigger against one symptom

    private func evaluate(
        trigger: Trigger,
        occasions triggerOccasions: [Occasion],
        totalOccasions: Int,
        symptoms: [SymptomObservation],
        kind: SymptomKind,
        baseRate: Double
    ) -> Finding? {
        // The support floor. This is the line the whole feature's honesty
        // rests on, and it is checked before anything is computed rather than
        // as a filter afterwards, so there is no path that can skip it.
        guard triggerOccasions.count >= configuration.minimumExposures else { return nil }

        // No contrast, no conclusion. If nearly every occasion involved this
        // trigger, its rate *is* the base rate and the comparison is circular.
        let controls = totalOccasions - triggerOccasions.count
        guard controls >= configuration.minimumControls else { return nil }

        var onsets: [Double] = []
        for occasion in triggerOccasions {
            guard let delay = firstSymptomDelay(after: occasion, in: symptoms) else { continue }
            onsets.append(delay / 3600)
        }

        let hits = onsets.count
        let posterior = Statistics.Beta
            .prior(mean: baseRate, strength: configuration.priorStrength)
            .updated(successes: hits, trials: triggerOccasions.count)

        let confidence = posterior.probability(greaterThan: baseRate)
        let estimate = posterior.mean
        let interval = posterior.quantile(0.05)...posterior.quantile(0.95)

        // The bar is the *pessimistic* end of the interval, not the estimate.
        //
        // Requiring the point estimate to be half again the base rate sounds
        // strict and isn't: at small samples the point estimate wanders freely,
        // and on ninety days of random meals something always wanders far
        // enough. Asking instead that even the low end of the credible range
        // still be meaningfully elevated is the same question asked of the
        // whole distribution, and noise cannot answer it — a run of luck widens
        // the interval as fast as it lifts the mean.
        guard baseRate > 0, interval.lowerBound >= baseRate * configuration.minimumLift else {
            return nil
        }

        // An onset can't be summarised from nothing; a finding with no hits
        // cannot have cleared the confidence bar anyway, but the maths is
        // allowed to surprise us and the unwrap is not.
        guard let median = Statistics.median(onsets),
              let low = Statistics.percentile(onsets, 0.25),
              let high = Statistics.percentile(onsets, 0.75)
        else { return nil }

        return Finding(
            trigger: trigger,
            symptom: kind,
            exposures: triggerOccasions.count,
            hits: hits,
            baseRate: baseRate,
            estimatedRate: estimate,
            interval: interval,
            confidence: confidence,
            onsetMedianHours: median,
            onsetRangeHours: low...high,
            indistinguishableFrom: []
        )
    }

    // MARK: - Pieces

    /// How often this symptom follows *any* eating occasion.
    ///
    /// The prior, and the thing every trigger is compared against. Measured the
    /// same way as a trigger's rate so the two are commensurable — a base rate
    /// computed per day against a trigger rate computed per occasion would make
    /// every trigger look alarming.
    func baseRate(occasions: [Occasion], symptoms: [SymptomObservation]) -> Double {
        guard !occasions.isEmpty else { return 0 }
        let followed = occasions.filter { firstSymptomDelay(after: $0, in: symptoms) != nil }.count
        return Double(followed) / Double(occasions.count)
    }

    /// Seconds from an occasion to the first symptom inside the window.
    private func firstSymptomDelay(after occasion: Occasion, in symptoms: [SymptomObservation]) -> TimeInterval? {
        for symptom in symptoms {
            let delay = symptom.at.timeIntervalSince(occasion.start)
            if delay <= 0 { continue }
            if delay > configuration.window { break }   // sorted, so the rest are further out
            return delay
        }
        return nil
    }

    /// Collapses meals into eating occasions.
    func occasions(from meals: [MealObservation]) -> [Occasion] {
        let sorted = meals.sorted { $0.at < $1.at }
        var result: [Occasion] = []
        var currentStart: Date?
        var currentIDs: [UUID] = []
        var last: Date?

        for meal in sorted {
            if let previous = last, meal.at.timeIntervalSince(previous) <= configuration.occasionMergeWindow {
                currentIDs.append(meal.id)
            } else {
                if let start = currentStart { result.append(Occasion(start: start, mealIDs: currentIDs)) }
                currentStart = meal.at
                currentIDs = [meal.id]
            }
            last = meal.at
        }
        if let start = currentStart { result.append(Occasion(start: start, mealIDs: currentIDs)) }
        return result
    }

    /// Flags findings whose triggers arrive on nearly the same occasions.
    ///
    /// Bread and butter, coffee and milk, tomato and onion. When two triggers
    /// overlap this heavily, no amount of data *of this kind* separates them —
    /// only eating one without the other does. Saying so is more useful than
    /// naming whichever scored a hair higher, and it points at the experiment
    /// that would settle it.
    private func annotateConfounders(
        _ findings: [Finding],
        occasionsByTrigger: [Trigger: [Occasion]]
    ) -> [Finding] {
        let starts = occasionsByTrigger.mapValues { Set($0.map(\.start)) }

        return findings.map { finding in
            guard let mine = starts[finding.trigger] else { return finding }
            let partners = findings
                .filter { $0.symptom == finding.symptom && $0.trigger != finding.trigger }
                .filter { other in
                    guard let theirs = starts[other.trigger] else { return false }
                    return Statistics.jaccard(mine, theirs) >= configuration.confounderOverlap
                }
                .map(\.trigger)

            guard !partners.isEmpty else { return finding }
            return Finding(
                trigger: finding.trigger, symptom: finding.symptom,
                exposures: finding.exposures, hits: finding.hits,
                baseRate: finding.baseRate, estimatedRate: finding.estimatedRate,
                interval: finding.interval, confidence: finding.confidence,
                onsetMedianHours: finding.onsetMedianHours, onsetRangeHours: finding.onsetRangeHours,
                indistinguishableFrom: partners.sorted { $0.name < $1.name }
            )
        }
    }

    private func spanDays(meals: [MealObservation], symptoms: [SymptomObservation]) -> Int {
        let dates = meals.map(\.at) + symptoms.map(\.at)
        guard let first = dates.min(), let last = dates.max() else { return 0 }
        return Int(last.timeIntervalSince(first) / 86400) + 1
    }
}
