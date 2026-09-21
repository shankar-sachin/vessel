// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VesselCore",
    defaultLocalization: "en",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "VesselCore", targets: ["VesselCore"])
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: "VesselCore",
            dependencies: [
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "VesselCoreTests",
            dependencies: ["VesselCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
