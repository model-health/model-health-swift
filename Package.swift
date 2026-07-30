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
            url: "https://github.com/model-health/model-health-swift/releases/download/v0.8.0/ModelHealthFFI.xcframework.zip",
            checksum: "003165974025ccd771dcbccba0abae4506a5f733c135bd3866f631eccb5042f9"
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
