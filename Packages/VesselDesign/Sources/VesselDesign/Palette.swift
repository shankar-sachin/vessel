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
    public static let ground = Color.vessel(
        light: 0xFAF6F0, dark: 0x121110,
        lightHC: 0xFFFFFF, darkHC: 0x000000
    )

    /// Raised surface — cards, sheets, grouped rows.
    public static let surface = Color.vessel(
        light: 0xFFFFFF, dark: 0x1C1A18,
        lightHC: 0xFFFFFF, darkHC: 0x222020
    )

    /// A surface resting on another surface (nested cards, popovers).
    public static let surfaceRaised = Color.vessel(
        light: 0xFFFDFA, dark: 0x262320,
        lightHC: 0xFFFFFF, darkHC: 0x2E2B28
    )

    /// Hairlines and dividers.
    public static let separator = Color.vessel(
        light: 0xE4DCD1, dark: 0x332F2B,
        lightHC: 0x9A9086, darkHC: 0x6A635C
    )

    // MARK: - Ink

    /// Primary text.
    public static let ink = Color.vessel(
        light: 0x1A1714, dark: 0xF5F0E8,
        lightHC: 0x000000, darkHC: 0xFFFFFF
    )

    /// Secondary text — subtitles, metadata.
    public static let inkSecondary = Color.vessel(
        light: 0x5C5349, dark: 0xB3AAA0,
        lightHC: 0x3A342D, darkHC: 0xD6CFC6
    )

    /// Tertiary text — timestamps, footnotes, disabled.
    public static let inkTertiary = Color.vessel(
        light: 0x8C8176, dark: 0x7D746B,
        lightHC: 0x5C5349, darkHC: 0xA39A91
    )

    // MARK: - Module accents

    /// Diet Tracker — terracotta. Warm, food-adjacent, appetizing without being loud.
    public static let diet = Color.vessel(
        light: 0xC2643F, dark: 0xE08B5F,
        lightHC: 0x94441F, darkHC: 0xF5A87C
    )

    /// Water Diary — deep teal. Reads unmistakably as water.
    public static let water = Color.vessel(
        light: 0x1E7A78, dark: 0x4FBDB4,
        lightHC: 0x0D5250, darkHC: 0x76D8CF
    )

    /// Journal — muted violet. Reflective, quieter than the other three.
    public static let journal = Color.vessel(
        light: 0x6B5B95, dark: 0x9B8AC4,
        lightHC: 0x4A3C70, darkHC: 0xB8A9DC
    )

    /// Date Log (symptoms) — soft coral. Signals attention without alarm-red panic.
    public static let symptom = Color.vessel(
        light: 0xC94F5D, dark: 0xF08A94,
        lightHC: 0x9A2F3C, darkHC: 0xFFA8B0
    )

    /// Streaks — warm ember. Deliberately distinct from the four module accents
    /// so a streak badge never reads as belonging to one module.
    public static let streak = Color.vessel(
        light: 0xD98324, dark: 0xF2A950,
        lightHC: 0xA35E12, darkHC: 0xFFC078
    )

    // MARK: - Semantic

    public static let positive = Color.vessel(
        light: 0x3F7D52, dark: 0x6FBF87,
        lightHC: 0x275538, darkHC: 0x92D9A6
    )

    public static let caution = Color.vessel(
        light: 0xB07A16, dark: 0xE0AE4F,
        lightHC: 0x805508, darkHC: 0xF5C978
    )

    public static let critical = Color.vessel(
        light: 0xB03A2E, dark: 0xE8705F,
        lightHC: 0x821F16, darkHC: 0xFF9484
    )

    // MARK: - Macro nutrients
    //
    // Distinct hues that stay distinguishable for the most common color-vision
    // deficiencies: we separate them by lightness as well as hue, so a ring chart
    // still reads correctly in grayscale.

    public static let protein = Color.vessel(light: 0x8A4F9E, dark: 0xBE8FD0)
    public static let carbs   = Color.vessel(light: 0xD98324, dark: 0xF2A950)
    public static let fat     = Color.vessel(light: 0x3E7CA6, dark: 0x79B4DB)
    public static let fiber   = Color.vessel(light: 0x5C8A3F, dark: 0x9BC97A)
}
