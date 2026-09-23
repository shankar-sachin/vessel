// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VesselNutrition",
    defaultLocalization: "en",
    platforms: [.iOS(.v18), .macOS(.v15), .watchOS(.v11)],
    products: [
        .library(name: "VesselNutrition", targets: ["VesselNutrition"])
    ],
    dependencies: [
        .package(path: "../VesselCore"),    ],
    targets: [
        .target(
            name: "VesselNutrition",
            dependencies: [
                .product(name: "VesselCore", package: "VesselCore")
            ],
            // The compiled USDA database ships inside the package rather than
            // the app target, so anything depending on VesselNutrition — the
            // app, tests, future tools — gets it automatically.
            resources: [.copy("Resources/foods.sqlite")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "VesselNutritionTests",
            dependencies: ["VesselNutrition"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
