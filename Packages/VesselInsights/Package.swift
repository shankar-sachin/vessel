// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VesselInsights",
    defaultLocalization: "en",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "VesselInsights", targets: ["VesselInsights"])
    ],
    dependencies: [
        .package(path: "../VesselCore"),    ],
    targets: [
        .target(
            name: "VesselInsights",
            dependencies: [
                .product(name: "VesselCore", package: "VesselCore"),            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "VesselInsightsTests",
            dependencies: ["VesselInsights"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
