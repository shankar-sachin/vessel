import SwiftUI

/// The palette as data: every colour's hex value for each appearance.
///
/// Kept apart from `Palette` so the values can be *tested*. `PaletteTests`
/// checks every text colour and accent against the grounds it sits on, in
/// both themes, at WCAG AA (4.5:1). Four light-theme accents and the tertiary
/// ink failed that when it was first measured; the values below are the
/// corrected ones, darkened in lightness only so each hue stays itself.
public struct ColorToken: Sendable {
    public let name: String
    public let light: UInt32
    public let dark: UInt32
    public let lightHC: UInt32?
    public let darkHC: UInt32?

    public var color: Color { .vessel(light: light, dark: dark, lightHC: lightHC, darkHC: darkHC) }
}

public enum PaletteTokens {
    public static let ground = ColorToken(name: "ground", light: 0xFAF6F0, dark: 0x121110, lightHC: 0xFFFFFF, darkHC: 0x000000)
    public static let surface = ColorToken(name: "surface", light: 0xFFFFFF, dark: 0x1C1A18, lightHC: 0xFFFFFF, darkHC: 0x222020)
    public static let surfaceRaised = ColorToken(name: "surfaceRaised", light: 0xFFFDFA, dark: 0x262320, lightHC: 0xFFFFFF, darkHC: 0x2E2B28)
    public static let separator = ColorToken(name: "separator", light: 0xE4DCD1, dark: 0x332F2B, lightHC: 0x9A9086, darkHC: 0x6A635C)
    public static let ink = ColorToken(name: "ink", light: 0x1A1714, dark: 0xF5F0E8, lightHC: 0x000000, darkHC: 0xFFFFFF)
    public static let inkSecondary = ColorToken(name: "inkSecondary", light: 0x5C5349, dark: 0xB3AAA0, lightHC: 0x3A342D, darkHC: 0xD6CFC6)
    public static let inkTertiary = ColorToken(name: "inkTertiary", light: 0x776E64, dark: 0x938A81, lightHC: 0x5C5349, darkHC: 0xA39A91)
    public static let diet = ColorToken(name: "diet", light: 0xAC5837, dark: 0xE08B5F, lightHC: 0x94441F, darkHC: 0xF5A87C)
    public static let water = ColorToken(name: "water", light: 0x1E7A78, dark: 0x4FBDB4, lightHC: 0x0D5250, darkHC: 0x76D8CF)
    public static let journal = ColorToken(name: "journal", light: 0x6B5B95, dark: 0x9B8AC4, lightHC: 0x4A3C70, darkHC: 0xB8A9DC)
    public static let symptom = ColorToken(name: "symptom", light: 0xC43F4F, dark: 0xF08A94, lightHC: 0x9A2F3C, darkHC: 0xFFA8B0)
    public static let streak = ColorToken(name: "streak", light: 0xA0611B, dark: 0xF2A950, lightHC: 0xA35E12, darkHC: 0xFFC078)
    public static let positive = ColorToken(name: "positive", light: 0x3F7D52, dark: 0x6FBF87, lightHC: 0x275538, darkHC: 0x92D9A6)
    public static let caution = ColorToken(name: "caution", light: 0x956713, dark: 0xE0AE4F, lightHC: 0x805508, darkHC: 0xF5C978)
    public static let critical = ColorToken(name: "critical", light: 0xB03A2E, dark: 0xE8705F, lightHC: 0x821F16, darkHC: 0xFF9484)
    public static let onAccent = ColorToken(name: "onAccent", light: 0xFFFFFF, dark: 0x121110, lightHC: 0xFFFFFF, darkHC: 0x000000)
    public static let protein = ColorToken(name: "protein", light: 0x8A4F9E, dark: 0xBE8FD0, lightHC: nil, darkHC: nil)
    public static let carbs = ColorToken(name: "carbs", light: 0xD98324, dark: 0xF2A950, lightHC: nil, darkHC: nil)
    public static let fat = ColorToken(name: "fat", light: 0x3E7CA6, dark: 0x79B4DB, lightHC: nil, darkHC: nil)
    public static let fiber = ColorToken(name: "fiber", light: 0x5C8A3F, dark: 0x9BC97A, lightHC: nil, darkHC: nil)

    /// Colours used as text or glyphs on the page.
    public static let textColors: [ColorToken] = [
        ink, inkSecondary, inkTertiary, diet, water, journal, symptom, streak, positive, caution, critical
    ]
    /// What they sit on.
    public static let grounds: [ColorToken] = [ground, surface, surfaceRaised]
    /// Accents that get filled, with `onAccent` drawn over them.
    public static let fills: [ColorToken] = [diet, water, journal, symptom]
}
