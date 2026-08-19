// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Tally",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Tally", path: "Sources/Tally")
    ]
)
