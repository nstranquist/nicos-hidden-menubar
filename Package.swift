// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NicosHiddenMenuBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "NicosHiddenMenuBar",
            path: "Sources/NicosHiddenMenuBar"
        ),
        .testTarget(
            name: "NicosHiddenMenuBarTests",
            dependencies: ["NicosHiddenMenuBar"],
            path: "Tests/NicosHiddenMenuBarTests"
        ),
    ]
)
