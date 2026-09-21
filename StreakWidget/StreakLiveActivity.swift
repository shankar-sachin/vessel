import ActivityKit
import WidgetKit
import SwiftUI
import VesselActivities
import VesselDesign

/// The streak countdown, on the Lock Screen and in the Dynamic Island.
///
/// Designed around one question — *what do I still have to eat today?* — so it
/// draws the day as actual meals rather than a bar and a number. Seeing that
/// breakfast and lunch are filled and dinner isn't answers that instantly;
/// "2/3" makes you work it out.
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
                .activityBackgroundTint(Color(hex: 0x14120F).opacity(0.92))
                .activitySystemActionForegroundColor(Palette.streak)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    StreakBadge(context: context)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    CountdownBadge(context: context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    MealTrack(context: context, compact: false)
                }
            } compactLeading: {
                // A filling ring rather than a flat glyph: the compact island is
                // four points of information wide, and a ring spends them on
                // progress instead of decoration.
                MealRing(context: context, lineWidth: 3)
                    .frame(width: 20, height: 20)
            } compactTrailing: {
                if context.attributes.isComplete(context.state) {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Palette.positive)
                } else {
                    Text(timerInterval: Date()...context.attributes.deadline, countsDown: true)
                        .monospacedDigit()
                        .frame(maxWidth: 50)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(tint(context))
                }
            } minimal: {
                MealRing(context: context, lineWidth: 3)
                    .frame(width: 20, height: 20)
            }
            .widgetURL(URL(string: "vessel://log/food"))
            .keylineTint(tint(context))
        }
    }

    private func tint(_ context: ActivityViewContext<StreakActivityAttributes>) -> Color {
        context.attributes.isComplete(context.state) ? Palette.positive : Palette.streak
    }
}

// MARK: - Lock Screen

private struct LockScreenView: View {
    let context: ActivityViewContext<StreakActivityAttributes>

    private var isComplete: Bool { context.attributes.isComplete(context.state) }
    private var tint: Color { isComplete ? Palette.positive : Palette.streak }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    MealRing(context: context, lineWidth: 5)
                    VStack(spacing: -2) {
                        Text("\(context.state.streakCount)")
                            .font(.system(size: 19, design: .rounded).weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(tint)
                        Text("day")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .frame(width: 54, height: 54)

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
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(2)
                }

                Spacer(minLength: 4)

                if !isComplete {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(timerInterval: Date()...context.attributes.deadline, countsDown: true)
                            .font(.system(size: 22, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(tint)
                        Text("left")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .frame(maxWidth: 92)
                }
            }

            MealTrack(context: context, compact: false)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - Dynamic Island regions

private struct StreakBadge: View {
    let context: ActivityViewContext<StreakActivityAttributes>

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill")
                .font(.system(size: 17))
                .foregroundStyle(
                    // A two-stop gradient reads as a flame rather than a
                    // flame-shaped block of orange.
                    LinearGradient(
                        colors: [Palette.streak, Color(hex: 0xE8562E)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            VStack(alignment: .leading, spacing: -2) {
                Text("\(context.state.streakCount)")
                    .font(.system(size: 20, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text(context.state.streakCount == 1 ? "day" : "days")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.leading, 4)
    }
}

private struct CountdownBadge: View {
    let context: ActivityViewContext<StreakActivityAttributes>

    var body: some View {
        VStack(alignment: .trailing, spacing: -1) {
            if context.attributes.isComplete(context.state) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Palette.positive)
            } else {
                Text(timerInterval: Date()...context.attributes.deadline, countsDown: true)
                    .font(.system(size: 20, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(Palette.streak)
                Text("until reset")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.trailing, 4)
    }
}

// MARK: - Shared pieces

/// The day drawn as its actual meals.
///
/// Each slot gets its own icon — sunrise, sun, moon — so a glance says *dinner
/// is missing*, not *one of three is missing*. Anonymous pips force the reader
/// to do that mapping themselves.
private struct MealTrack: View {
    let context: ActivityViewContext<StreakActivityAttributes>
    let compact: Bool

    private var slots: [String] {
        let planned = context.state.planSlots
        // Older activities, or an unusual plan, may not carry slot names.
        // Fall back to unnamed placeholders rather than drawing nothing.
        guard !planned.isEmpty else {
            return Array(repeating: "", count: max(1, context.attributes.required))
        }
        return planned
    }

    private var logged: Set<String> { Set(context.state.loggedSlots) }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(slots.enumerated()), id: \.offset) { index, slot in
                let isDone = slot.isEmpty ? index < context.state.logged : logged.contains(slot)

                HStack(spacing: 5) {
                    Image(systemName: slot.isEmpty
                          ? (isDone ? "checkmark" : "circle")
                          : StreakActivityAttributes.ContentState.symbol(forSlot: slot))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isDone ? .white : .white.opacity(0.4))

                    if !compact, !slot.isEmpty {
                        Text(StreakActivityAttributes.ContentState.title(forSlot: slot))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(isDone ? .white : .white.opacity(0.45))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(
                        isDone
                            ? AnyShapeStyle(LinearGradient(
                                colors: [Palette.streak, Color(hex: 0xE8562E)],
                                startPoint: .leading, endPoint: .trailing))
                            : AnyShapeStyle(Color.white.opacity(0.12))
                    )
                )
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Meals logged today")
        .accessibilityValue("\(context.state.logged) of \(context.attributes.required)")
    }
}

/// One segment per required meal, filled as they're logged.
private struct MealRing: View {
    let context: ActivityViewContext<StreakActivityAttributes>
    let lineWidth: CGFloat

    private var required: Int { max(1, context.attributes.required) }
    private var logged: Int { context.state.logged }
    private var isComplete: Bool { context.attributes.isComplete(context.state) }
    private var tint: Color { isComplete ? Palette.positive : Palette.streak }

    var body: some View {
        ZStack {
            ForEach(0..<required, id: \.self) { index in
                let gap = min(0.06, 0.18 / Double(required))
                let start = Double(index) / Double(required) + gap / 2
                Circle()
                    .trim(from: start, to: start + (1.0 / Double(required)) - gap)
                    .stroke(
                        index < logged
                            ? AnyShapeStyle(LinearGradient(
                                colors: [tint, isComplete ? tint : Color(hex: 0xE8562E)],
                                startPoint: .topLeading, endPoint: .bottomTrailing))
                            : AnyShapeStyle(tint.opacity(0.22)),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
        }
    }
}
