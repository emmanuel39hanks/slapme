// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SlapMe",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "SlapMe", targets: ["SlapMe"]),
    ],
    targets: [
        .executableTarget(
            name: "SlapMe",
            path: "SlapMe",
            resources: [
                .copy("Resources/SoundPacks")
            ]
        ),
        .testTarget(
            name: "SlapMeTests",
            dependencies: ["SlapMe"],
            path: "Tests"
        ),
    ]
)
