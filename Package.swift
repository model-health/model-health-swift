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
            url: "https://github.com/model-health/model-health-swift/releases/download/v0.1.36/ModelHealthFFI.xcframework.zip",
            checksum: "b0325cecb8098c45d84cafb66e5c606fc95eab3ee2f5e1b065404c61cc3fd172"
        ),
        .target(
            name: "ModelHealth",
            dependencies: ["ModelHealthFFI"],
            path: "Sources/ModelHealth"
        ),
    ]
)
