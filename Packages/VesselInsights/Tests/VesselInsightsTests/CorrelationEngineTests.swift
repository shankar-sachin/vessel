import Testing
import Foundation
import VesselCore
@testable import VesselInsights

@Suite("Refusing to find things that aren't there")
struct RestraintTests {

    /// The test this whole feature's integrity rests on.
    ///
    /// Two dairy meals, both followed by bloating, is a 100% correlation and a
    /// coin landing heads twice. An app that says "dairy — 100%" here has
    /// invented a health conclusion out of two data points, and the person it
    /// says it to will believe it.
    @Test("Two coincidences produce nothing")
    func silentAtTwo() {
        var history = SyntheticHistory()
        for day in 0..<2 {
            let meal = history.eat(day: day, hour: 12, groups: ["dairy"])
            history.feel(.bloating, after: meal, hours: 2)
        }
        for day in 2..<12 {
            _ = history.eat(day: day, hour: 12, groups: ["gluten"])
        }

        let report = CorrelationEngine().report(meals: history.meals, symptoms: history.symptoms)
        #expect(report.findings.isEmpty, "n=2 must never produce a finding")
    }

    @Test("Four out of four is still not enough")
    func silentAtFour() {
        var history = SyntheticHistory()
        for day in 0..<4 {
            let meal = history.eat(day: day, hour: 12, groups: ["dairy"])
            history.feel(.bloating, after: meal, hours: 2)
        }
        for day in 4..<20 {
            _ = history.eat(day: day, hour: 12, groups: ["gluten"])
        }

        let report = CorrelationEngine().report(meals: history.meals, symptoms: history.symptoms)
        #expect(report.findings.isEmpty, "the floor is five exposures, not four")
    }

    /// Pure noise. Symptoms are scattered at random and have nothing to do with
    /// what was eaten; the engine must say so rather than find the strongest
    /// coincidence and dress it up.
    @Test("Random history yields no findings", arguments: [7, 13, 29, 101, 5_000] as [UInt64])
    func silentOnNoise(seed: UInt64) {
        var random = SyntheticHistory.Random(seed: seed)
        var history = SyntheticHistory()
        let groups = ["dairy", "gluten", "allium", "caffeine", "egg", "soy", "nightshade", "legume"]

        for day in 0..<90 {
            for hour in [8.0, 13.0, 19.0] {
                var chosen: Set<String> = []
                for group in groups where random.chance(0.3) { chosen.insert(group) }
                _ = history.eat(day: day, hour: hour, groups: chosen)
            }
            // Symptoms arrive on their own schedule, unrelated to any of it.
            if random.chance(0.35) {
                history.symptoms.append(
                    SymptomObservation(at: SyntheticHistory.day(day, hour: random.next() * 24),
                                       kind: .bloating)
                )
            }
        }

        let report = CorrelationEngine().report(meals: history.meals, symptoms: history.symptoms)
        #expect(report.findings.isEmpty,
                "seed \(seed) produced: \(report.findings.map { "\($0.trigger.name) \($0.summary)" })")
        #expect(report.silence == .nothingStandsOut)
    }

    /// Someone who has dairy at every single meal has no control group. Their
    /// dairy rate *is* their base rate, and comparing the two is circular.
    @Test("A trigger eaten at every meal cannot be assessed")
    func noControlGroup() {
        var history = SyntheticHistory()
        for day in 0..<60 {
            let meal = history.eat(day: day, hour: 12, groups: ["dairy"])
            if day % 2 == 0 { history.feel(.bloating, after: meal, hours: 2) }
        }

        let report = CorrelationEngine().report(meals: history.meals, symptoms: history.symptoms)
        #expect(!report.findings.contains { $0.trigger == .group("dairy") },
                "with nothing to compare against, dairy cannot be named")
    }

    /// Co-occurrence without a denominator is the classic way to be wrong:
    /// bread precedes every symptom because bread precedes everything.
    @Test("Co-occurrence without a raised rate is not a finding")
    func denominatorsMatter() {
        var history = SyntheticHistory()
        // Gluten twice a day, every day; bloating after 1 occasion in 10.
        for day in 0..<60 {
            let breakfast = history.eat(day: day, hour: 8, groups: ["gluten"])
            _ = history.eat(day: day, hour: 19, groups: ["gluten"])
            _ = history.eat(day: day, hour: 13, groups: ["legume"])
            if day % 10 == 0 { history.feel(.bloating, after: breakfast, hours: 2) }
        }

        let report = CorrelationEngine().report(meals: history.meals, symptoms: history.symptoms)
        #expect(!report.findings.contains { $0.trigger == .group("gluten") },
                "gluten precedes every symptom and still isn't the cause")
    }
}

@Suite("Finding what is actually there")
struct DetectionTests {

