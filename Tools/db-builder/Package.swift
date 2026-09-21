// swift-tools-version: 6.0
import PackageDescription

// Build-time tool, not shipped in the app. Compiles the USDA FoodData Central
// CSV dumps into the single SQLite file Vessel bundles.
let package = Package(
    name: "db-builder",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "db-builder",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
