// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TibberCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "TibberCore", targets: ["TibberCore"])],
    targets: [
        .target(name: "TibberCore", swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "TibberCoreTests", dependencies: ["TibberCore"], resources: [.copy("Fixtures")], swiftSettings: [.swiftLanguageMode(.v6)]),
    ]
)
