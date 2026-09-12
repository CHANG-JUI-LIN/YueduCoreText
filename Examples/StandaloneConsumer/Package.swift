// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "YueduCoreTextConsumer",
    platforms: [.iOS(.v17)],
    products: [.library(name: "Consumer", targets: ["Consumer"])],
    dependencies: [.package(path: "../..")],
    targets: [
        .target(name: "Consumer", dependencies: [.product(name: "YueduCoreText", package: "YueduCoreText")]),
        .testTarget(name: "ConsumerTests", dependencies: ["Consumer", .product(name: "YueduCoreText", package: "YueduCoreText")])
    ]
)
