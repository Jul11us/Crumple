import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.appearance = AppModel.shared?.appearance.nsAppearance
        NSApp.activate()
    }

    /// Clicking the Dock icon (or opening the app again) brings the window back after it was closed.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            MainActor.assumeIsolated { AppModel.shared?.openMainWindow?() }
        }
        return true
    }

    // With the menu bar icon on, closing the window leaves Crumple running there.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !(UserDefaults.standard.object(forKey: "showsMenuBarExtra") as? Bool ?? true)
    }
}

struct CrumpleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    // A plain `let` rather than @State: on the macOS 27 SDK @State is a macro whose
    // plugin only ships with full Xcode, and this project builds with Command Line Tools.
    private let model = AppModel()

    var body: some Scene {
        Window("Crumple", id: "main") {
            ContentView()
                .tint(Theme.accent)
                .environment(model)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 780)
        .windowResizability(.contentMinSize)
        .commands { AppMenuCommands(model: model) }

        Window("关于 Crumple", id: "about") {
            AboutView()
                .tint(Theme.accent)
                .environment(model)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Settings {
            SettingsView()
                .tint(Theme.accent)
                .environment(model)
                .preferredColorScheme(model.appearance.colorScheme)
        }

        MenuBarExtra(isInserted: Binding(get: { model.showsMenuBarExtra }, set: { model.showsMenuBarExtra = $0 })) {
            MenuBarPanel()
                .tint(Theme.accent)
                .environment(model)
        } label: {
            Image(nsImage: MenuBarIcon.image)
        }
        .menuBarExtraStyle(.window)
    }
}
