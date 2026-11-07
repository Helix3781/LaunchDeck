// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LaunchDeck",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "LaunchDeck", path: "Sources")
    ]
)
