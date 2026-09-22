// swift-tools-version: 6.0
import PackageDescription

// Build-time tool. Generates the labelled training corpus for Vessel's parser.
//
// Depends on VesselIntelligence for one reason: every generated sentence is
// passed through the app's own `TextNormalizer` before it is written, so the
// models train on exactly the token stream they will see at inference.
let package = Package(
    name: "corpus-gen",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(path: "../../Packages/VesselIntelligence")
    ],
    targets: [
        .executableTarget(
            name: "corpus-gen",
            dependencies: [.product(name: "VesselIntelligence", package: "VesselIntelligence")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
