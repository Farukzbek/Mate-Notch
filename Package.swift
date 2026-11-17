// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MateNotch",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "MateNotch", path: "Sources/MateNotch")
    ]
)
