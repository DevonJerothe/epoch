// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "EpochLLM",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "EpochLLM", targets: ["EpochLLM"])],
    targets: [
        .target(name: "EpochLLM"),
        .testTarget(name: "EpochLLMTests", dependencies: ["EpochLLM"]),
    ]
)
