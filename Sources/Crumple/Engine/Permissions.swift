import AppKit

/// The macOS privacy permissions Crumple benefits from, and shortcuts to the right settings pane.
enum Permissions {
    /// Full Disk Access lets Crumple see the Trash, Mail downloads and other apps' caches.
    /// There's no API to ask; the only test is whether a file it protects can be opened.
    static var hasFullDiskAccess: Bool {
        if Paths.isDemo { return true }
        guard let handle = FileHandle(forReadingAtPath: "/Library/Application Support/com.apple.TCC/TCC.db") else { return false }
        try? handle.close()
        return true
    }

    static func openFullDiskAccessSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
    }

    static func openAutomationSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
    }

    static func openNotificationSettings() {
        open("x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(Bundle.main.bundleIdentifier ?? "")")
    }

    private static func open(_ link: String) {
        if let url = URL(string: link) { NSWorkspace.shared.open(url) }
    }

    /// Size of the user's Trash, or nil when it can't be read (no Full Disk Access).
    static func trashSize() -> Int64? {
        let trash = Paths.home.appendingPathComponent(".Trash")
        guard (try? FileManager.default.contentsOfDirectory(atPath: trash.path)) != nil else { return nil }
        return SpaceAnalyzer.size(of: trash)
    }
}
