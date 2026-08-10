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
            url: "https://github.com/model-health/model-health-swift/releases/download/v0.9.1/ModelHealthFFI.xcframework.zip",
            checksum: "13d9f3a904c0c745fa4f9e583c73bb0f60bbf47c1e5899d28ca61a0073a22c93"
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
