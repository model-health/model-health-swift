// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ModelHealth",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
    ],
    products: [
        .library(
            name: "ModelHealth",
            targets: ["ModelHealth"]
        )
    ],
    targets: [
        .binaryTarget(
            name: "ModelHealthFFI",
            url: "https://github.com/model-health/model-health-swift/releases/download/v0.1.26/ModelHealthFFI.xcframework.zip",
            checksum: "fadce352075a06a414b4b2f82f697eb9f25b1a2af1f42c6018b7264eb21ca8b5"
        ),
        .target(
            name: "ModelHealth",
            dependencies: ["ModelHealthFFI"],
            path: "Sources/ModelHealth"
        ),
    ]
)
