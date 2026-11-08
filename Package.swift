// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "8GBVibe",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "8GBVibe", targets: ["EightGBVibe"]),
        // MCP server for AI agents (stdio), shipped inside the app bundle.
        .executable(name: "8gbvibe-mcp", targets: ["VibeMCP"])
    ],
    targets: [
        // Reads system metrics, groups processes, alert thresholds. No UI.
        .target(name: "VibeCore"),
        // Menu bar app (SwiftUI).
        .executableTarget(name: "EightGBVibe", dependencies: ["VibeCore"]),
        .executableTarget(name: "VibeMCP", dependencies: ["VibeCore"]),
        .testTarget(name: "VibeCoreTests", dependencies: ["VibeCore"])
    ]
)
