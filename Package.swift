// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PinTool",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "PinTool", targets: ["PinTool"])
    ],
    targets: [
        .target(
            name: "PinToolCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "PinTool",
            dependencies: ["PinToolCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "PinToolChecks",
            dependencies: ["PinToolCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
