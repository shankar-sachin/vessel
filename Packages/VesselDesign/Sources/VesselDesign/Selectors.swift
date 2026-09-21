import SwiftUI

/// A horizontal scale picker built from discrete pips.
///
/// Used for symptom severity and mood. A `Picker` would work, but these values
/// are ordinal and benefit from showing the whole scale at once — you pick "3 of
/// 5" by seeing where 3 sits, not by reading a label in a wheel.
/// Fixed geometry for `ScaleSelector`.
///
/// Lives outside the generic type because Swift doesn't allow static stored
/// properties on generics.
private enum ScaleMetrics {
    /// Height reserved for the bar or symbol row.
    static let indicatorHeight: CGFloat = 32
    /// Height reserved for the label row, enough for two lines at default size.
    static let labelHeight: CGFloat = 30
}

public struct ScaleSelector<Value: Hashable & Identifiable>: View {

    /// How the scale draws itself.
    public enum Style {
        /// Bars fill cumulatively up to the selection, so "Disruptive" reads as
        /// *four out of five* rather than as one highlighted option among five.
        /// Correct for genuinely ordinal scales like severity.
        case cumulative
        /// Only the selected item is emphasised. For scales where the steps are
        /// distinct states rather than increasing amounts, like mood.
        case discrete
    }

    private let values: [Value]
    @Binding private var selection: Value
    private let tint: Color
    private let style: Style
    private let title: (Value) -> String
    private let detail: ((Value) -> String)?
    private let symbol: ((Value) -> String)?

    public init(
        values: [Value],
        selection: Binding<Value>,
        tint: Color,
        style: Style = .cumulative,
        title: @escaping (Value) -> String,
        detail: ((Value) -> String)? = nil,
        symbol: ((Value) -> String)? = nil
    ) {
        self.values = values
        self._selection = selection
        self.tint = tint
        self.style = style
        self.title = title
        self.detail = detail
        self.symbol = symbol
    }

