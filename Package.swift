// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "8GBVibe",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "8GBVibe", targets: ["EightGBVibe"])
    ],
    targets: [
        // Reads system metrics, groups processes, alert thresholds. No UI.
        .target(name: "VibeCore"),
        // Menu bar app (SwiftUI).
        .executableTarget(name: "EightGBVibe", dependencies: ["VibeCore"]),
        .testTarget(name: "VibeCoreTests", dependencies: ["VibeCore"])
    ]
)
