import ActivityKit
import WidgetKit
import SwiftUI
import VesselActivities
import VesselDesign

/// The streak countdown, on the Lock Screen and in the Dynamic Island.
///
/// Every time display uses `Text(timerInterval:)` rather than a string we
/// compute. That matters: the system re-renders the countdown itself, once a
/// second, without waking our process. Formatting it ourselves would mean the
/// number freezing the moment iOS stops giving the extension time.
struct StreakLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: StreakActivityAttributes.self) { context in
            LockScreenView(context: context)
                // Deliberately a deep neutral rather than the app's parchment
                // ground: this sits over whatever wallpaper the user has, and a
                // near-white tint disappears against a light photo.
                .activityBackgroundTint(Color(hex: 0x1C1A18).opacity(0.86))
                .activitySystemActionForegroundColor(Palette.streak)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ExpandedLeading(context: context)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ExpandedTrailing(context: context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedBottom(context: context)
                }
            } compactLeading: {
                Image(systemName: iconName(context))
                    .foregroundStyle(Palette.streak)
            } compactTrailing: {
                // Once complete there's nothing to count down to, so the island
                // shows the achieved state instead of a redundant timer.
                if isComplete(context) {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Palette.positive)
                } else {
                    Text(timerInterval: Date()...context.attributes.deadline, countsDown: true)
                        .monospacedDigit()
                        .frame(maxWidth: 52)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(Palette.streak)
                }
            } minimal: {
                Image(systemName: iconName(context))
                    .foregroundStyle(isComplete(context) ? Palette.positive : Palette.streak)
            }
            // Tapping anywhere opens the app to log the missing meal.
            .widgetURL(URL(string: "vessel://log/food"))
            .keylineTint(Palette.streak)
        }
    }

    private func isComplete(_ context: ActivityViewContext<StreakActivityAttributes>) -> Bool {
        context.attributes.isComplete(context.state)
    }

    private func iconName(_ context: ActivityViewContext<StreakActivityAttributes>) -> String {
        isComplete(context) ? "checkmark.circle.fill" : "flame.fill"
    }
}

// MARK: - Lock Screen

private struct LockScreenView: View {
    let context: ActivityViewContext<StreakActivityAttributes>

    private var remaining: Int { context.attributes.remaining(for: context.state) }
    private var isComplete: Bool { context.attributes.isComplete(context.state) }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                MealPipsRing(
                    logged: context.state.logged,
                    required: context.attributes.required,
                    tint: isComplete ? Palette.positive : Palette.streak
                )
                Image(systemName: isComplete ? "checkmark" : "flame.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isComplete ? Palette.positive : Palette.streak)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text(StreakActivityCopy.headline(
                    logged: context.state.logged,
                    required: context.attributes.required,
                    streak: context.state.streakCount
                ))
                .font(.headline)
                .foregroundStyle(.white)

                Text(StreakActivityCopy.detail(
                    logged: context.state.logged,
                    required: context.attributes.required,
                    nextSlot: context.state.nextSlotName
                ))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.75))
            }

            Spacer(minLength: 4)

            if !isComplete {
                VStack(spacing: 1) {
                    Text(timerInterval: Date()...context.attributes.deadline, countsDown: true)
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(Palette.streak)
                    Text("left")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .frame(maxWidth: 88)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Dynamic Island regions

private struct ExpandedLeading: View {
    let context: ActivityViewContext<StreakActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                Text("\(context.state.streakCount)")
                    .monospacedDigit()
            }
            .font(.system(.title3, design: .rounded, weight: .bold))
            .foregroundStyle(Palette.streak)

            Text(context.state.streakCount == 1 ? "day" : "days")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.leading, 4)
    }
}

private struct ExpandedTrailing: View {
    let context: ActivityViewContext<StreakActivityAttributes>

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            if context.attributes.isComplete(context.state) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Palette.positive)
            } else {
                Text(timerInterval: Date()...context.attributes.deadline, countsDown: true)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(Palette.streak)
                Text("until reset")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.trailing, 4)
    }
}

private struct ExpandedBottom: View {
    let context: ActivityViewContext<StreakActivityAttributes>

    var body: some View {
        VStack(spacing: 8) {
            Text(StreakActivityCopy.detail(
                logged: context.state.logged,
                required: context.attributes.required,
                nextSlot: context.state.nextSlotName
            ))
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.75))
            .frame(maxWidth: .infinity, alignment: .leading)

            MealPipsRow(
                logged: context.state.logged,
                required: context.attributes.required,
                tint: context.attributes.isComplete(context.state) ? Palette.positive : Palette.streak
            )
        }
        .padding(.top, 2)
    }
}

// MARK: - Shared bits

/// One segment per required meal — the same discrete language as the ring in the
/// app, so the island and the Today screen visibly describe the same thing.
private struct MealPipsRing: View {
    let logged: Int
    let required: Int
    let tint: Color

    var body: some View {
        ZStack {
            ForEach(0..<max(1, required), id: \.self) { index in
                let gap = min(0.05, 0.15 / Double(max(1, required)))
                let start = Double(index) / Double(max(1, required)) + gap / 2
                Circle()
                    .trim(from: start, to: start + (1.0 / Double(max(1, required))) - gap)
                    .stroke(
                        index < logged ? tint : tint.opacity(0.22),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
        }
    }
}

private struct MealPipsRow: View {
    let logged: Int
    let required: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<max(1, required), id: \.self) { index in
                Capsule()
                    .fill(index < logged ? tint : tint.opacity(0.22))
                    .frame(height: 5)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Meals logged")
        .accessibilityValue("\(logged) of \(required)")
    }
}
