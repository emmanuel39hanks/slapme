// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SlapMe",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "SlapMe", targets: ["SlapMe"]),
        .executable(name: "SlapMeDaemon", targets: ["SlapMeDaemon"]),
    ],
    targets: [
        .executableTarget(
            name: "SlapMe",
            path: "SlapMe",
            resources: [
                .copy("Resources/SoundPacks")
            ]
        ),
        .executableTarget(
            name: "SlapMeDaemon",
            path: "SlapMeDaemon"
        ),
        .testTarget(
            name: "SlapMeTests",
            dependencies: ["SlapMe"],
            path: "Tests"
        ),
    ]
)
