// swift-tools-version:5.10
import PackageDescription

var products: [Product] = [
    .library(name: "ZTronRoutingKit", targets: ["RoutingKit"]),
    // The upstream product name, so that this package is a drop-in replacement for vapor/routing-kit.
    .library(name: "RoutingKit", targets: ["RoutingKit"]),
]

var targets: [Target] = [
    .target(
        name: "RoutingKit",
        dependencies: [
            .product(name: "Logging", package: "swift-log")
        ],
        swiftSettings: swiftSettings
    ),
    .testTarget(
        name: "RoutingKitTests",
        dependencies: [
            .target(name: "RoutingKit")
        ],
        swiftSettings: swiftSettings
    ),
]

// ZNavigation is SwiftUI: it exists only where SwiftUI does, so Linux and Android builds see the router alone.
#if canImport(Darwin)
    products.append(.library(name: "ZTronNavigationKit", targets: ["ZNavigation"]))
    targets.append(
        .target(
            name: "ZNavigation",
            dependencies: [
                .target(name: "RoutingKit"),
                .product(name: "Logging", package: "swift-log"),
            ],
            swiftSettings: swiftSettings
        )
    )
    targets.append(
        .testTarget(
            name: "ZNavigationTests",
            dependencies: [
                .target(name: "ZNavigation"),
                .target(name: "RoutingKit"),
            ],
            swiftSettings: swiftSettings
        )
    )
#endif

let package = Package(
    name: "ztron-routing-kit",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .tvOS(.v13),
        .watchOS(.v6),
    ],
    products: products,
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.4")
    ],
    targets: targets
)

var swiftSettings: [SwiftSetting] {
    [
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("MemberImportVisibility"),
        .enableExperimentalFeature("StrictConcurrency=complete"),
    ]
}
