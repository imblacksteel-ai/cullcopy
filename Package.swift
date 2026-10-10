// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SDImporter",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SDImporter",
            path: "Sources/SDImporter",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
