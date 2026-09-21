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
        .foregroundStyle(filled ? Color.white : tint)
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
        HStack(alignment: .firstTextBaseline) {
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
            Spacer(minLength: Layout.sm)
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
