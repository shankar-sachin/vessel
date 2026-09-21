import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// Global UIKit appearance that SwiftUI can't reach directly.
///
/// Navigation titles are the one piece of type SwiftUI won't let us restyle with
/// a modifier — `.navigationTitle` always renders in the system face. Since
/// Vessel sets every other heading in New York, leaving screen titles in SF Pro
/// made the largest text on each screen the only text that didn't match. This
/// closes that gap.
public enum VesselAppearance {

    /// Call once, as early as possible in app startup.
    @MainActor
    public static func configure() {
        #if canImport(UIKit)
        configureNavigationBars()
        #endif
    }

    #if canImport(UIKit)
    @MainActor
    private static func configureNavigationBars() {
        // Two appearances, matching what iOS does by default: transparent when
        // the content is scrolled to the top (so the large title sits directly
        // on the page ground), and a blurred bar once content slides under it.
        let scrollEdge = UINavigationBarAppearance()
        scrollEdge.configureWithTransparentBackground()
        applyTitleFonts(to: scrollEdge)

        let standard = UINavigationBarAppearance()
        standard.configureWithDefaultBackground()
        applyTitleFonts(to: standard)

        let bar = UINavigationBar.appearance()
        bar.standardAppearance = standard
        bar.compactAppearance = standard
        bar.scrollEdgeAppearance = scrollEdge
        bar.compactScrollEdgeAppearance = scrollEdge
    }

    @MainActor
    private static func applyTitleFonts(to appearance: UINavigationBarAppearance) {
        appearance.largeTitleTextAttributes = [
            .font: serifFont(size: 34, weight: .bold, textStyle: .largeTitle),
            .foregroundColor: UIColor(Palette.ink)
        ]
        appearance.titleTextAttributes = [
            .font: serifFont(size: 17, weight: .semibold, textStyle: .headline),
            .foregroundColor: UIColor(Palette.ink)
        ]
    }

    /// New York at a given size, scaled for the user's Dynamic Type setting.
    ///
    /// UIKit appearance proxies take a concrete `UIFont`, not a text style, so
    /// the scaling has to be applied here — otherwise titles would be the only
    /// text in the app that ignores Larger Text.
    private static func serifFont(
        size: CGFloat,
        weight: UIFont.Weight,
        textStyle: UIFont.TextStyle
    ) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)

        // `withDesign(.serif)` can return nil if the serif face is unavailable,
        // in which case the system font is a perfectly good fallback.
        let serif: UIFont
        if let descriptor = base.fontDescriptor.withDesign(.serif) {
            // Re-assert the weight: switching design resets the descriptor's
            // weight trait on some systems, which quietly renders titles light.
            let weighted = descriptor.addingAttributes([
                .traits: [UIFontDescriptor.TraitKey.weight: weight]
            ])
            serif = UIFont(descriptor: weighted, size: size)
        } else {
            serif = base
        }

        return UIFontMetrics(forTextStyle: textStyle).scaledFont(for: serif)
    }
    #endif
}
