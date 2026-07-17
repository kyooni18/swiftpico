// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftPico",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "swiftpico", targets: ["SwiftPicoCLI"]),
        .library(name: "SwiftPicoCore", targets: ["SwiftPicoCore"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "SwiftPicoCLI",
            dependencies: ["SwiftPicoCore"],
            path: "Sources/SwiftPicoCLI"
        ),
        .target(name: "SwiftPicoCore", path: "Sources/SwiftPicoCore"),
        .testTarget(
            name: "SwiftPicoCoreTests",
            dependencies: ["SwiftPicoCore"],
            path: "Tests/SwiftPicoCoreTests"
        )
    ]
)
