// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftPico",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "swiftpico", targets: ["SwiftPicoCLI"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "SwiftPicoCLI",
            dependencies: [],
            path: "Sources/SwiftPicoCLI"
        )
    ]
)
