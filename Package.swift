// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ModelHealth",
    platforms: [
        .iOS(.v15),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "ModelHealth",
            targets: ["ModelHealth"]
        ),
        .library(
            name: "ModelHealthUI",
            targets: ["ModelHealthUI"]
        )
    ],
    targets: [
        .binaryTarget(
            name: "ModelHealthFFI",
            url: "https://github.com/model-health/model-health-swift/releases/download/v0.11.3/ModelHealthFFI.xcframework.zip",
            checksum: "7e59fbbd2c7f68e13c80542ef638e10c9a2d04a06a788d37f6d74045933c7bae"
        ),
        .target(
            name: "ModelHealth",
            dependencies: ["ModelHealthFFI"],
            path: "Sources/ModelHealth"
        ),
        .target(
            name: "ModelHealthUI",
            dependencies: ["ModelHealth"],
            path: "Sources/ModelHealthUI",
            resources: [
                .copy("Resources/WebBundle")
            ]
        ),
    ]
)
