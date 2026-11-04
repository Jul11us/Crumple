// swift-tools-version:5.10
import Foundation
import PackageDescription

// Command Line Tools keep the Swift Testing macros in a subfolder the compiler doesn't search, so
// tests need an extra plugin path there. Xcode finds them by itself, and pointing its compiler at
// the Command Line Tools' plugins could load a mismatched version, so the flag is only added when
// the Command Line Tools are the active developer folder (DEVELOPER_DIR, else `xcode-select`).
let commandLineTools = "/Library/Developer/CommandLineTools"
let testingPlugins = commandLineTools + "/usr/lib/swift/host/plugins/testing"
let developerDir = ProcessInfo.processInfo.environment["DEVELOPER_DIR"]
    ?? (try? FileManager.default.destinationOfSymbolicLink(atPath: "/var/db/xcode_select_link"))
let usesCommandLineTools = developerDir.map { $0.hasPrefix(commandLineTools) }
    ?? !FileManager.default.fileExists(atPath: "/Applications/Xcode.app")
let testSettings: [SwiftSetting] = usesCommandLineTools && FileManager.default.fileExists(atPath: testingPlugins)
    ? [.unsafeFlags(["-plugin-path", testingPlugins])]
    : []

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
            swiftSettings: testSettings
        ),
    ]
)
