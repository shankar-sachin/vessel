import SwiftUI

/// The app's signature visual: a volume of liquid that fills a shape, with a
/// surface that actually moves.
///
/// Two sine waves of different wavelength, amplitude and speed are summed. A
/// single sine reads as a cartoon; two summed at non-harmonic speeds never
/// visibly repeat, which is what makes it read as real liquid.
///
/// ### Why the animation is hand-rolled
///
/// `Canvas` draws with whatever value its closure captures at body evaluation —
/// SwiftUI does not re-run it once per frame, so a `withAnimation` around the
/// level would make the liquid *jump* rather than rise. Instead the level is
/// solved analytically from a damped-spring step response, sampled against the
/// `TimelineView` clock that's already driving the waves. That costs nothing
/// extra and buys exact control over how the liquid settles.
public struct LiquidFill: View {

    /// How full, 0...1.
    private let progress: Double
    private let tint: Color
    /// Waves stand still when false — used for previews and snapshots, and
    /// automatically when Reduce Motion is on.
    private let isAnimated: Bool

    /// Bumped by the caller each time liquid is added, to trigger a splash.
    /// Any change in value counts; the number itself is meaningless.
    private let splashToken: Int

    /// The band of the container's height that 0...1 progress maps onto.
    ///
    /// A carafe's neck is no place for a surface: mapped over the full height,
    /// 85% of the goal put the liquid in the shoulder, where the clip turned
    /// the waves into a V and the wide body below read as a solid slab. The
    /// water screen maps the goal to the top of the body instead, and lets a
    /// day over its goal rise a little further.
    private let levelRange: ClosedRange<Double>

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The in-flight level transition: where it started, where it's heading, and
    /// when it began. Everything about the motion is derived from these three.
    @State private var transition: LevelTransition
    /// When the last splash was triggered, or nil if none yet.
    @State private var splashStart: Date?

    public init(
        progress: Double,
        tint: Color = Palette.water,
        isAnimated: Bool = true,
        splashToken: Int = 0,
        levelRange: ClosedRange<Double> = 0...1
    ) {
        self.progress = progress
        self.tint = tint
        self.isAnimated = isAnimated
        self.splashToken = splashToken
        self.levelRange = levelRange
        let clamped = Self.level(for: progress, in: levelRange)
        // Start settled at the initial value, so the first render isn't an
        // animation from empty.
        _transition = State(initialValue: LevelTransition(from: clamped, to: clamped, start: .distantPast))
    }

    private var target: Double { Self.level(for: progress, in: levelRange) }

    /// Progress mapped into the fill band. Up to 15% over the goal still
    /// shows, so a good day visibly exceeds the line rather than stopping flat.
    private static func level(for progress: Double, in range: ClosedRange<Double>) -> Double {
        let span = range.upperBound - range.lowerBound
        let over = range == 0...1 ? 1.0 : 1.15
        let clamped = min(max(progress, 0), over)
        guard clamped > 0 else { return 0 }
        return min(1, range.lowerBound + clamped * span)
    }

