// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VesselIntents",
    defaultLocalization: "en",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "VesselIntents", targets: ["VesselIntents"])
    ],
    dependencies: [
        .package(path: "../VesselCore"),
        .package(path: "../VesselNutrition"),
        .package(path: "../VesselIntelligence"),    ],
    targets: [
        .target(
            name: "VesselIntents",
            dependencies: [
                .product(name: "VesselCore", package: "VesselCore"),
                .product(name: "VesselNutrition", package: "VesselNutrition"),
                .product(name: "VesselIntelligence", package: "VesselIntelligence"),            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "VesselIntentsTests",
            dependencies: ["VesselIntents"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
