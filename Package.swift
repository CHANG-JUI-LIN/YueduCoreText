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
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", exact: "2.13.7"),
    ],
    targets: [
        .target(
            name: "YueduCoreText",
            dependencies: ["YueduCoreTextTypography", .product(name: "SwiftSoup", package: "SwiftSoup")]
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
