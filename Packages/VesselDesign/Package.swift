// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VesselDesign",
    defaultLocalization: "en",
    platforms: [.iOS(.v18), .macOS(.v15), .watchOS(.v11)],
    products: [
        .library(name: "VesselDesign", targets: ["VesselDesign"])
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: "VesselDesign",
            dependencies: [
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "VesselDesignTests",
            dependencies: ["VesselDesign"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
