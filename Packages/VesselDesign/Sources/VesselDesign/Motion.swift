import SwiftUI

/// Vessel's motion language.
///
/// Every animation is a spring, because springs are interruptible — if you tap
/// again mid-transition the UI redirects from its current velocity instead of
/// snapping or queueing. That responsiveness is most of what "feels good" means
/// on a touchscreen.
///
/// Durations are deliberately short. Motion should explain what happened, then
/// get out of the way.
public enum Motion {

    /// Small state flips: toggles, selection, chip taps.
    public static let quick = Animation.spring(response: 0.28, dampingFraction: 0.82)

    /// The default for most UI: cards appearing, rows inserting, sheets settling.
    public static let standard = Animation.spring(response: 0.42, dampingFraction: 0.85)

    /// Screen-level transitions and hero elements.
    public static let deliberate = Animation.spring(response: 0.58, dampingFraction: 0.88)

    /// Liquid, water and fill animations. Lower damping so it overshoots and
    /// settles — the physical behaviour of something being poured.
    public static let fluid = Animation.spring(response: 0.75, dampingFraction: 0.62)

    /// A celebration: streak extended, goal hit. Bouncy on purpose.
    public static let celebrate = Animation.spring(response: 0.5, dampingFraction: 0.55)

    /// Continuous ambient motion — the surface of the water, a breathing glow.
    public static let ambient = Animation.easeInOut(duration: 2.4).repeatForever(autoreverses: true)
}

public extension View {
    /// Honors Reduce Motion: substitutes a plain cross-fade when the user has
    /// asked the system to calm animations down.
    ///
    /// Use this instead of `.animation(_:value:)` for anything with travel,
    /// scale or spring overshoot.
    func vesselAnimation<V: Equatable>(
        _ animation: Animation,
        value: V,
        reduceMotionFallback: Animation? = .easeInOut(duration: 0.2)
    ) -> some View {
        modifier(ReduceMotionAwareAnimation(animation: animation, value: value, fallback: reduceMotionFallback))
    }
}

private struct ReduceMotionAwareAnimation<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: V
    let fallback: Animation?

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? fallback : animation, value: value)
    }
}
