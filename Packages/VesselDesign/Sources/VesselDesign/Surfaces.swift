import SwiftUI

/// Card and background treatments.
///
/// On iOS/iPadOS 26 these adopt Liquid Glass; on 18 they fall back to a solid
/// surface with a hairline border and a soft shadow. The fallback is designed to
/// look deliberate in its own right rather than like a broken version of the
/// newer treatment — an iOS 18 user should never feel they're looking at
/// something unfinished.
public struct VesselCard<Content: View>: View {

    private let content: Content
    private let padding: CGFloat
    private let radius: CGFloat
    /// Cards that sit on top of vivid artwork need the glass treatment to stay
    /// legible; flat cards on the page ground do not.
    private let prefersGlass: Bool

    public init(
        padding: CGFloat = Layout.lg,
        radius: CGFloat = Layout.radiusMedium,
        prefersGlass: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.radius = radius
        self.prefersGlass = prefersGlass
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(CardBackground(radius: radius, prefersGlass: prefersGlass))
    }
}

private struct CardBackground: ViewModifier {
    let radius: CGFloat
    let prefersGlass: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        #if canImport(UIKit)
        if #available(iOS 26.0, *), prefersGlass {
            return AnyView(content.glassEffect(in: shape))
        }
        #endif

        return AnyView(
            content
                .background(Palette.surface, in: shape)
                .overlay(shape.strokeBorder(Palette.separator, lineWidth: 0.5))
                // Warm-tinted rather than neutral gray: a pure black shadow on a
                // parchment ground reads as dirty.
                .shadow(color: Color(hex: 0x3A2E20).opacity(0.06), radius: 10, x: 0, y: 4)
        )
    }
}

public extension View {
    /// Applies Liquid Glass where available, and a legible translucent material
    /// everywhere else. For chrome that floats above scrolling content.
    func vesselGlass(in shape: some Shape = Capsule()) -> some View {
        modifier(GlassChrome(shape: AnyShape(shape)))
    }
}

private struct GlassChrome: ViewModifier {
    let shape: AnyShape

    func body(content: Content) -> some View {
        #if canImport(UIKit)
        if #available(iOS 26.0, *) {
            return AnyView(content.glassEffect(in: shape))
        }
        #endif
        return AnyView(
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Palette.separator.opacity(0.6), lineWidth: 0.5))
        )
    }
}
