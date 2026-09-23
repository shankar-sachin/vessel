import Testing
import Foundation
@testable import VesselDesign

/// WCAG contrast for every colour the app draws text in.
///
/// Measured rather than eyeballed: on parchment the terracotta, coral, ember
/// and tertiary ink all *looked* fine and all failed AA, and white on the
/// dark-theme accents — every selected tile and the log button — sat between
/// 2.0 and 3.1:1.
@Suite("Palette contrast")
struct PaletteTests {

    /// WCAG AA for normal-size text.
    static let minimum = 4.5

    static func luminance(_ hex: UInt32) -> Double {
        func channel(_ shift: UInt32) -> Double {
            let c = Double((hex >> shift) & 0xFF) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }

    static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// The four appearances every colour resolves to.
    static let appearances: [(String, @Sendable (ColorToken) -> UInt32)] = [
        ("light", { $0.light }), ("dark", { $0.dark }),
        ("light, increased contrast", { $0.lightHC ?? $0.light }),
        ("dark, increased contrast", { $0.darkHC ?? $0.dark })
    ]

    @Test("Text colours reach AA on every ground, in every appearance")
    func textOnGrounds() {
        for (appearance, resolve) in Self.appearances {
            for text in PaletteTokens.textColors {
                for ground in PaletteTokens.grounds {
                    let ratio = Self.contrast(resolve(text), resolve(ground))
                    #expect(ratio >= Self.minimum,
                            "\(text.name) on \(ground.name), \(appearance): \(String(format: "%.2f", ratio)):1")
                }
            }
        }
    }

    @Test("What's drawn on an accent fill reaches AA")
    func onAccent() {
        for (appearance, resolve) in Self.appearances {
            for fill in PaletteTokens.fills {
                let ratio = Self.contrast(resolve(PaletteTokens.onAccent), resolve(fill))
                #expect(ratio >= Self.minimum,
                        "onAccent on \(fill.name), \(appearance): \(String(format: "%.2f", ratio)):1")
            }
        }
    }

    @Test("Increased contrast never lowers contrast")
    func increasedContrastIsHigher() {
        for text in PaletteTokens.textColors {
            let normal = Self.contrast(text.light, PaletteTokens.surface.light)
            let high = Self.contrast(text.lightHC ?? text.light, PaletteTokens.surface.lightHC ?? PaletteTokens.surface.light)
            #expect(high >= normal - 0.01, "\(text.name): increased contrast \(high) < normal \(normal)")
        }
    }
}
