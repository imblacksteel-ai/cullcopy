// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CullCopy",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "CullCopy",
            path: "Sources/CullCopy",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
