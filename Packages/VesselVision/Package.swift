// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VesselVision",
    defaultLocalization: "en",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "VesselVision", targets: ["VesselVision"])
    ],
    dependencies: [
        .package(path: "../VesselCore"),
        .package(path: "../VesselNutrition"),    ],
    targets: [
        .target(
            name: "VesselVision",
            dependencies: [
                .product(name: "VesselCore", package: "VesselCore"),
                .product(name: "VesselNutrition", package: "VesselNutrition"),            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "VesselVisionTests",
            dependencies: ["VesselVision"],
            // Real food photographs, so the recogniser is measured against
            // actual images rather than assumed to work.
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
