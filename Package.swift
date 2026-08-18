// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ALLaunchGuard",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(
            name: "ALLaunchGuard",
            targets: ["ALLaunchGuard"]
        )
    ],
    targets: [
        .target(
            name: "ALLaunchGuard",
            path: "Sources/ALLaunchGuard"
        ),
        .testTarget(
            name: "ALLaunchGuardTests",
            dependencies: ["ALLaunchGuard"],
            path: "Tests/ALLaunchGuardTests"
        )
    ],
    swiftLanguageVersions: [.v6]
)
