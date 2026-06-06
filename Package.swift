// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Hopr",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Hopr",
            path: "Sources/Hopr",
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("Carbon"),
            ]
        ),
    ]
)