    public var body: some View {
        GeometryReader { geo in
            Group {
                if isAnimated && !reduceMotion {
                    TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                        canvas(size: geo.size, now: timeline.date)
                    }
                } else {
                    // Frozen, level surface — a static render should look
                    // intentional rather than caught mid-wave.
                    canvas(size: geo.size, now: .distantPast, staticLevel: target)
                }
            }
        }
        .onChange(of: progress) { oldValue, newValue in
            // Re-aim the spring from wherever the liquid currently is, so a
            // second drink logged mid-rise continues smoothly instead of
            // snapping back to start.
            let current = transition.level(at: Date(), reduceMotion: reduceMotion)
            transition = LevelTransition(from: current, to: Self.level(for: newValue, in: levelRange), start: Date())
        }
        .onChange(of: splashToken) { _, _ in
            guard !reduceMotion else { return }
            splashStart = Date()
        }
        .accessibilityElement()
        .accessibilityLabel("Fill level")
        .accessibilityValue("\(Int((min(max(progress, 0), 1) * 100).rounded())) percent")
    }

    private func canvas(size: CGSize, now: Date, staticLevel: Double? = nil) -> some View {
        let level = staticLevel ?? transition.level(at: now, reduceMotion: reduceMotion)
        let splash = staticLevel != nil ? 0 : splashIntensity(at: now)
        let drop = staticLevel != nil ? nil : dropProgress(at: now)
        let time = now.timeIntervalSinceReferenceDate

        return Canvas { context, canvasSize in
            guard canvasSize.width > 0, canvasSize.height > 0 else { return }

            let surfaceY = canvasSize.height * (1 - level)

            // Waves flatten as the vessel approaches full — a nearly-full
            // container has little room to slosh, and a big wave at the brim
            // looks wrong. A splash temporarily overrides that calm.
            let calm = 1.0 - (level * 0.5)
            let baseAmplitude = min(canvasSize.height * 0.026, 7) * calm * (1 + splash * 1.7)
            // Fresh liquid moves faster before it settles.
            let speed = 1.0 + splash * 1.2

            // Three layers rather than two. The third is slow and long, so the
            // surface drifts as well as ripples — two waves alone read as a
            // repeating pattern once you watch for more than a few seconds.
            let deep = wavePath(
                in: canvasSize, surfaceY: surfaceY + baseAmplitude * 0.8,
                amplitude: baseAmplitude * 0.45, wavelength: canvasSize.width * 2.1,
                phase: time * 0.31 * speed + 2.7
            )
            let back = wavePath(
                in: canvasSize, surfaceY: surfaceY + baseAmplitude * 0.35,
                amplitude: baseAmplitude * 0.7, wavelength: canvasSize.width * 1.37,
                phase: -time * 0.78 * speed + 1.2
            )
            let front = wavePath(
                in: canvasSize, surfaceY: surfaceY,
                amplitude: baseAmplitude, wavelength: canvasSize.width * 0.85,
                phase: time * 1.15 * speed
            )

            // Back layers sit behind and dimmer, which gives the liquid depth
            // instead of looking like one flat sheet.
            context.fill(deep, with: .color(tint.opacity(0.28)))
            context.fill(back, with: .color(tint.opacity(0.45)))

            context.fill(
                front,
                with: .linearGradient(
                    // Clearer at the surface, deeper toward the base — the
                    // way light falls through water. The old stops started at
                    // 98% opacity, which is why a full carafe read as paint.
                    Gradient(stops: [
                        .init(color: tint.opacity(0.62), location: 0),
                        .init(color: tint.opacity(0.74), location: 0.4),
                        .init(color: tint.opacity(0.9), location: 1)
                    ]),
                    startPoint: CGPoint(x: 0, y: surfaceY),
                    endPoint: CGPoint(x: 0, y: canvasSize.height)
                )
            )

            // A drop falling into the vessel, accelerating as it goes. The
            // pour reads as cause and effect: drop, then ripple.
            if let drop {
                let eased = drop * drop
                let radius = min(canvasSize.width * 0.035, 5)
                let y = canvasSize.height * 0.02 + (surfaceY - canvasSize.height * 0.02) * eased
                context.fill(
                    dropPath(center: CGPoint(x: canvasSize.width / 2, y: y), radius: radius),
                    with: .color(tint.opacity(0.85))
                )
            }

            if level > 0.001 {
                let surface = wavePath(
                    in: canvasSize, surfaceY: surfaceY,
                    amplitude: baseAmplitude, wavelength: canvasSize.width * 0.85,
                    phase: time * 1.15 * speed, surfaceOnly: true
                )

                // A soft band just under the surface, then a bright hairline on
                // it. Together they read as a meniscus — the single detail that
                // most makes this look like liquid rather than a coloured shape.
                context.stroke(
                    surface,
                    with: .color(.white.opacity(0.16 + splash * 0.12)),
                    lineWidth: 5
                )
                context.stroke(
                    surface,
                    with: .color(.white.opacity(0.62 + splash * 0.28)),
                    lineWidth: 1.4
                )
            }
        }
    }

    /// A teardrop, point up, centred on `center`.
    private func dropPath(center: CGPoint, radius: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: center.x, y: center.y - radius * 2.1))
        p.addCurve(
            to: CGPoint(x: center.x, y: center.y + radius),
            control1: CGPoint(x: center.x + radius * 0.2, y: center.y - radius * 1.2),
            control2: CGPoint(x: center.x + radius * 1.35, y: center.y + radius)
        )
        p.addCurve(
            to: CGPoint(x: center.x, y: center.y - radius * 2.1),
            control1: CGPoint(x: center.x - radius * 1.35, y: center.y + radius),
            control2: CGPoint(x: center.x - radius * 0.2, y: center.y - radius * 1.2)
        )
        return p
    }

    /// Splash strength, decaying to nothing about a second and a half after the
    /// pour.
    private func splashIntensity(at now: Date) -> Double {
        guard let splashStart else { return 0 }
        // The ripple starts when the drop lands, not when the button is tapped.
        let elapsed = now.timeIntervalSince(splashStart) - Self.dropDuration
        guard elapsed >= 0, elapsed < 1.6 else { return 0 }
        // Rises over a tenth of a second rather than starting at full strength,
        // so the surface is pushed rather than cut.
        let attack = min(1, elapsed / 0.1)
        return attack * exp(-elapsed / 0.5)
    }

    /// How long a drop takes to fall from the neck to the surface.
    private static let dropDuration: Double = 0.34

    /// Where the falling drop is, 0...1 of its fall, or nil when none is.
    private func dropProgress(at now: Date) -> Double? {
        guard let splashStart else { return nil }
        let t = now.timeIntervalSince(splashStart) / Self.dropDuration
        return (0..<1).contains(t) ? t : nil
    }

    /// Builds the filled area beneath a two-term sine surface.
    ///
    /// - Parameter surfaceOnly: when true, returns just the surface line rather
    ///   than the closed region below it.
    private func wavePath(
        in size: CGSize,
        surfaceY: CGFloat,
        amplitude: CGFloat,
        wavelength: CGFloat,
        phase: Double,
        surfaceOnly: Bool = false
    ) -> Path {
        var path = Path()
        guard wavelength > 0 else { return path }

        // 2pt steps: visually smooth on every display we target, and cheap
        // enough to run at 60fps alongside everything else on screen.
        let step: CGFloat = 2
        let k = (2 * .pi) / wavelength

        var x: CGFloat = 0
        var isFirst = true
        while x <= size.width + step {
            let clampedX = min(x, size.width)
            let y = surfaceY + amplitude * sin(k * clampedX + phase)
            let point = CGPoint(x: clampedX, y: y)
            if isFirst {
                path.move(to: point)
                isFirst = false
            } else {
                path.addLine(to: point)
            }
            x += step
        }

        if !surfaceOnly {
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.addLine(to: CGPoint(x: 0, y: size.height))
            path.closeSubpath()
        }
        return path
    }
}

