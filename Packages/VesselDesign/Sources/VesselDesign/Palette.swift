import SwiftUI

/// Vessel's palette.
///
/// The app is built around a warm parchment / deep ink ground rather than pure
/// white and black — it reads as a paper journal instead of a spreadsheet, which
/// is the whole feeling we want for something you touch five times a day.
///
/// Each of the four modules owns one saturated accent. That accent is the only
/// strong color on screen in that module, so you always know where you are
/// without reading a label.
public enum Palette {

    // MARK: - Ground

    /// Page background. Warm parchment in light, near-black warm ink in dark.
    public static let ground = PaletteTokens.ground.color

    /// Raised surface — cards, sheets, grouped rows.
    public static let surface = PaletteTokens.surface.color

    /// A surface resting on another surface (nested cards, popovers).
    public static let surfaceRaised = PaletteTokens.surfaceRaised.color

    /// Hairlines and dividers.
    public static let separator = PaletteTokens.separator.color

    // MARK: - Ink

    /// Primary text.
    public static let ink = PaletteTokens.ink.color

    /// Secondary text — subtitles, metadata.
    public static let inkSecondary = PaletteTokens.inkSecondary.color

    /// Tertiary text — timestamps, footnotes, disabled.
    public static let inkTertiary = PaletteTokens.inkTertiary.color

    // MARK: - Module accents

    /// Diet Tracker — terracotta. Warm, food-adjacent, appetizing without being loud.
    public static let diet = PaletteTokens.diet.color

    /// Water Diary — deep teal. Reads unmistakably as water.
    public static let water = PaletteTokens.water.color

    /// Journal — muted violet. Reflective, quieter than the other three.
    public static let journal = PaletteTokens.journal.color

    /// Date Log (symptoms) — soft coral. Signals attention without alarm-red panic.
    public static let symptom = PaletteTokens.symptom.color

    /// Streaks — warm ember. Deliberately distinct from the four module accents
    /// so a streak badge never reads as belonging to one module.
    public static let streak = PaletteTokens.streak.color

    // MARK: - Semantic

    public static let positive = PaletteTokens.positive.color

    public static let caution = PaletteTokens.caution.color

    public static let critical = PaletteTokens.critical.color

    /// Text and glyphs drawn *on* an accent fill — a selected tile, the log
    /// button. White on the light-theme accents; deep ink on the dark-theme
    /// ones, which are pale enough that white on them measured 2.0–3.1:1.
    public static let onAccent = PaletteTokens.onAccent.color

    // MARK: - Macro nutrients
    //
    // Distinct hues that stay distinguishable for the most common color-vision
    // deficiencies: we separate them by lightness as well as hue, so a ring chart
    // still reads correctly in grayscale.

    public static let protein = PaletteTokens.protein.color
    public static let carbs = PaletteTokens.carbs.color
    public static let fat = PaletteTokens.fat.color
    public static let fiber = PaletteTokens.fiber.color
}
