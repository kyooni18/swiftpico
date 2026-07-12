// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftPico",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "swiftpico", targets: ["SwiftPicoCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/kyooni18/PicoKit.git", from: "0.1.1")
    ],
    targets: [
        .executableTarget(
            name: "SwiftPicoCLI",
            dependencies: [.product(name: "PicoKit", package: "PicoKit")],
            path: "Sources/SwiftPicoCLI"
        )
    ]
)
