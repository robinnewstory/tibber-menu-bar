// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TibberCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "TibberCore", targets: ["TibberCore"])],
    targets: [
        .target(name: "TibberCore"),
        .testTarget(name: "TibberCoreTests", dependencies: ["TibberCore"], resources: [.copy("Fixtures")]),
    ]
)
