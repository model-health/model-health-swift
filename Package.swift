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
            url: "https://github.com/model-health/model-health-swift/releases/download/v0.12.0/ModelHealthFFI.xcframework.zip",
            checksum: "9eb5ec6e7cb0cfce29702c5ae701f2c24d5d4f2cf4efa7c523c83cde4cb70e0a"
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
