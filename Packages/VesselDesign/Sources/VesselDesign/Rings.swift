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
/// you've logged two of three meals, not 66.7% of a meal. Showing it as a
/// smooth sweep would misrepresent what the number means.
///
/// The three states are distinguished by colour *and* by form, so the ring
/// still reads correctly in greyscale and for colour-vision deficiency:
/// in progress is a warm ember, met is a closed green ring with a tick, and
/// at risk keeps the ember but breathes.
public struct StreakRing: View {
    private let logged: Int
    private let required: Int
    private let tint: Color
    private let lineWidth: CGFloat
    private let isAtRisk: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

    private var isComplete: Bool { logged >= required }
    private var activeTint: Color { isComplete ? Palette.positive : tint }

    /// Gap between segments, as a fraction of the circle.
    ///
    /// Generous on purpose — each arc should read as *one meal*, a separate
    /// thing you either did or didn't do, rather than as a progress bar that
    /// happens to be dashed. Scaled down as segments multiply so a five-meal
    /// plan doesn't dissolve into ticks.
    private var gapFraction: Double {
        min(0.085, 0.30 / Double(required))
    }

    private var segmentFraction: Double {
        (1.0 / Double(required)) - gapFraction
    }

    /// A warm two-stop ramp. Flat orange reads as a progress bar bent into a
    /// circle; a ramp reads as something burning down.
    private var fillGradient: AngularGradient {
        AngularGradient(
            gradient: Gradient(colors: isComplete
                ? [Palette.positive, Palette.positive.opacity(0.75), Palette.positive]
                : [tint, Color(hex: 0xE8562E), tint]),
            center: .center,
            startAngle: .degrees(-90),
            endAngle: .degrees(270)
        )
    }

    public var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)

            ZStack {
                // A barely-there disc so the ring sits on something rather than
                // floating on the card.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [activeTint.opacity(0.10), activeTint.opacity(0.01)],
                            center: .center,
                            startRadius: 0,
                            endRadius: size / 2
                        )
                    )

                // Unfilled track, drawn per segment so the gaps line up exactly
                // with the filled ones.
                ForEach(0..<required, id: \.self) { index in
                    segment(index: index)
                        .stroke(
                            activeTint.opacity(0.14),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                        )
                }

                // Filled segments, with a soft bloom underneath so the ring has
                // some depth instead of sitting flat on the card.
                ForEach(0..<min(logged, required), id: \.self) { index in
                    segment(index: index)
                        .stroke(fillGradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .shadow(color: activeTint.opacity(0.35), radius: 5, y: 1)
                }
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .modifier(AtRiskPulse(isActive: isAtRisk && !isComplete, tint: tint))
        .vesselAnimation(Motion.celebrate, value: logged)
        .accessibilityElement()
        .accessibilityLabel("Meals logged today")
        .accessibilityValue("\(logged) of \(required)")
    }

    private func segment(index: Int) -> some Shape {
        let start = Double(index) / Double(required) + gapFraction / 2
        return Circle()
            .trim(from: start, to: start + segmentFraction)
            .rotation(.degrees(-90))
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

/// The day's meals, named and ticked off.
///
/// Sits beside the streak ring rather than inside it. Crowded into the ring the
/// icons collided with the streak count and were too small to read; given their
/// own row they answer the question the ring can't — *which* meal is missing.
public struct MealProgressRow: View {

    /// One meal: its symbol, its name, and whether it's logged.
    public struct Meal: Identifiable, Hashable, Sendable {
        public let symbol: String
        public let title: String
        public let isLogged: Bool

        public var id: String { title }

        public init(symbol: String, title: String, isLogged: Bool) {
            self.symbol = symbol
            self.title = title
            self.isLogged = isLogged
        }
    }

    private let meals: [Meal]
    private let tint: Color

    public init(meals: [Meal], tint: Color = Palette.streak) {
        self.meals = meals
        self.tint = tint
    }

    public var body: some View {
        HStack(spacing: Layout.sm) {
            ForEach(meals) { meal in
                VStack(spacing: 5) {
                    ZStack {
                        Circle()
                            .fill(meal.isLogged ? tint.opacity(0.16) : Palette.separator.opacity(0.28))
                            .frame(width: 34, height: 34)

                        // Outlined while outstanding, filled once logged — the
                        // progress is legible from the icons alone, without
                        // relying on colour.
                        Image(systemName: meal.isLogged
                              ? meal.symbol
                              : (meal.symbol.hasSuffix(".fill")
                                 ? String(meal.symbol.dropLast(5))
                                 : meal.symbol))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(meal.isLogged ? tint : Palette.inkTertiary)
                    }

                    // Wraps rather than shrinks: shrunk to fit, "Breakfast"
                    // was smaller than the text the user asked for.
                    Text(meal.title)
                        .font(Typography.caption)
                        .foregroundStyle(meal.isLogged ? Palette.inkSecondary : Palette.inkTertiary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(meal.title): \(meal.isLogged ? "logged" : "not yet")")
            }
        }
    }
}