    /// A history with one real trigger in it, and the engine has to find it.
    private func historyWithDairyTrigger() -> SyntheticHistory {
        var history = SyntheticHistory()
        for day in 0..<80 {
            // Dairy twice a week, reliably followed by bloating about 2.5h later.
            if day % 7 == 1 || day % 7 == 4 {
                let meal = history.eat(day: day, hour: 12, groups: ["dairy"], foods: ["yogurt"])
                history.feel(.bloating, after: meal, hours: day % 3 == 0 ? 2.0 : 3.0)
            } else {
                _ = history.eat(day: day, hour: 12, groups: ["gluten"], foods: ["bread"])
            }
            _ = history.eat(day: day, hour: 19, groups: ["legume"], foods: ["lentils"])
        }
        return history
    }

    @Test("A real trigger is found and named")
    func findsTheTrigger() throws {
        let history = historyWithDairyTrigger()
        let report = CorrelationEngine().report(meals: history.meals, symptoms: history.symptoms)

        let top = try #require(report.findings.first)
        #expect(top.symptom == .bloating)
        #expect(top.trigger == .group("dairy") || top.trigger == .food("yogurt"))
        #expect(top.lift > 2, "the effect is large and should read as large")
        #expect(top.exposures >= 20)
    }

    @Test("Onset is a median, with the middle half alongside it")
    func onsetIsReported() throws {
        let history = historyWithDairyTrigger()
        let report = CorrelationEngine().report(meals: history.meals, symptoms: history.symptoms)
        let top = try #require(report.findings.first)

        #expect(top.onsetMedianHours >= 2 && top.onsetMedianHours <= 3)
        #expect(top.onsetRangeHours.lowerBound <= top.onsetMedianHours)
        #expect(top.onsetRangeHours.upperBound >= top.onsetMedianHours)
    }

    /// A single symptom logged the following morning must not drag the reported
    /// onset out to a time when nothing happened. This is why it is a median.
    @Test("One late outlier doesn't move the typical onset")
    func medianResistsOutliers() throws {
        var history = historyWithDairyTrigger()
        if let lastDairy = history.meals.last(where: { $0.groups.contains("dairy") }) {
            history.symptoms.append(
                SymptomObservation(at: lastDairy.at.addingTimeInterval(5.5 * 3600), kind: .bloating)
            )
        }
        let report = CorrelationEngine().report(meals: history.meals, symptoms: history.symptoms)
        let top = try #require(report.findings.first)
        #expect(top.onsetMedianHours < 3.5, "a mean would have been dragged upward")
    }

    @Test("The sample size travels with the claim")
    func summaryLeadsWithSampleSize() throws {
        let history = historyWithDairyTrigger()
        let report = CorrelationEngine().report(meals: history.meals, symptoms: history.symptoms)
        let top = try #require(report.findings.first)

        #expect(top.summary.contains("of \(top.exposures) occasions"))
        #expect(top.hits <= top.exposures)
        #expect(top.interval.lowerBound <= top.estimatedRate)
        #expect(top.interval.upperBound >= top.estimatedRate)
    }

    /// Bread and butter always arrive together. No amount of *this* data
    /// separates them, and the honest output names both.
    @Test("Inseparable triggers are named as inseparable")
    func confoundersAreDeclared() throws {
        var history = SyntheticHistory()
        for day in 0..<80 {
            if day % 3 == 0 {
                let meal = history.eat(day: day, hour: 8, groups: ["gluten", "dairy"])
                history.feel(.bloating, after: meal, hours: 2)
            } else {
                _ = history.eat(day: day, hour: 8, groups: ["legume"])
            }
            _ = history.eat(day: day, hour: 19, groups: ["nightshade"])
        }

        let report = CorrelationEngine().report(meals: history.meals, symptoms: history.symptoms)
        let gluten = try #require(report.findings.first { $0.trigger == .group("gluten") })
        #expect(gluten.indistinguishableFrom.contains(.group("dairy")),
                "bread and butter can't be told apart and the finding must say so")
    }
}

@Suite("Eating occasions")
struct OccasionTests {

    /// Two dairy meals an hour apart followed by one symptom is one exposure
    /// and one hit — not two of each. Counting them twice inflates confidence
    /// out of a habit of snacking.
    @Test("Meals close together are one exposure")
    func mealsCoalesce() {
        var history = SyntheticHistory()
        _ = history.eat(day: 0, hour: 12, groups: ["dairy"])
        _ = history.eat(day: 0, hour: 13, groups: ["dairy"])
        _ = history.eat(day: 0, hour: 19, groups: ["dairy"])

        let engine = CorrelationEngine()
        #expect(engine.occasions(from: history.meals).count == 2)
    }

    @Test("A symptom before the meal is not caused by it")
    func symptomsBeforeDontCount() {
        var history = SyntheticHistory()
        for day in 0..<40 {
            let meal = history.eat(day: day, hour: 14, groups: ["dairy"])
            // Logged two hours *before* eating.
            history.symptoms.append(SymptomObservation(at: meal.addingTimeInterval(-7200), kind: .nausea))
            _ = history.eat(day: day, hour: 20, groups: ["soy"])
        }

        let report = CorrelationEngine().report(meals: history.meals, symptoms: history.symptoms)
        #expect(!report.findings.contains { $0.trigger == .group("dairy") && $0.symptom == .nausea })
    }
}
