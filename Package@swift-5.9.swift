// swift-tools-version:5.9
import PackageDescription

var products: [Product] = [
    .library(name: "ZTronRoutingKit", targets: ["RoutingKit"]),
    .library(name: "RoutingKit", targets: ["RoutingKit"]),
]

var targets: [Target] = [
    .target(
        name: "RoutingKit",
        dependencies: [
            .product(name: "Logging", package: "swift-log")
        ],
        swiftSettings: [
            .enableExperimentalFeature("StrictConcurrency=complete")
        ]),
    .testTarget(
        name: "RoutingKitTests",
        dependencies: ["RoutingKit"],
        swiftSettings: [
            .enableExperimentalFeature("StrictConcurrency=complete")
        ]
    ),
]

// ZNavigation is SwiftUI: it exists only where SwiftUI does, so Linux and Android builds see the router alone.
#if canImport(Darwin)
    products.append(.library(name: "ZTronNavigationKit", targets: ["ZNavigation"]))
    targets.append(
        .target(
            name: "ZNavigation",
            dependencies: [
                "RoutingKit",
                .product(name: "Logging", package: "swift-log"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency=complete")
            ])
    )
    targets.append(
        .testTarget(
            name: "ZNavigationTests",
            dependencies: ["ZNavigation", "RoutingKit"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency=complete")
            ]
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
