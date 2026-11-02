// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "devcheck",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "devcheck", targets: ["DevCheckApp"]),
        .library(name: "DevCheckCore", targets: ["DevCheckCore"]),
    ],
    targets: [
        .target(
            name: "DevCheckCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "DevCheckApp",
            dependencies: ["DevCheckCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "DevCheckCoreTests",
            dependencies: ["DevCheckCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)