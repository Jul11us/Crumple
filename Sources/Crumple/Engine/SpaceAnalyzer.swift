import Foundation
import AppKit
import SwiftUI

/// Breaks a folder down by what's inside it, measuring each child in the background.
@MainActor @Observable
final class SpaceAnalyzer {
    enum Base: String, CaseIterable, Identifiable {
        case home, applications

        var id: String { rawValue }
        var title: String { self == .home ? String(localized: "个人文件夹") : String(localized: "应用程序") }
        var url: URL { self == .home ? Paths.home : Paths.applicationFolders[0] }
    }

    struct Entry: Identifiable, Hashable {
        let url: URL
        let name: String
        let isFolder: Bool
        var size: Int64?
        /// Folders macOS guards with a privacy prompt; we leave them unmeasured.
        var isProtected = false

        var id: URL { url }
    }

    private(set) var base: Base = .home
    /// The folders from the base down to the one being shown.
    private(set) var trail: [URL] = []
    private(set) var entries: [Entry] = []
    private(set) var pending = 0

    @ObservationIgnored private var cache: [URL: Int64] = [:]
    @ObservationIgnored private var token = 0

    var current: URL { trail.last ?? base.url }
    var total: Int64 { entries.compactMap(\.size).reduce(0, +) }

    func open(base: Base) {
        self.base = base
        trail = [base.url]
        load()
    }

    func open(_ entry: Entry) {
        guard entry.isFolder, !entry.isProtected else { return }
        trail.append(entry.url)
        load()
    }

    func goBack(to index: Int) {
        guard index < trail.count - 1 else { return }
        trail = Array(trail.prefix(index + 1))
        load()
    }

    func rescan() {
        cache = [:]
        load()
    }

    func remove(_ entry: Entry) {
        entries.removeAll { $0.url == entry.url }
        // Every folder above it is now smaller.
        cache = cache.filter { !entry.url.path.hasPrefix($0.key.path + "/") && $0.key != entry.url }
    }

    private func load() {
        token += 1
        let token = token
        let urls = (try? FileManager.default.contentsOfDirectory(at: current, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey])) ?? []
        entries = urls.map { url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            let isFolder = values?.isDirectory == true && values?.isPackage != true
            var name = FileManager.default.displayName(atPath: url.path)
            if values?.isPackage == true, name.hasSuffix(".app") { name = String(name.dropLast(4)) }
            let isProtected = Self.isProtected(url)
            return Entry(url: url, name: name, isFolder: isFolder, size: isProtected ? 0 : cache[url], isProtected: isProtected)
        }
        sortEntries()
        let todo = entries.filter { $0.size == nil }.map(\.url)
        pending = todo.count
        guard !todo.isEmpty else { return }

        Task {
            await withTaskGroup(of: (URL, Int64).self) { group in
                var queue = todo.makeIterator()
                for _ in 0..<min(6, todo.count) {
                    if let url = queue.next() { group.addTask { (url, Self.size(of: url)) } }
                }
                while let (url, size) = await group.next() {
                    guard token == self.token else {
                        group.cancelAll()
                        return
                    }
                    cache[url] = size
                    if let i = entries.firstIndex(where: { $0.url == url }) { entries[i].size = size }
                    pending -= 1
                    if let next = queue.next() { group.addTask { (next, Self.size(of: next)) } }
                }
            }
            if token == self.token { withAnimation(.snappy) { sortEntries() } }
        }
    }

    private func sortEntries() {
        entries.sort { a, b in
            switch (a.size, b.size) {
            case let (x?, y?) where x != y: return x > y
            case (nil, _?): return false
            case (_?, nil): return true
            default: return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
        }
    }

    // MARK: - Measuring

    nonisolated private static let protectedNames: Set<String> = ["Containers", "Group Containers", "Mail", "Messages", "Safari", "Cookies"]

    nonisolated private static func isProtected(_ url: URL) -> Bool {
        url.deletingLastPathComponent().lastPathComponent == "Library" && protectedNames.contains(url.lastPathComponent)
    }

    nonisolated static func size(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        if values.isDirectory != true {
            return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in true }
        ) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            if isProtected(file) {
                enumerator.skipDescendants()
                continue
            }
            guard let v = try? file.resourceValues(forKeys: keys), v.isRegularFile == true else { continue }
            total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        return total
    }
}
