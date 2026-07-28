// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "YueduCoreText",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "YueduCoreText",
            targets: ["YueduCoreText"]
        ),
        .library(
            name: "YueduCoreTextTypography",
            targets: ["YueduCoreTextTypography"]
        ),
    ],
    targets: [
        .target(
            name: "YueduCoreText"
        ),
        .target(
            name: "YueduCoreTextTypography"
        ),
        .testTarget(
            name: "YueduCoreTextTests",
            dependencies: ["YueduCoreText"]
        ),
        .testTarget(
            name: "YueduCoreTextTypographyTests",
            dependencies: ["YueduCoreTextTypography"]
        ),
    ]
)
