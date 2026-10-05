// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StaleDefaultReference",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "StaleDefaultReference", targets: ["StaleDefaultReference"]),
    ],
    targets: [
        .target(name: "StaleDefaultReference"),
        .testTarget(name: "StaleDefaultReferenceTests", dependencies: ["StaleDefaultReference"]),
    ]
)
