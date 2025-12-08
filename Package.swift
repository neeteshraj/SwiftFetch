// swift-tools-version:5.9

import PackageDescription

let package = Package(
    name: "SwiftFetch",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .watchOS(.v8)
    ],
    products: [
        .library(
            name: "SwiftFetch",
            targets: ["SwiftFetch"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SwiftFetch",
            dependencies: []
        ),
        .testTarget(
            name: "SwiftFetchTests",
            dependencies: ["SwiftFetch"]
        )
    ]
)

