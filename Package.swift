// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "SimpleVideoRecorder",
    platforms: [.macOS(.v14)],
    targets: [.executableTarget(name: "SimpleVideoRecorder", path: "Sources")]
)
