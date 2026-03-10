// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "qrgo",
    platforms: [
        .macOS(.v12)  // Updated to macOS 12 to support ScreenCaptureKit
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "qrgo",
            dependencies: ["qrgoLib"]),
        .target(
            name: "qrgoLib",
            dependencies: []),
        .testTarget(
            name: "qrgoTests",
            dependencies: ["qrgoLib"]),
    ]
)
