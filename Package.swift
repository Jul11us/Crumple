// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Crumple",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Crumple",
            path: "Sources/Crumple"
        ),
        .testTarget(
            name: "CrumpleTests",
            dependencies: ["Crumple"],
            path: "Tests/CrumpleTests",
            // Command Line Tools keep the Swift Testing macros in a subfolder the compiler doesn't search.
            swiftSettings: [.unsafeFlags(["-plugin-path", "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"])]
        ),
    ]
)
