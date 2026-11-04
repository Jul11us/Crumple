import Foundation

enum Cleaner {
    /// What happened to one item: whether it is gone, and where its files went in the Trash.
    struct Outcome: Sendable {
        var removed = false
        var trashed: [TrashedFile] = []
    }

    /// Cleans an item and the files that go with it (an app's leftovers).
    /// Succeeds when the item itself is gone; leftovers are best effort.
    static func clean(_ item: CleanItem, mode: CleanMode) -> Outcome {
        var outcome = Outcome()
        if let place = discard(item.url, mode: mode) {
            outcome.removed = true
            if let place { outcome.trashed.append(TrashedFile(original: item.url.path, trashed: place.path)) }
        } else if item.url.pathExtension == "app", !Paths.isDemo,
                  // Apps installed by the App Store belong to root; Finder can move them after asking for a password.
                  let place = trashWithFinder(item.url) {
            outcome.removed = true
            outcome.trashed.append(TrashedFile(original: item.url.path, trashed: place.path))
        }
        guard outcome.removed else { return outcome }
        for component in item.components where component.url != item.url {
            if let place = discard(component.url, mode: mode), let place {
                outcome.trashed.append(TrashedFile(original: component.url.path, trashed: place.path))
            }
        }
        return outcome
    }

    /// Moves one file to the Trash or deletes it. Refuses anything outside the safe zones
    /// (see `isSafeTarget`).
    static func clean(_ url: URL, mode: CleanMode) -> Bool {
        discard(url, mode: mode) != nil
    }

    /// nil when the file couldn't be removed; otherwise where it went in the Trash
    /// (an inner nil when it was deleted outright).
    static func discard(_ url: URL, mode: CleanMode) -> URL?? {
        guard isSafeTarget(url) else { return nil }
        do {
            switch mode {
            case .trash:
                if Paths.isDemo { return .some(try moveToDemoTrash(url)) }
                var place: NSURL?
                try FileManager.default.trashItem(at: url, resultingItemURL: &place)
                return .some(place as URL?)
            case .delete:
                try FileManager.default.removeItem(at: url)
                return .some(nil)
            }
        } catch {
            return nil
        }
    }

    /// Demo files go to a Trash folder inside the sandbox, named the way Finder would.
    private static func moveToDemoTrash(_ url: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: Paths.trash, withIntermediateDirectories: true)
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var target = Paths.trash.appendingPathComponent(url.lastPathComponent)
        var n = 2
        while exists(target) {
            target = Paths.trash.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        try fm.moveItem(at: url, to: target)
        return target
    }

    /// Puts a trashed file back where it was. Refuses when something else now sits at the
    /// original path, or when the file is no longer in the Trash.
    static func restore(_ file: TrashedFile) -> Bool {
        let from = URL(fileURLWithPath: file.trashed)
        let to = URL(fileURLWithPath: file.original)
        guard isInTrash(from), isSafeTarget(to), exists(from), !exists(to) else { return false }
        do {
            try FileManager.default.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: from, to: to)
            return true
        } catch {
            return false
        }
    }

    static func isInTrash(_ url: URL) -> Bool {
        let parts = url.standardizedFileURL.pathComponents
        return parts.contains(".Trash") || parts.contains(".Trashes")
    }

    /// Like `fileExists`, but a symbolic link counts as itself rather than what it points to.
    static func exists(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }

    /// Something at least two levels inside the home folder (so never ~ or ~/Library itself) and
    /// outside the `NeverTouch` places, or an app sitting directly in one of the Applications folders.
    static func isSafeTarget(_ url: URL) -> Bool {
        let parts = components(url)
        if url.pathExtension == "app", Paths.applicationFolders.contains(where: { components($0) == Array(parts.dropLast()) }) {
            return true
        }
        let home = components(Paths.home)
        guard parts.count >= home.count + 2, Array(parts.prefix(home.count)) == home else { return false }
        return !NeverTouch.contains(Array(parts.dropFirst(home.count)))
    }

    static func components(_ url: URL) -> [String] { Paths.components(url) }

    /// Asks Finder to move something to the Trash and returns where it went. Finder shows its own
    /// password dialog for items the user doesn't own. Same safety rule as everything else.
    static func trashWithFinder(_ url: URL) -> URL? {
        guard isSafeTarget(url) else { return nil }
        let path = url.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Finder" to set moved to delete (POSIX file "\(path)" as alias)
        POSIX path of (moved as alias)
        """
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0, !exists(url) else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let place = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        // Finder adds a trailing slash to folders and bundles.
        return URL(fileURLWithPath: place.hasSuffix("/") ? String(place.dropLast()) : place)
    }

    /// Asks Finder to empty the Trash (needs the Automation permission the first time).
    /// In demo mode it just empties the sandbox's Trash folder.
    static func emptyTrash() -> Bool {
        if Paths.isDemo {
            let fm = FileManager.default
            for url in (try? fm.contentsOfDirectory(at: Paths.trash, includingPropertiesForKeys: nil)) ?? [] {
                try? fm.removeItem(at: url)
            }
            return true
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "tell application \"Finder\" to empty trash"]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

/// Places that hold keys, passwords or an app's own database. Nothing re-creates them once they
/// are gone, so they are refused even deep inside home, whichever page asks (Space Lens shows
/// hidden folders, for one). The Windows edition refuses the same kinds of places; both are
/// checked against Tests/Shared/never-touch.json.
enum NeverTouch {
    /// Folders refused wherever they appear, with everything inside them.
    static let folderNames: Set<String> = [".ssh", ".gnupg", ".aws", ".azure", ".kube"]
    /// Bundles and keychain files refused wherever they appear.
    static let extensions: Set<String> = ["photoslibrary", "keychain", "keychain-db"]
    /// Folders below home refused with everything inside them.
    static let homeFolders: [[String]] = [
        "Library/Keychains", "Library/Mail", "Library/Messages", "Library/Accounts",
        "Library/Application Support/Crumple",
    ].map { $0.lowercased().split(separator: "/").map(String.init) }

    /// `relative` is a path's components below home. Compared without case, because the Mac's
    /// disk usually ignores it: ~/library/keychains is the same folder as ~/Library/Keychains.
    static func contains(_ relative: [String]) -> Bool {
        let parts = relative.map { $0.lowercased() }
        return parts.contains { folderNames.contains($0) || extensions.contains(($0 as NSString).pathExtension) }
            || homeFolders.contains { parts.starts(with: $0) }
    }
}

/// Cleaning history, kept as a small JSON file in Application Support.
enum HistoryStore {
    private static var fileURL: URL { Paths.appSupport.appendingPathComponent("history.json") }

    static func load() -> [HistoryEntry] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([HistoryEntry].self, from: data)) ?? []
    }

    static func save(_ entries: [HistoryEntry]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entries) else { return }
        try? FileManager.default.createDirectory(at: Paths.appSupport, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
