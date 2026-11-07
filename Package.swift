// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QuadStatus",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "QuadStatus",
            path: "Sources/QuadStatus",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