// MARK: - Level motion

/// A damped-spring transition between two fill levels.
///
/// Solved in closed form rather than integrated step by step, so the level
/// depends only on elapsed time. That makes it exact regardless of frame rate,
/// and correct even if the view stops rendering and resumes later.
private struct LevelTransition {
    let from: Double
    let to: Double
    let start: Date

    /// Damping ratio. Below 1 the liquid overshoots and rocks back, which is
    /// what makes it read as a pour rather than a progress bar.
    private static let zeta: Double = 0.58
    /// Natural frequency, radians per second.
    private static let omega: Double = 9.5

    func level(at now: Date, reduceMotion: Bool) -> Double {
        guard from != to else { return to }

        let t = now.timeIntervalSince(start)
        guard t > 0 else { return from }

        if reduceMotion {
            // A plain short fade instead of a spring: same destination, no
            // bouncing, matching the rest of the app's Reduce Motion behaviour.
            let progress = min(1, t / 0.25)
            return from + (to - from) * progress
        }

        let zeta = Self.zeta
        let omega = Self.omega
        let damped = omega * sqrt(1 - zeta * zeta)
        let decay = exp(-zeta * omega * t)

        // Settled: stop evaluating transcendentals forever.
        guard decay > 0.0005 else { return to }

        let oscillation = cos(damped * t) + (zeta * omega / damped) * sin(damped * t)
        return to - (to - from) * decay * oscillation
    }
}

