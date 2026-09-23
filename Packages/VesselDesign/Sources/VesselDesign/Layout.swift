import SwiftUI

/// Spacing, radius and elevation tokens.
///
/// A small fixed scale rather than arbitrary numbers — consistent rhythm is most
/// of what separates an app that feels designed from one that feels assembled.
public enum Layout {

    // MARK: - Spacing (4pt base grid)

    /// 4pt — between tightly related items, e.g. a metric and its unit.
    public static let xs: CGFloat = 4
    /// 8pt — within a component.
    public static let sm: CGFloat = 8
    /// 12pt — default internal padding for compact rows.
    public static let md: CGFloat = 12
    /// 16pt — standard card padding and screen gutter.
    public static let lg: CGFloat = 16
    /// 24pt — between distinct cards.
    public static let xl: CGFloat = 24
    /// 32pt — between major sections.
    public static let xxl: CGFloat = 32
    /// 48pt — above a screen's first element, and around empty states.
    public static let xxxl: CGFloat = 48

    // MARK: - Corner radius

    /// Small controls, chips, badges.
    public static let radiusSmall: CGFloat = 10
    /// Standard cards.
    public static let radiusMedium: CGFloat = 18
    /// Hero cards and sheets.
    public static let radiusLarge: CGFloat = 28
    /// Fully rounded.
    public static let radiusPill: CGFloat = 999

    // MARK: - Hit targets

    /// Apple's minimum comfortable touch target. Nothing tappable goes below this.
    public static let minTouchTarget: CGFloat = 44

    // MARK: - Screen

    /// Horizontal gutter on compact width.
    public static let gutter: CGFloat = 16

    /// On iPad, content is capped so lines of prose never sprawl to 1000pt wide —
    /// past roughly 70 characters, reading comprehension measurably drops.
    public static let readableWidth: CGFloat = 680
}

public extension View {
    /// Standard screen gutter.
    func screenGutter() -> some View {
        self.padding(.horizontal, Layout.gutter)
    }

    /// Constrains prose to a comfortable measure and centers it — essential on iPad,
    /// a no-op on iPhone where the screen is already narrower than the cap.
    func readableWidth(_ maxWidth: CGFloat = Layout.readableWidth) -> some View {
        self.frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }
}

/// A row that becomes a column at accessibility text sizes.
///
/// At the largest sizes a horizontal row has no room for its words, and
/// SwiftUI breaks them mid-letter instead — "Di / n / ne / r", "Dair / y".
/// Every row that pairs a label with a value, or a title with metadata, goes
/// through this so it stacks rather than shreds.
public struct AdaptiveStack<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var size
    private let alignment: VerticalAlignment
    private let spacing: CGFloat?
    private let content: Content

    public init(alignment: VerticalAlignment = .center, spacing: CGFloat? = nil,
                @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        if size.isAccessibilitySize {
            VStack(alignment: .leading, spacing: spacing ?? Layout.xs) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: alignment, spacing: spacing) { content }
        }
    }
}

public extension DynamicTypeSize {
    /// True when rows should stack. Named for what the caller wants to know.
    var needsStackedLayout: Bool { isAccessibilitySize }
}

/// A `Spacer` for `AdaptiveStack`: pushes apart in a row, and disappears in a
/// column, where a spacer would open a gap down the screen instead.
public struct AdaptiveSpacer: View {
    @Environment(\.dynamicTypeSize) private var size
    private let minLength: CGFloat?

    public init(minLength: CGFloat? = nil) { self.minLength = minLength }

    public var body: some View {
        if !size.isAccessibilitySize { Spacer(minLength: minLength) }
    }
}