    private var selectedIndex: Int {
        values.firstIndex(of: selection) ?? 0
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Layout.md) {
            HStack(alignment: .bottom, spacing: Layout.xs) {
                ForEach(Array(values.enumerated()), id: \.element) { index, value in
                    let isSelected = value == selection
                    // Cumulative: everything up to and including the selection is
                    // "on". Discrete: only the selection is.
                    let isLit = style == .cumulative ? index <= selectedIndex : isSelected

                    Button {
                        selection = value
                    } label: {
                        // Both rows get a fixed height. Without it, a label that
                        // wraps to two lines ("Barely there") shifts its bar up
                        // relative to a one-line neighbour, and the ascending
                        // ramp — the whole point of the control — stops reading
                        // as a ramp.
                        VStack(spacing: Layout.sm) {
                            if let symbol {
                                Image(systemName: symbol(value))
                                    .font(.title3)
                                    .foregroundStyle(isLit ? tint : Palette.inkTertiary)
                                    .frame(height: ScaleMetrics.indicatorHeight, alignment: .bottom)
                            } else {
                                bar(index: index, isLit: isLit, isSelected: isSelected)
                            }

                            Text(title(value))
                                .font(isSelected ? Typography.captionEmphasis : Typography.caption)
                                // Unselected steps stay readable rather than
                                // fading out — the whole scale has to be legible
                                // for the selection to mean anything.
                                .foregroundStyle(isSelected ? tint : Palette.inkSecondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                // Shrink and tighten rather than hyphenate:
                                // a break like "Notice-able" reads as a
                                // rendering fault rather than a design choice.
                                .minimumScaleFactor(0.6)
                                .allowsTightening(true)
                                .frame(maxWidth: .infinity, minHeight: ScaleMetrics.labelHeight, alignment: .top)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Layout.sm)
                        .padding(.horizontal, 2)
                        .background(
                            RoundedRectangle(cornerRadius: Layout.radiusSmall, style: .continuous)
                                .fill(isSelected ? tint.opacity(0.13) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Layout.radiusSmall, style: .continuous)
                                .strokeBorder(isSelected ? tint.opacity(0.45) : .clear, lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(title(value))
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                }
            }
            .vesselAnimation(Motion.quick, value: selection)

            // The plain-language anchor for the current choice. Without it,
            // "3" drifts in meaning over months and the correlation data
            // quietly degrades.
            if let detail {
                Text(detail(selection))
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
                    .id(selection)
            }
        }
    }

    /// A bar whose height encodes its step, so the ordering survives even in
    /// grayscale or for someone who can't distinguish the tint.
    private func bar(index: Int, isLit: Bool, isSelected: Bool) -> some View {
        let steps = max(1, values.count - 1)
        let fraction = Double(index) / Double(steps)
        let height = 11 + (ScaleMetrics.indicatorHeight - 11) * fraction

        return Capsule()
            .fill(isLit ? tint : tint.opacity(0.20))
            .frame(width: 11, height: height)
            .overlay(
                // The selected step gets a ring so it stays identifiable once
                // everything below it is also filled in.
                Capsule()
                    .strokeBorder(isSelected ? Palette.ink.opacity(0.40) : .clear, lineWidth: 1.5)
            )
            .frame(height: ScaleMetrics.indicatorHeight, alignment: .bottom)
    }
}

/// A free-form tag field: type, press return, get a chip.
public struct TagEditor: View {
    @Binding private var tags: [String]
    private let tint: Color
    private let placeholder: String

    @State private var draft: String = ""
    @FocusState private var isFocused: Bool

    public init(tags: Binding<[String]>, tint: Color, placeholder: String = "Add a tag") {
        self._tags = tags
        self.tint = tint
        self.placeholder = placeholder
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Layout.sm) {
            if !tags.isEmpty {
                // Wraps to as many lines as needed — a horizontal scroller would
                // hide tags off-screen with no indication they exist.
                FlowLayout(spacing: Layout.xs) {
                    ForEach(tags, id: \.self) { tag in
                        Button {
                            tags.removeAll { $0 == tag }
                        } label: {
                            HStack(spacing: 3) {
                                Text(tag)
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .font(Typography.captionEmphasis)
                            .foregroundStyle(tint)
                            .padding(.horizontal, Layout.sm)
                            .padding(.vertical, 5)
                            .background(tint.opacity(0.14), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove tag \(tag)")
                    }
                }
            }

            TextField(placeholder, text: $draft)
                .modifier(PlainTextEntry())
                .focused($isFocused)
                .onSubmit(commit)
        }
    }

    private func commit() {
        let cleaned = draft.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        draft = ""
        guard !cleaned.isEmpty, !tags.contains(cleaned) else { return }
        tags.append(cleaned)
        // Keep focus so several tags can be added without re-tapping the field.
        isFocused = true
    }
}

/// Lays children left to right, wrapping to new lines as needed.
///
/// SwiftUI has no built-in wrapping stack, and `LazyVGrid` can't do it because
/// chip widths vary with their text.
///
/// `SwiftUI.Layout` is spelled out because this module already exports a
/// `Layout` enum of spacing tokens, which otherwise shadows the protocol.
public struct FlowLayout: SwiftUI.Layout {
    private let spacing: CGFloat

    public init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: SwiftUI.LayoutSubviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = layout(subviews: subviews, maxWidth: maxWidth)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: maxWidth == .infinity ? rows.map(\.width).max() ?? 0 : maxWidth, height: height)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: SwiftUI.LayoutSubviews, cache: inout ()) {
        let rows = layout(subviews: subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func layout(subviews: SwiftUI.LayoutSubviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width

            if needed > maxWidth, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
                current.indices = [index]
                current.width = size.width
                current.height = size.height
            } else {
                current.indices.append(index)
                current.width = needed
                current.height = max(current.height, size.height)
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}


/// Text-entry tweaks that only exist on iOS.
///
/// The package also compiles for macOS so unit tests run without a simulator,
/// and these modifiers are unavailable there.
private struct PlainTextEntry: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.done)
        #else
        content.autocorrectionDisabled()
        #endif
    }
}
