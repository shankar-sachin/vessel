import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Dynamic color construction

public extension Color {
    /// Builds a color that resolves differently in light and dark, and lifts to a
    /// higher-contrast variant when the user has asked for increased contrast.
    ///
    /// Defined in code rather than an asset catalog so the palette stays diffable,
    /// reviewable, and testable.
    static func vessel(
        light: UInt32,
        dark: UInt32,
        lightHC: UInt32? = nil,
        darkHC: UInt32? = nil
    ) -> Color {
        #if canImport(UIKit)
        return Color(uiColor: UIColor { traits in
            let increased = traits.accessibilityContrast == .high
            switch (traits.userInterfaceStyle, increased) {
            case (.dark, true):  return UIColor(hex: darkHC ?? dark)
            case (.dark, false): return UIColor(hex: dark)
            case (_, true):      return UIColor(hex: lightHC ?? light)
            default:             return UIColor(hex: light)
            }
        })
        #else
        return Color(hex: light)
        #endif
    }

    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

#if canImport(UIKit)
extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
#endif