// MARK: - Vessel shape

/// The silhouette the app is named after: a carafe with a narrow neck, a
/// flared shoulder and a softly rounded base. Used as the clip for `LiquidFill`
/// on the water screen.
public struct VesselShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height

        let neckHalf = w * 0.30          // half-width of the neck opening
        let neckBottom = h * 0.10        // where the neck ends and the shoulder starts
        let shoulderBottom = h * 0.34    // where the shoulder finishes flaring
        let baseRadius = w * 0.22

        let left = rect.minX, right = rect.maxX
        let neckLeft = rect.midX - neckHalf, neckRight = rect.midX + neckHalf

        p.move(to: CGPoint(x: neckLeft, y: 0))
        p.addLine(to: CGPoint(x: neckRight, y: 0))
        p.addLine(to: CGPoint(x: neckRight, y: neckBottom))

        // Shoulder: a cubic so the flare eases out of the neck and eases into
        // the body, instead of meeting both at a visible corner.
        p.addCurve(
            to: CGPoint(x: right, y: shoulderBottom),
            control1: CGPoint(x: neckRight + w * 0.05, y: neckBottom + h * 0.04),
            control2: CGPoint(x: right, y: shoulderBottom - h * 0.13)
        )

        p.addLine(to: CGPoint(x: right, y: h - baseRadius))
        p.addQuadCurve(to: CGPoint(x: right - baseRadius, y: h), control: CGPoint(x: right, y: h))
        p.addLine(to: CGPoint(x: left + baseRadius, y: h))
        p.addQuadCurve(to: CGPoint(x: left, y: h - baseRadius), control: CGPoint(x: left, y: h))

        p.addLine(to: CGPoint(x: left, y: shoulderBottom))
        p.addCurve(
            to: CGPoint(x: neckLeft, y: neckBottom),
            control1: CGPoint(x: left, y: shoulderBottom - h * 0.13),
            control2: CGPoint(x: neckLeft - w * 0.05, y: neckBottom + h * 0.04)
        )
        p.closeSubpath()
        return p
    }
}

/// The glass around the water: a soft vertical highlight and a hairline edge,
/// drawn *over* the liquid so the vessel stays visible however full it is.
public struct VesselGlass: View {
    private let tint: Color

    public init(tint: Color = Palette.water) {
        self.tint = tint
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                // A highlight down the left of the body, as light catches a
                // curved glass wall.
                // Wide and heavily blurred: a narrow stripe read as a
                // rendering glitch rather than light on a curved wall.
                Capsule()
                    .fill(.white.opacity(0.16))
                    .frame(width: geo.size.width * 0.16, height: geo.size.height * 0.46)
                    .position(x: geo.size.width * 0.22, y: geo.size.height * 0.64)
                    .blur(radius: 7)

                VesselShape()
                    .stroke(tint.opacity(0.3), lineWidth: 1.5)
            }
            .clipShape(VesselShape().inset(by: -1))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension VesselShape: InsettableShape {
    public func inset(by amount: CGFloat) -> some InsettableShape {
        InsetVessel(amount: amount)
    }
}

private struct InsetVessel: InsettableShape {
    let amount: CGFloat
    func path(in rect: CGRect) -> Path {
        VesselShape().path(in: rect.insetBy(dx: amount, dy: amount))
    }
    func inset(by more: CGFloat) -> some InsettableShape { InsetVessel(amount: amount + more) }
}

#Preview("Liquid fill") {
    HStack(spacing: 24) {
        LiquidFill(progress: 0.35)
            .clipShape(VesselShape())
            .frame(width: 120, height: 190)
        LiquidFill(progress: 0.72, tint: Palette.diet)
            .clipShape(Circle())
            .frame(width: 140, height: 140)
    }
    .padding(40)
    .background(Palette.ground)
}
