import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// A button style that dips under the finger and springs back.
///
/// Scale rather than opacity: a tile that fades on press looks disabled, while
/// one that compresses reads as a physical thing being pushed.
public struct PressableTileStyle: ButtonStyle {
    private let cornerRadius: CGFloat

    public init(cornerRadius: CGFloat = Layout.radiusMedium) {
        self.cornerRadius = cornerRadius
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// A tile that logs a fixed amount, with the amount flying up out of it.
///
/// The rising label exists so the tap is confirmable without looking at the
/// total — you press "Glass", see "+250 ml" lift away, and know it landed. That
/// removes the need to visually re-read the number every time, which is what
/// makes rapid logging feel quick rather than anxious.
public struct QuickAddButton: View {

    private let title: String
    private let detail: String
    private let symbol: String
    /// Text that flies up on tap, e.g. "+250 ml". Nil when the screen shows
    /// its own confirmation — on the water screen the label rises from the
    /// vessel instead, where the water actually went.
    private let burstText: String?
    private let tint: Color
    private let action: () -> Void

    @State private var bursts: [UUID] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        title: String,
        detail: String,
        symbol: String,
        burstText: String? = nil,
        tint: Color = Palette.water,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.burstText = burstText
        self.tint = tint
        self.action = action
    }

    public var body: some View {
        Button {
            action()
            fireBurst()
        } label: {
            VStack(spacing: Layout.xs) {
                Image(systemName: symbol)
                    .font(.title2)
                    .symbolEffect(.bounce, value: bursts.count)
                Text(title)
                    .font(Typography.captionEmphasis)
                Text(detail)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkTertiary)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: Layout.minTouchTarget * 1.8)
            .padding(.vertical, Layout.sm)
            .foregroundStyle(tint)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Layout.radiusMedium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Layout.radiusMedium, style: .continuous)
                    .strokeBorder(Palette.separator, lineWidth: 0.5)
            )
        }
        .buttonStyle(PressableTileStyle())
        // The labels must escape the tile's bounds as they rise, and must never
        // intercept a second tap while in flight.
        .overlay(alignment: .top) {
            ZStack {
                if let burstText {
                    ForEach(bursts, id: \.self) { id in
                        RisingLabel(text: burstText, tint: tint, reduceMotion: reduceMotion)
                    }
                }
            }
            .allowsHitTesting(false)
        }
        .accessibilityLabel("Add \(title)")
        .accessibilityValue(detail)
    }

    private func fireBurst() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif

        let id = UUID()
        bursts.append(id)

        // Self-cleaning, so repeated taps stack up several labels in flight
        // rather than one replacing the last mid-rise.
        Task {
            try? await Task.sleep(for: .milliseconds(950))
            bursts.removeAll { $0 == id }
        }
    }
}

/// A short-lived label that lifts and fades.
private struct RisingLabel: View {
    let text: String
    let tint: Color
    let reduceMotion: Bool

    @State private var offset: CGFloat = 4
    @State private var opacity: Double = 0

    var body: some View {
        Text(text)
            .font(Typography.captionEmphasis)
            .foregroundStyle(tint)
            .padding(.horizontal, Layout.sm)
            .padding(.vertical, 3)
            .background(tint.opacity(0.14), in: Capsule())
            .offset(y: offset)
            .opacity(opacity)
            .onAppear(perform: animate)
    }

    private func animate() {
        guard !reduceMotion else {
            // Still confirm the tap, just without the travel.
            withAnimation(.easeOut(duration: 0.15)) { opacity = 1 }
            withAnimation(.easeIn(duration: 0.3).delay(0.4)) { opacity = 0 }
            return
        }

        withAnimation(.easeOut(duration: 0.18)) { opacity = 1 }
        // Decelerating rise, so it looks thrown rather than driven.
        withAnimation(.easeOut(duration: 0.9)) { offset = -38 }
        withAnimation(.easeIn(duration: 0.42).delay(0.46)) { opacity = 0 }
    }
}

#Preview("Quick add") {
    HStack(spacing: 12) {
        QuickAddButton(title: "Glass", detail: "250 ml", symbol: "cup.and.saucer",
                       burstText: "+250 ml") {}
        QuickAddButton(title: "Bottle", detail: "500 ml", symbol: "waterbottle",
                       burstText: "+500 ml") {}
    }
    .padding(40)
    .background(Palette.ground)
}
