import SwiftUI

/// Vessel's type system.
///
/// Two families, used with intent:
/// - **New York** (serif) for headers and journal prose. It gives the app an
///   editorial, written-by-hand feeling that a pure SF Pro interface never has.
/// - **SF Pro** for every number, label and control, where legibility at small
///   sizes and tabular alignment matter more than character.
///
/// Everything is built on `Font.system(_:design:)` with a text style, so Dynamic
/// Type scaling is inherited for free — we never hardcode a point size.
public enum Typography {

    // MARK: - Editorial (New York)

    /// Screen titles. Large, serif, confident.
    public static let display = Font.system(.largeTitle, design: .serif, weight: .semibold)

    /// Section headers within a screen.
    public static let title = Font.system(.title2, design: .serif, weight: .semibold)

    /// Card headers.
    public static let heading = Font.system(.headline, design: .serif, weight: .semibold)

    /// Journal body copy. Serif, regular weight, generous line height applied at the view.
    public static let prose = Font.system(.body, design: .serif, weight: .regular)

    /// Pull quotes and empty-state copy.
    public static let quote = Font.system(.title3, design: .serif, weight: .regular).italic()

    // MARK: - Interface (SF Pro)

    public static let body = Font.system(.body, design: .default, weight: .regular)
    public static let bodyEmphasis = Font.system(.body, design: .default, weight: .semibold)
    public static let callout = Font.system(.callout, design: .default, weight: .regular)
    public static let label = Font.system(.subheadline, design: .default, weight: .medium)
    public static let caption = Font.system(.caption, design: .default, weight: .regular)
    public static let captionEmphasis = Font.system(.caption, design: .default, weight: .semibold)

    // MARK: - Numerics
    //
    // Monospaced digits everywhere a number can change in place, so values don't
    // jitter horizontally as they animate or tick upward.

    /// The single big number on a card — calories remaining, ml drunk, streak count.
    public static let metric = Font.system(.largeTitle, design: .rounded, weight: .bold)
        .monospacedDigit()

    /// Secondary metrics in a stat row.
    public static let metricSmall = Font.system(.title3, design: .rounded, weight: .semibold)
        .monospacedDigit()

    /// Units and suffixes that sit beside a metric.
    public static let metricUnit = Font.system(.subheadline, design: .rounded, weight: .medium)

    /// Numbers inside dense lists and charts.
    public static let numeric = Font.system(.subheadline, design: .default, weight: .regular)
        .monospacedDigit()
}

public extension View {
    /// Journal prose needs more air between lines than SwiftUI's default.
    func proseLineSpacing() -> some View {
        self.lineSpacing(5)
    }
}
