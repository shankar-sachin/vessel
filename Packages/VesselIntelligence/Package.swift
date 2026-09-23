// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VesselIntelligence",
    defaultLocalization: "en",
    platforms: [.iOS(.v18), .macOS(.v15), .watchOS(.v11)],
    products: [
        .library(name: "VesselIntelligence", targets: ["VesselIntelligence"])
    ],
    dependencies: [
        .package(path: "../VesselCore"),
        .package(path: "../VesselNutrition"),    ],
    targets: [
        .target(
            name: "VesselIntelligence",
            dependencies: [
                .product(name: "VesselCore", package: "VesselCore"),
                .product(name: "VesselNutrition", package: "VesselNutrition")
            ],
            // `.process` compiles the Core ML models at build time, so the app
            // loads a ready .mlmodelc instead of compiling on first launch.
            resources: [
                .process("Resources/VesselIntent.mlmodel"),
                .process("Resources/VesselTagger.mlmodel")
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "VesselIntelligenceTests",
            dependencies: ["VesselIntelligence"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
