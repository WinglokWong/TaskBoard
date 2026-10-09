// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "TaskBoard",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "TaskBoard", path: "Sources/TaskBoard")
    ]
)
