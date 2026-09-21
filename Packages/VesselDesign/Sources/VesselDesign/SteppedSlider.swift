import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// A continuous-feeling slider that snaps to a fixed set of steps.
///
/// Used for symptom severity. A slider suits an *intensity* better than a row of
/// buttons does: severity is one quantity you dial up or down, and dragging it
/// feels like that, where tapping one of five boxes feels like picking from a
/// menu of unrelated options.
///
/// It still snaps, because the underlying scale really is five discrete points —
/// the correlation engine needs "4", not "3.7". The drag is smooth; the value
/// isn't.
public struct SteppedSlider<Value: Hashable & Identifiable>: View {

    private let values: [Value]
    @Binding private var selection: Value
    private let tint: Color
    private let title: (Value) -> String
    private let detail: ((Value) -> String)?
    private let accessibilityLabel: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDragging = false

    public init(
        values: [Value],
        selection: Binding<Value>,
        tint: Color,
        accessibilityLabel: String,
        title: @escaping (Value) -> String,
        detail: ((Value) -> String)? = nil
    ) {
        self.values = values
        self._selection = selection
        self.tint = tint
        self.accessibilityLabel = accessibilityLabel
        self.title = title
        self.detail = detail
    }

    private var selectedIndex: Int { values.firstIndex(of: selection) ?? 0 }
    private var lastIndex: Int { max(1, values.count - 1) }
    private var fraction: Double { Double(selectedIndex) / Double(lastIndex) }

    private let trackHeight: CGFloat = 12
    private let thumbSize: CGFloat = 30

    public var body: some View {
        VStack(alignment: .leading, spacing: Layout.md) {
            // Current value reads as the headline, so the slider doesn't need
            // five labels crowding underneath it.
            HStack(alignment: .firstTextBaseline, spacing: Layout.sm) {
                Text(title(selection))
                    .font(Typography.bodyEmphasis)
                    .foregroundStyle(tint)
                    .contentTransition(.numericText())
                if let detail {
                    Text(detail(selection))
                        .font(Typography.caption)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .animation(reduceMotion ? nil : Motion.quick, value: selection)
            .accessibilityHidden(true)

            slider

            // End anchors only. The scale is ordered, so naming the extremes is
            // enough to orient someone — labelling all five is noise.
            HStack {
                Text(title(values.first ?? selection))
                Spacer()
                Text(title(values.last ?? selection))
            }
            .font(Typography.caption)
            .foregroundStyle(Palette.inkTertiary)
            // The slider already speaks its label and value, so the visible
            // headline and end anchors would just repeat it.
            .accessibilityHidden(true)
        }
    }

    /// Bridges the slider representation's `Double` to our discrete values.
    private var accessibilityValueBinding: Binding<Double> {
        Binding(
            get: { Double(selectedIndex) },
            set: { newValue in
                let index = Int(newValue.rounded())
                guard values.indices.contains(index), values[index] != selection else { return }
                selection = values[index]
                hapticStep()
            }
        )
    }

    private var slider: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let travel = max(0, width - thumbSize)
            let thumbX = thumbSize / 2 + travel * fraction

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(tint.opacity(0.16))
                    .frame(height: trackHeight)

                // The fill deepens as it lengthens, so intensity is carried by
                // colour as well as by length.
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.55), tint],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: thumbX, height: trackHeight)

                // Faint stops, so it's visible that the value snaps rather than
                // the snapping feeling like a bug.
                HStack(spacing: 0) {
                    ForEach(0...lastIndex, id: \.self) { index in
                        Circle()
                            .fill(index <= selectedIndex ? Color.white.opacity(0.55) : tint.opacity(0.30))
                            .frame(width: 3, height: 3)
                        if index < lastIndex { Spacer(minLength: 0) }
                    }
                }
                .padding(.horizontal, thumbSize / 2)

                Circle()
                    .fill(Palette.surface)
                    .overlay(Circle().strokeBorder(tint, lineWidth: 3))
                    .shadow(color: Color(hex: 0x3A2E20).opacity(isDragging ? 0.22 : 0.12),
                            radius: isDragging ? 7 : 4, x: 0, y: 2)
                    .frame(width: thumbSize, height: thumbSize)
                    .scaleEffect(isDragging ? 1.12 : 1)
                    .position(x: thumbX, y: geo.size.height / 2)
            }
            .frame(height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                // minimumDistance 0 so a plain tap anywhere on the track jumps
                // there, which is what people expect of a slider.
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if !isDragging { isDragging = true }
                        update(x: gesture.location.x, travel: travel)
                    }
                    .onEnded { _ in isDragging = false }
            )
            .animation(reduceMotion ? nil : Motion.quick, value: selectedIndex)
            .animation(Motion.quick, value: isDragging)
        }
        .frame(height: thumbSize + 6)
        // Presented to assistive technology as a genuine slider rather than a
        // pile of shapes with a custom action bolted on. VoiceOver then offers
        // its familiar swipe-up/swipe-down adjustment, and the value is spoken
        // as "Disruptive" rather than as a meaningless percentage.
        //
        // Applied to the track rather than the whole control on purpose: the
        // exposed element inherits this frame, so its coordinate space matches
        // the thing a person actually drags.
        .accessibilityRepresentation {
            Slider(
                value: accessibilityValueBinding,
                in: 0...Double(lastIndex),
                step: 1
            )
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(title(selection))
        }
    }

    private func update(x: CGFloat, travel: CGFloat) {
        guard travel > 0 else { return }
        let raw = (x - thumbSize / 2) / travel
        let index = Int((min(max(raw, 0), 1) * Double(lastIndex)).rounded())
        guard values.indices.contains(index), values[index] != selection else { return }
        selection = values[index]
        hapticStep()
    }

    /// A tick at each step, so the snapping is felt as well as seen.
    private func hapticStep() {
        #if canImport(UIKit)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }
}
