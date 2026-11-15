// swift-tools-version: 5.10
import PackageDescription

// Lógica pura do LIFE RESET: sem SwiftUI, sem SwiftData, totalmente testável.
let package = Package(
    name: "LifeResetCore",
    defaultLocalization: "pt-PT",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "LifeResetCore", targets: ["LifeResetCore"]),
    ],
    targets: [
        .target(name: "LifeResetCore", path: "Sources/LifeResetCore"),
        .testTarget(name: "LifeResetCoreTests", dependencies: ["LifeResetCore"], path: "Tests/LifeResetCoreTests"),
    ]
)
