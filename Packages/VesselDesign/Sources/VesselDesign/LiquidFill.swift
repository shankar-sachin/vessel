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
        splashToken: Int = 0
    ) {
        self.progress = progress
        self.tint = tint
        self.isAnimated = isAnimated
        self.splashToken = splashToken
        let clamped = min(max(progress, 0), 1)
        // Start settled at the initial value, so the first render isn't an
        // animation from empty.
        _transition = State(initialValue: LevelTransition(from: clamped, to: clamped, start: .distantPast))
    }

    private var target: Double { min(max(progress, 0), 1) }

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
            transition = LevelTransition(from: current, to: min(max(newValue, 0), 1), start: Date())
        }
        .onChange(of: splashToken) { _, _ in
            guard !reduceMotion else { return }
            splashStart = Date()
        }
        .accessibilityElement()
        .accessibilityLabel("Fill level")
        .accessibilityValue("\(Int((target * 100).rounded())) percent")
    }

    private func canvas(size: CGSize, now: Date, staticLevel: Double? = nil) -> some View {
        let level = staticLevel ?? transition.level(at: now, reduceMotion: reduceMotion)
        let splash = staticLevel != nil ? 0 : splashIntensity(at: now)
        let time = now.timeIntervalSinceReferenceDate

        return Canvas { context, canvasSize in
            guard canvasSize.width > 0, canvasSize.height > 0 else { return }

            let surfaceY = canvasSize.height * (1 - level)

            // Waves flatten as the vessel approaches full — a nearly-full
            // container has little room to slosh, and a big wave at the brim
            // looks wrong. A splash temporarily overrides that calm.
            let calm = 1.0 - (level * 0.55)
            let baseAmplitude = min(canvasSize.height * 0.035, 9) * calm * (1 + splash * 2.4)
            // Fresh liquid moves faster before it settles.
            let speed = 1.0 + splash * 1.8

            let front = wavePath(
                in: canvasSize, surfaceY: surfaceY,
                amplitude: baseAmplitude, wavelength: canvasSize.width * 0.85,
                phase: time * 1.15 * speed
            )
            let back = wavePath(
                in: canvasSize, surfaceY: surfaceY + baseAmplitude * 0.35,
                amplitude: baseAmplitude * 0.66, wavelength: canvasSize.width * 1.37,
                phase: -time * 0.78 * speed + 1.2
            )

            // Back wave sits behind and dimmer, which creates depth in the liquid.
            context.fill(back, with: .color(tint.opacity(0.42)))

            context.fill(
                front,
                with: .linearGradient(
                    Gradient(colors: [tint.opacity(0.95), tint.opacity(0.68)]),
                    startPoint: CGPoint(x: 0, y: surfaceY),
                    endPoint: CGPoint(x: 0, y: canvasSize.height)
                )
            )

            // A bright hairline along the surface — the specular highlight that
            // sells it as a liquid rather than a colored rectangle.
            if level > 0.001 {
                context.stroke(
                    wavePath(
                        in: canvasSize, surfaceY: surfaceY,
                        amplitude: baseAmplitude, wavelength: canvasSize.width * 0.85,
                        phase: time * 1.15 * speed, surfaceOnly: true
                    ),
                    with: .color(.white.opacity(0.5 + splash * 0.3)),
                    lineWidth: 1.2
                )
            }
        }
    }

    /// Splash strength, decaying to nothing about a second and a half after the
    /// pour.
    private func splashIntensity(at now: Date) -> Double {
        guard let splashStart else { return 0 }
        let elapsed = now.timeIntervalSince(splashStart)
        guard elapsed >= 0, elapsed < 1.6 else { return 0 }
        return exp(-elapsed / 0.42)
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
