import SwiftUI
import SwiftData
import VesselCore
import VesselDesign
import VesselInsights

/// The Date Log's conclusions — the reason the four journals share an app.
///
/// Everything here is built to be doubted. The sample size sits next to every
/// claim, the credible range is drawn rather than described, and when two foods
/// can't be told apart the card says so instead of picking one. A health app
/// that states findings without their uncertainty is not being confident, it is
/// withholding the part that decides whether to act.
struct InsightsSection: View {

    let meals: [FoodEntry]
    let drinks: [WaterEntry]
    let symptoms: [SymptomEntry]

    @State private var report: InsightsReport = .empty

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.md) {
            header

            if let silence = report.silence {
                SilenceCard(silence: silence, symptomCount: report.symptomCount)
            } else {
                ForEach(report.findings.prefix(5)) { finding in
                    FindingCard(finding: finding)
                }
                disclaimer
            }
        }
        // Recomputed when the log changes, not on every redraw — the engine is
        // fast, but not free, and a scroll shouldn't re-derive anyone's health.
        .task(id: signature) { recompute() }
    }

    private var signature: String {
        "\(meals.count)-\(drinks.count)-\(symptoms.count)-\(symptoms.first?.id.uuidString ?? "")"
    }

    private func recompute() {
        let observations = History.observations(from: meals) + History.observations(from: drinks)
        report = CorrelationEngine().report(
            meals: observations,
            symptoms: History.observations(from: symptoms)
        )
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Label("What your log suggests", systemImage: "chart.dots.scatter")
                .font(Typography.heading)
                .foregroundStyle(Palette.ink)
            Spacer()
            if !report.findings.isEmpty {
                Text("\(report.occasionCount) occasions")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkTertiary)
            }
        }
    }

    private var disclaimer: some View {
        Text("These are patterns in your own log, not a diagnosis. "
             + "Foods affect people differently, and a pattern here is a question worth asking — "
             + "not an answer. Talk to a clinician before cutting anything out.")
            .font(Typography.caption)
            .foregroundStyle(Palette.inkTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, Layout.xs)
    }
}

/// One suggested relationship.
private struct FindingCard: View {
    let finding: Finding

    var body: some View {
        VesselCard {
            VStack(alignment: .leading, spacing: Layout.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Text(finding.trigger.title)
                        .font(Typography.title)
                        .foregroundStyle(Palette.ink)
                    Text("→")
                        .foregroundStyle(Palette.inkTertiary)
                    Label(finding.symptom.title, systemImage: finding.symptom.symbol)
                        .font(Typography.bodyEmphasis)
                        .foregroundStyle(Palette.symptom)
                    Spacer()
                }

                // The sentence the whole feature exists to produce, and the one
                // place a bare percentage would have been easier and worse.
                Text(finding.summary)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.inkSecondary)

                RateBar(finding: finding)

                Text("Usually \(finding.symptom.title.lowercased()) follows "
                     + "\(Int((finding.baseRate * 100).rounded()))% of your meals; "
                     + "after \(finding.trigger.title.lowercased()), "
                     + "\(Int((finding.estimatedRate * 100).rounded()))%.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                if !finding.indistinguishableFrom.isEmpty {
                    let names = finding.indistinguishableFrom.map(\.title).joined(separator: ", ")
                    Label(
                        "Almost always eaten with \(names), so this log can't separate them. "
                        + "Having one without the other would.",
                        systemImage: "arrow.triangle.branch"
                    )
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(finding.trigger.title), \(finding.symptom.title). \(finding.summary)."
        )
    }
}

/// The estimate, its credible range, and the ordinary rate to compare against.
///
/// Drawn rather than written because the interval is the point: a wide band on
/// a short log says "we don't really know yet" in a way that no number does.
private struct RateBar: View {
    let finding: Finding

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Palette.symptom.opacity(0.12))
                    .frame(height: 8)

                Capsule()
                    .fill(Palette.symptom.opacity(0.45))
                    .frame(
                        width: max(4, width * (finding.interval.upperBound - finding.interval.lowerBound)),
                        height: 8
                    )
                    .offset(x: width * finding.interval.lowerBound)

                Circle()
                    .fill(Palette.symptom)
                    .frame(width: 10, height: 10)
                    .offset(x: max(0, width * finding.estimatedRate - 5))

                // Where this symptom normally sits, so the bar is a comparison
                // rather than a score.
                Rectangle()
                    .fill(Palette.inkTertiary)
                    .frame(width: 1.5, height: 14)
                    .offset(x: width * finding.baseRate)
            }
            .frame(height: 14)
        }
        .frame(height: 14)
        .accessibilityElement()
        .accessibilityLabel("Estimated rate")
        .accessibilityValue(
            "\(Int((finding.estimatedRate * 100).rounded())) percent, "
            + "somewhere between \(Int((finding.interval.lowerBound * 100).rounded())) "
            + "and \(Int((finding.interval.upperBound * 100).rounded())); "
            + "normally \(Int((finding.baseRate * 100).rounded())) percent"
        )
    }
}

/// What to say when there is nothing to say.
///
/// "No patterns found" is three different situations wearing one label, and the
/// difference matters: one of them means keep logging, one means your log looks
/// clean, and one means you haven't recorded a reaction yet.
private struct SilenceCard: View {
    let silence: InsightsReport.Silence
    let symptomCount: Int

    var body: some View {
        VesselCard {
            VStack(alignment: .leading, spacing: Layout.sm) {
                Label(title, systemImage: symbol)
                    .font(Typography.heading)
                    .foregroundStyle(Palette.ink)
                Text(message)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var title: String {
        switch silence {
        case .noSymptoms:       return "Nothing to look for yet"
        case .notEnoughHistory: return "Still gathering"
        case .nothingStandsOut: return "Nothing stands out"
        }
    }

    private var symbol: String {
        switch silence {
        case .noSymptoms:       return "tray"
        case .notEnoughHistory: return "hourglass"
        case .nothingStandsOut: return "checkmark.circle"
        }
    }

    private var message: String {
        switch silence {
        case .noSymptoms:
            return "Log how you feel after eating and Vessel will start looking for what precedes it."
        case .notEnoughHistory(let days):
            return "\(days) day\(days == 1 ? "" : "s") of log so far, and \(symptomCount) "
                + "reaction\(symptomCount == 1 ? "" : "s"). A few weeks of both is where "
                + "patterns start to mean something rather than just look like something."
        case .nothingStandsOut:
            return "No food in your log precedes a reaction more often than the rest do. "
                + "That is a real result, not a missing one — and it's the one most people get."
        }
    }
}
