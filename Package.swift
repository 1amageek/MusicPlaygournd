// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "MusicPlaygournd",
    platforms: [.macOS(.v15), .iOS(.v27)],
    products: [
        .executable(name: "MusicPlaygournd", targets: ["MusicPlaygourndApp"]),
        .library(name: "MusicPlaygourndCore", targets: ["MusicPlaygourndCore"]),
        .library(name: "MusicPlayground", targets: ["MusicPlayground"]),
        .library(name: "MusicPlaygroundUI", targets: ["MusicPlaygroundUI"])
    ],
    dependencies: [
        .package(url: "https://github.com/1amageek/SwiftMusic.git", exact: "0.5.1"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "604.0.0")
    ],
    targets: [
        .target(name: "MusicPlaygroundUI", dependencies: [.product(name: "SwiftSyntax", package: "swift-syntax"), .product(name: "SwiftParser", package: "swift-syntax"), .product(name: "SwiftIDEUtils", package: "swift-syntax"), .product(name: "SwiftParserDiagnostics", package: "swift-syntax"), .product(name: "SwiftBasicFormat", package: "swift-syntax")], exclude: ["DESIGN.md", "Workspace/DESIGN.md", "Sidebar/DESIGN.md", "Deck/DESIGN.md", "Editor/DESIGN.md", "Effect/DESIGN.md", "Wave/DESIGN.md", "Control/DESIGN.md"]),
        .target(name: "MusicPlayground", dependencies: [.product(name: "SwiftMusic", package: "SwiftMusic")], exclude: ["DESIGN.md"]),
        .target(
            name: "MusicPlaygourndCore",
            dependencies: ["MusicPlayground", .product(name: "SwiftMusic", package: "SwiftMusic")],
            exclude: ["DESIGN.md", "Evaluation/DESIGN.md", "Rendering/DESIGN.md", "Playback/DESIGN.md", "MIDI/DESIGN.md", "AudioUnits/DESIGN.md"]
        ),
        .executableTarget(
            name: "MusicPlaygourndApp",
            dependencies: ["MusicPlaygroundUI", "MusicPlaygourndCore", .product(name: "SwiftMusic", package: "SwiftMusic")],
            exclude: ["DESIGN.md", "Editor/DESIGN.md", "Editor/Presentation/DESIGN.md"]
        ),
        .executableTarget(name: "MIDINativeTestHost", dependencies: ["MusicPlaygourndCore"],
            path: "Tests/MIDINativeTestHost"),
        .testTarget(name: "MusicPlaygourndCoreTests", dependencies: ["MusicPlaygroundUI", "MusicPlaygourndCore", "MusicPlaygourndApp", "MIDINativeTestHost"],
            path: "Tests/MusicPlaygourndCoreTests")
    ]
)
