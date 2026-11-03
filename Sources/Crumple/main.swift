import AppKit
import Foundation

// Developer flags (used by build.sh and for checking the artwork); otherwise launch the app.
let arguments = CommandLine.arguments

func argument(after flag: String) -> URL? {
    guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
    return URL(fileURLWithPath: arguments[i + 1])
}

if let dir = argument(after: "--render-interface") {
    MainActor.assumeIsolated { DevTools.renderInterface(to: dir) }
    exit(0)
}
if let dir = argument(after: "--render-icon") {
    MainActor.assumeIsolated { DevTools.renderIconSet(to: dir) }
    exit(0)
}
if let dir = argument(after: "--render-splash") {
    MainActor.assumeIsolated { DevTools.renderSplash(to: dir) }
    exit(0)
}
if let dir = argument(after: "--render-logos") {
    MainActor.assumeIsolated { DevTools.renderLogos(to: dir) }
    exit(0)
}
if let dir = argument(after: "--render-dmg-background") {
    MainActor.assumeIsolated { DevTools.renderDMGBackground(to: dir) }
    exit(0)
}
if let dir = argument(after: "--render-basket") {
    MainActor.assumeIsolated { DevTools.renderBasketMoments(to: dir) }
    exit(0)
}
if let dir = argument(after: "--render-shredder") {
    MainActor.assumeIsolated { DevTools.renderShredder(to: dir) }
    exit(0)
}
if let dir = argument(after: "--render-previews") {
    MainActor.assumeIsolated { DevTools.renderPreviews(to: dir) }
    exit(0)
}
if let dir = argument(after: "--render-menubar") {
    MainActor.assumeIsolated { DevTools.renderMenuBar(to: dir) }
    exit(0)
}
if arguments.contains("--scan-report") {
    DevTools.printScanReport()
    exit(0)
}

CrumpleApp.main()
