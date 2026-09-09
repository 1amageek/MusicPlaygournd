// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "LiveSet",
    platforms: [.macOS(.v15)],
    products: [.library(name: "LiveSet", targets: ["LiveSet"])],
    dependencies: [.package(url: "https://github.com/1amageek/SwiftMusic.git", exact: "0.3.0")],
    targets: [.target(name: "LiveSet", dependencies: [.product(name: "SwiftMusic", package: "SwiftMusic")], resources: [.copy("Resources")])]
)