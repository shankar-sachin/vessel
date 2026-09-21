// swift-tools-version: 6.0
import PackageDescription

// Build-time tool. Trains Vessel's parser models with Create ML and writes the
// Core ML artifacts the app bundles. macOS only — CreateML doesn't exist on iOS.
let package = Package(
    name: "model-trainer",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "model-trainer",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
