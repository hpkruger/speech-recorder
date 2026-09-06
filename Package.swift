// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "SpeechRecorder",
    platforms: [.macOS(.v14)],
    targets: [.executableTarget(name: "SpeechRecorder", path: "Sources")]
)
