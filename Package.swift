// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HoprClone",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "HoprClone",
            path: "Sources/HoprClone",
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("Carbon"),
            ]
        ),
    ]
)
