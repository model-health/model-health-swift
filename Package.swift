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
            url: "https://github.com/model-health/model-health-swift/releases/download/v0.11.2/ModelHealthFFI.xcframework.zip",
            checksum: "db637d1c64aa666eba458be2f1b5f64aff563ada185b810c216c6ad574d031e1"
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
