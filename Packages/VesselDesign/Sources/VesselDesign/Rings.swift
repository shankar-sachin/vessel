import SwiftUI

/// A circular progress arc.
///
/// Rings rather than bars for the day's headline numbers: a ring's remaining gap
/// is readable at a glance from across a room, which is how people actually
/// check a tracker.
public struct ProgressRing: View {
    private let progress: Double
    private let tint: Color
    private let lineWidth: CGFloat
    private let trackOpacity: Double
    /// Draws past 100% as a second lap in a darker shade, so exceeding a goal
    /// stays visible instead of silently pinning at full.
    private let showsOverflow: Bool

    public init(
        progress: Double,
        tint: Color,
        lineWidth: CGFloat = 12,
        trackOpacity: Double = 0.15,
        showsOverflow: Bool = true
    ) {
        self.progress = progress
        self.tint = tint
        self.lineWidth = lineWidth
        self.trackOpacity = trackOpacity
        self.showsOverflow = showsOverflow
    }

    private var firstLap: Double { min(max(progress, 0), 1) }
    private var overflow: Double { min(max(progress - 1, 0), 1) }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(trackOpacity), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: firstLap)
                .stroke(
                    AngularGradient(
                        colors: [tint.opacity(0.75), tint],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            if showsOverflow && overflow > 0 {
                Circle()
                    .trim(from: 0, to: overflow)
                    .stroke(tint.opacity(0.45), style: StrokeStyle(lineWidth: lineWidth * 0.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .vesselAnimation(Motion.deliberate, value: progress)
    }
}

/// The streak ring: one segment per meal required today.
///
/// Segments rather than a continuous arc because the requirement is discrete —
/// you've logged two of three meals, not 66.7% of a meal. Showing it as a smooth
/// sweep would misrepresent what the number means.
public struct StreakRing: View {
    private let logged: Int
    private let required: Int
    private let tint: Color
    private let lineWidth: CGFloat
    private let isAtRisk: Bool

    public init(
        logged: Int,
        required: Int,
        tint: Color = Palette.streak,
        lineWidth: CGFloat = 14,
        isAtRisk: Bool = false
    ) {
        self.logged = logged
        self.required = max(1, required)
        self.tint = tint
        self.lineWidth = lineWidth
        self.isAtRisk = isAtRisk
    }

    /// Gap between segments, as a fraction of the circle. Scales down as segments
    /// multiply so a five-meal plan doesn't turn into dashes.
    private var gapFraction: Double {
        min(0.04, 0.12 / Double(required))
    }

    private var segmentFraction: Double {
        (1.0 / Double(required)) - gapFraction
    }

    public var body: some View {
        ZStack {
            ForEach(0..<required, id: \.self) { index in
                let start = Double(index) / Double(required) + gapFraction / 2
                let filled = index < logged

                Circle()
                    .trim(from: start, to: start + segmentFraction)
                    .stroke(
                        filled ? tint : tint.opacity(0.16),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
        }
        // A gentle pulse when the deadline is near. Reduce Motion users get a
        // static ring — the warning is also carried by color and text, never by
        // motion alone.
        .modifier(AtRiskPulse(isActive: isAtRisk, tint: tint))
        .vesselAnimation(Motion.celebrate, value: logged)
        .accessibilityElement()
        .accessibilityLabel("Meals logged today")
        .accessibilityValue("\(logged) of \(required)")
    }
}

private struct AtRiskPulse: ViewModifier {
    let isActive: Bool
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    func body(content: Content) -> some View {
        content
            .shadow(color: isActive ? tint.opacity(pulsing ? 0.55 : 0.15) : .clear, radius: pulsing ? 14 : 6)
            .onAppear {
                guard isActive, !reduceMotion else { return }
                withAnimation(Motion.ambient) { pulsing = true }
            }
            .onChange(of: isActive) { _, active in
                guard !reduceMotion else { return }
                if active {
                    withAnimation(Motion.ambient) { pulsing = true }
                } else {
                    withAnimation(Motion.standard) { pulsing = false }
                }
            }
    }
}

/// Concentric rings for the three macros — protein, carbs, fat at a glance.
public struct MacroRings: View {
    private let protein: Double
    private let carbs: Double
    private let fat: Double
    private let lineWidth: CGFloat

    public init(protein: Double, carbs: Double, fat: Double, lineWidth: CGFloat = 8) {
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.lineWidth = lineWidth
    }

    public var body: some View {
        ZStack {
            ProgressRing(progress: protein, tint: Palette.protein, lineWidth: lineWidth)
            ProgressRing(progress: carbs, tint: Palette.carbs, lineWidth: lineWidth)
                .padding(lineWidth + 4)
            ProgressRing(progress: fat, tint: Palette.fat, lineWidth: lineWidth)
                .padding((lineWidth + 4) * 2)
        }
    }
}

#Preview("Rings") {
    VStack(spacing: 32) {
        StreakRing(logged: 2, required: 3, isAtRisk: true).frame(width: 120, height: 120)
        MacroRings(protein: 0.7, carbs: 0.45, fat: 1.2).frame(width: 120, height: 120)
    }
    .padding(40)
    .background(Palette.ground)
}

/// A linear macro meter.
///
/// Replaces concentric rings where legibility matters more than compactness:
/// three nested rings look elegant at a glance but are genuinely hard to read,
/// because each one has a different circumference and the eye can't compare arc
/// lengths across them. Bars share a baseline and a scale, so they can.
public struct MacroBar: View {
    private let name: String
    private let value: Double
    private let goal: Double?
    private let tint: Color

    public init(name: String, value: Double, goal: Double?, tint: Color) {
        self.name = name
        self.value = value
        self.goal = goal
        self.tint = tint
    }

    private var fraction: Double {
        guard let goal, goal > 0 else { return 0 }
        return min(1, value / goal)
    }

    private var isOver: Bool {
        guard let goal, goal > 0 else { return false }
        return value > goal
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: Layout.xs) {
                Text(name)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkSecondary)
                Spacer(minLength: Layout.xs)
                Text("\(Int(value.rounded()))")
                    .font(Typography.numeric)
                    .foregroundStyle(Palette.ink)
                if let goal {
                    Text("/ \(Int(goal))g")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.inkTertiary)
                } else {
                    Text("g")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.inkTertiary)
                }
            }

            // Only draw a meter when there's a goal to measure against. An empty
            // track with nothing in it reads as a rendering bug rather than as
            // "you haven't set a target", so we show the number alone instead.
            if goal != nil {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(tint.opacity(0.16))
                        Capsule()
                            .fill(tint)
                            .frame(width: max(fraction > 0 ? 4 : 0, geo.size.width * fraction))
                        // Exceeding a goal is marked rather than clipped, so "over"
                        // never looks identical to "exactly met".
                        if isOver {
                            Capsule()
                                .strokeBorder(Palette.caution, lineWidth: 1.5)
                        }
                    }
                }
                .frame(height: 6)
            } else {
                Capsule()
                    .fill(tint.opacity(0.25))
                    .frame(width: 22, height: 3)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(name)
        .accessibilityValue(goal.map { "\(Int(value)) of \(Int($0)) grams" } ?? "\(Int(value)) grams")
    }
}
