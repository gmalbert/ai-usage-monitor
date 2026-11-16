// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AIUsageMonitorMac",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AIUsageMonitorCore", targets: ["AIUsageMonitorCore"]),
    ],
    targets: [
        .target(
            name: "AIUsageMonitorCore",
            path: "Sources/AIUsageMonitorCore"
        ),
        .testTarget(
            name: "AIUsageMonitorCoreTests",
            dependencies: ["AIUsageMonitorCore"],
            path: "Tests/AIUsageMonitorCoreTests"
        ),
    ]
)
