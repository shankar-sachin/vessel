import SwiftUI

/// A large headline number with its unit set beside it.
///
/// Kept as one component so the baseline relationship between the number and its
/// unit is identical everywhere — it's the kind of detail that looks sloppy the
/// moment two screens disagree.
public struct MetricLabel: View {
    private let value: String
    private let unit: String?
    private let tint: Color
    private let compact: Bool

    public init(value: String, unit: String? = nil, tint: Color = Palette.ink, compact: Bool = false) {
        self.value = value
        self.unit = unit
        self.tint = tint
        self.compact = compact
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Layout.xs) {
            Text(value)
                .font(compact ? Typography.metricSmall : Typography.metric)
                .foregroundStyle(tint)
                // Big numbers must never truncate to "…" — shrinking is always better.
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let unit {
                Text(unit)
                    .font(Typography.metricUnit)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A small labelled chip. Used for tags, meal types, symptom severities.
public struct VesselChip: View {
    private let text: String
    private let systemImage: String?
    private let tint: Color
    private let filled: Bool

    public init(_ text: String, systemImage: String? = nil, tint: Color = Palette.inkSecondary, filled: Bool = false) {
        self.text = text
        self.systemImage = systemImage
        self.tint = tint
        self.filled = filled
    }

    public var body: some View {
        HStack(spacing: Layout.xs) {
            if let systemImage {
                Image(systemName: systemImage).imageScale(.small)
            }
            Text(text)
        }
        .font(Typography.captionEmphasis)
        .foregroundStyle(filled ? Palette.onAccent : tint)
        .padding(.horizontal, Layout.sm)
        .padding(.vertical, 5)
        .background(filled ? tint : tint.opacity(0.12), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// Section header with an optional trailing action.
public struct SectionHeader<Trailing: View>: View {
    private let title: String
    private let subtitle: String?
    private let trailing: Trailing

    public init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    public var body: some View {
        AdaptiveStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.title)
                    .foregroundStyle(Palette.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.inkTertiary)
                }
            }
            AdaptiveSpacer(minLength: Layout.sm)
            trailing
        }
        .accessibilityAddTraits(.isHeader)
    }
}

/// Shown when a log has nothing in it yet.
///
/// Empty states are the first thing a new user sees, so they get real copy and
/// the module's accent rather than a gray shrug.
public struct EmptyStateView: View {
    private let icon: String
    private let title: String
    private let message: String
    private let tint: Color

    public init(icon: String, title: String, message: String, tint: Color = Palette.inkSecondary) {
        self.icon = icon
        self.title = title
        self.message = message
        self.tint = tint
    }

    public var body: some View {
        VStack(spacing: Layout.md) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(tint.opacity(0.7))
            Text(title)
                .font(Typography.heading)
                .foregroundStyle(Palette.ink)
            Text(message)
                .font(Typography.callout)
                .foregroundStyle(Palette.inkTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(Layout.xl)
        .frame(maxWidth: 340)
        .accessibilityElement(children: .combine)
    }
}

/// The floating button that logs from anywhere.
///
/// Every screen in Vessel is a readout of what's already recorded; this is the
/// one control that adds to it. Keeping it fixed above the content means the
/// shortest path to logging is the same everywhere, instead of depending on
/// which tab you happen to be looking at.
public struct FloatingLogButton: View {

    private let tint: Color
    private let action: () -> Void

    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(tint: Color = Palette.diet, action: @escaping () -> Void) {
        self.tint = tint
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Palette.onAccent)
                // 52pt: comfortably above the 44pt tap minimum without
                // dominating the screen it floats over. At 58 with a wide glow
                // it read as the main event rather than a way into one.
                .frame(width: 52, height: 52)
                .background(
                    Circle().fill(
                        LinearGradient(
                            colors: [tint, Color(hex: 0xA8461F)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                )
                // A tinted shadow rather than a neutral one, so the button
                // looks lit from within instead of pasted on.
                .shadow(color: tint.opacity(0.35), radius: 9, y: 4)
                .shadow(color: Color(hex: 0x3A2E20).opacity(0.16), radius: 3, y: 1)
                .scaleEffect(isPressed ? 0.92 : 1)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressed else { return }
                    withAnimation(reduceMotion ? nil : Motion.quick) { isPressed = true }
                }
                .onEnded { _ in
                    withAnimation(reduceMotion ? nil : Motion.quick) { isPressed = false }
                }
        )
        .accessibilityLabel("Log something")
        .accessibilityHint("Describe a meal, a drink, or how you're feeling")
        .vesselHover()
        .accessibilityIdentifier("floatingLogButton")
    }
}
