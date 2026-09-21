// swift-tools-version: 6.0
import PackageDescription

// Build-time tool. Generates the labelled training corpus for Vessel's parser.
let package = Package(
    name: "corpus-gen",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "corpus-gen",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
