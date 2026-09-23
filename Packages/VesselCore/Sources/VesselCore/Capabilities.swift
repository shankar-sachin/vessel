import Foundation

#if canImport(UIKit)
import UIKit
#endif

/// The single place in Vessel that asks "what OS is this?".
///
/// Feature code reads booleans off this type and never writes `if #available`
/// inline. That matters for two reasons: the availability rules stay in one
/// reviewable file instead of scattering across dozens of views, and the tier
/// can be overridden in tests and previews so we can actually exercise the
/// iOS 18 path on a 26 simulator.
public struct VesselCapabilities: Sendable, Equatable {

    /// What the running OS can offer.
    public enum Tier: Int, Sendable, Comparable, CaseIterable {
        /// iOS/iPadOS 18–25. A complete app: our own language model, our own
        /// vision models, voice logging, every tracker, Siri. What it lacks is
        /// Apple's newest on-device frameworks.
        case essential = 0
        /// iOS/iPadOS 26+. Adds the on-device foundation model as a parsing
        /// fallback, streaming transcription, and Liquid Glass.
        case full = 1

        public static func < (lhs: Tier, rhs: Tier) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public let tier: Tier

    public init(tier: Tier) {
        self.tier = tier
    }

    /// The real capabilities of the device this is running on.
    public static let current: VesselCapabilities = {
        #if DEBUG
        // Drives the Essential path on a 26+ simulator, since no iOS 18
        // runtime ships with current Xcode. UI tests launch with it set.
        if ProcessInfo.processInfo.environment["VESSEL_FORCE_TIER"] == "essential" {
            return VesselCapabilities(tier: .essential)
        }
        #endif
        if #available(iOS 26.0, macOS 26.0, *) {
            return VesselCapabilities(tier: .full)
        }
        return VesselCapabilities(tier: .essential)
    }()

    // MARK: - Feature gates

    /// Apple's on-device foundation model, used only as a fallback when our own
    /// tagger is unsure. Note this being `true` means the *framework* exists —
    /// the model itself can still be unavailable (unsupported device, Apple
    /// Intelligence switched off, model still downloading), so callers must also
    /// handle a nil session at runtime.
    public var hasFoundationModels: Bool { tier >= .full }

    /// `SpeechAnalyzer` streaming transcription. Below this we use
    /// `SFSpeechRecognizer`, which works but gives coarser partial results.
    public var hasStreamingTranscription: Bool { tier >= .full }

    /// Liquid Glass material and the morphing tab bar.
    public var hasLiquidGlass: Bool { tier >= .full }

    /// Apple Intelligence assistant schemas on top of plain App Intents.
    public var hasAssistantSchemas: Bool { tier >= .full }

    /// Vision × FoundationModels scene description for low-confidence plates.
    public var hasVisionLanguageDescription: Bool { tier >= .full }

    /// True when the device is missing capabilities we'd like it to have, which
    /// is what drives the (single, dismissible) upgrade prompt.
    public var canUpgrade: Bool { tier < .full }

    // MARK: - Upgrade messaging

    /// "iOS" or "iPadOS" — so the prompt names the OS the user actually has
    /// rather than guessing.
    @MainActor
    public static var osDisplayName: String {
        #if os(watchOS)
        return "watchOS"
        #elseif os(iOS)
        switch UIDevice.current.userInterfaceIdiom {
        case .pad: return "iPadOS"
        case .mac: return "macOS"
        default:   return "iOS"
        }
        #else
        return "macOS"
        #endif
    }

    public static var upgradePromptTitle: String {
        "Unlock the full Vessel"
    }

    @MainActor
    public static var upgradePromptMessage: String {
        "Upgrade to \(osDisplayName) 26 to experience the full version of Vessel."
    }

    /// What's actually gained, listed plainly. Vague "new features!" copy earns
    /// nothing; naming the four concrete wins respects the reader.
    public static var upgradeBenefits: [String] {
        [
            "Smarter parsing of unusual phrasings",
            "Live transcription as you speak",
            "Richer photo understanding",
            "The Liquid Glass interface"
        ]
    }
}
