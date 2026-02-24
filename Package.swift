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
            url: "https://github.com/model-health/model-health-swift/releases/download/v0.1.25/ModelHealthFFI.xcframework.zip",
            checksum: "a6f48dc97d1eca3e39e5c99fa6a9d44c701e8b82d8d090c7b1320281e577cf87"
        ),
        .target(
            name: "ModelHealth",
            dependencies: ["ModelHealthFFI"],
            path: "Sources/ModelHealth"
        ),
    ]
)
