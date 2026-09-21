// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VesselNutrition",
    defaultLocalization: "en",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "VesselNutrition", targets: ["VesselNutrition"])
    ],
    dependencies: [
        .package(path: "../VesselCore"),    ],
    targets: [
        .target(
            name: "VesselNutrition",
            dependencies: [
                .product(name: "VesselCore", package: "VesselCore"),            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "VesselNutritionTests",
            dependencies: ["VesselNutrition"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
