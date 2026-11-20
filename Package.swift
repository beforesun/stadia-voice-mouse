// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StadiaVoiceMouse",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "stadia-voice-mouse", targets: ["StadiaVoiceMouse"])],
    targets: [.executableTarget(name: "StadiaVoiceMouse")]
)
