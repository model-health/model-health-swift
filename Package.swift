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
            targets: ["ModelHealthFFI"]
        )
    ],
    targets: [
        .binaryTarget(
            name: "ModelHealthFFI",
            url: "https://github.com/model-health/model-health-swift/releases/download/v0.1.17/ModelHealthFFI.xcframework.zip",
            checksum: "788538e419e268b57e969cca4ea90a6c2e3572eab095eb43e4793c132725bfaa"
        ),
    ]
)
