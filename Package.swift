// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "mlController",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(
            url: "https://github.com/httpswift/swifter.git",
            .upToNextMajor(from: "1.5.0")
        )
    ],
    targets: [
        .executableTarget(
            name: "mlController",
            dependencies: [
                .product(name: "Swifter", package: "swifter")
            ],
            path: "Sources/mlController",
            resources: [
                .copy("Resources/web")
            ]
        )
    ]
)
