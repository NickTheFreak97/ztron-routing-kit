// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ztron-routing-kit",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .tvOS(.v13),
        .watchOS(.v6),
    ],
    products: [
        .library(name: "ZTronRoutingKit", targets: ["RoutingKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.3"),
    ],
    targets: [
        .target(
            name: "RoutingKit",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "RoutingKitTests",
            dependencies: [
                .target(name: "RoutingKit"),
            ],
            swiftSettings: swiftSettings
        ),
    ]
)

var swiftSettings: [SwiftSetting] { [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableExperimentalFeature("StrictConcurrency=complete"),
] }
