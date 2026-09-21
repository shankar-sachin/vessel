// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VesselActivities",
    defaultLocalization: "en",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "VesselActivities", targets: ["VesselActivities"])
    ],
    targets: [
        .target(name: "VesselActivities", swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(
            name: "VesselActivitiesTests",
            dependencies: ["VesselActivities"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
