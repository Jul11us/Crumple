import Foundation
import Testing
@testable import Crumple

/// The promises in the README's "Care in the defaults": what starts ticked, and what is held back.
/// Every scan here runs against a sandbox folder, never the real home.
@Suite("扫描的默认勾选")
struct ScanDefaultsTests {
    let fm = FileManager.default

    func sandbox() throws -> URL {
        let url = fm.temporaryDirectory.appendingPathComponent("crumple-defaults-\(UUID().uuidString)")
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    func file(_ path: String, in root: URL, ageDays: Double? = nil) throws -> URL {
        let url = root.appendingPathComponent(path)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: 8_192).write(to: url)
        if let ageDays {
            // Both the modification and the access time, since old downloads look at whichever is later.
            let seconds = Int(Date().addingTimeInterval(-ageDays * 86_400).timeIntervalSince1970)
            var times = [timeval(tv_sec: seconds, tv_usec: 0), timeval(tv_sec: seconds, tv_usec: 0)]
            #expect(utimes(url.path, &times) == 0)
        }
        return url
    }

    func byName(_ items: [CleanItem]) -> [String: CleanItem] {
        Dictionary(uniqueKeysWithValues: items.map { ($0.url.lastPathComponent, $0) })
    }

    @Test("运行中的应用的缓存不勾选，名字相近的不受影响")
    func runningAppCachesStayUnticked() throws {
        let caches = try sandbox()
        defer { try? fm.removeItem(at: caches) }
        for folder in ["com.example.editor", "com.example.editor.helper", "com.example.editorial", "com.other.app",
                       "\(Scanner.ownBundleID).tests"] {
            try file("\(folder)/data", in: caches)
        }

        let items = byName(Scanner.scanAppFolders(in: caches, running: ["com.example.editor"]))
        #expect(items["com.example.editor"]?.isSelected == false)
        #expect(items["com.example.editor"]?.badge != nil)
        #expect(items["com.example.editor.helper"]?.isSelected == false)
        #expect(items["com.example.editorial"]?.isSelected == true)
        #expect(items["com.other.app"]?.isSelected == true)
        #expect(items["\(Scanner.ownBundleID).tests"] == nil, "Crumple's own folders are never listed")
    }

    @Test("日志不看应用是否在运行")
    func logsIgnoreRunningApps() throws {
        let logs = try sandbox()
        defer { try? fm.removeItem(at: logs) }
        try file("com.example.editor/today.log", in: logs)
        let items = Scanner.scanAppFolders(in: logs, running: nil)
        #expect(items.count == 1)
        #expect(items.allSatisfy { $0.isSelected })
    }

    @Test("安装包一律不勾选")
    func installersStartUnticked() throws {
        let home = try sandbox()
        defer { try? fm.removeItem(at: home) }
        for name in ["App.dmg", "Tool.PKG", "Disk.iso", "notes.txt"] { try file("Downloads/\(name)", in: home) }

        let items = byName(Scanner.scanInstallers(home))
        #expect(Set(items.keys) == ["App.dmg", "Tool.PKG", "Disk.iso"])
        #expect(items.values.allSatisfy { !$0.isSelected })
    }

    @Test("旧下载只列出很久没动的，安装包不重复列出，也都不勾选")
    func oldDownloadsStartUnticked() throws {
        let home = try sandbox()
        defer { try? fm.removeItem(at: home) }
        try file("Downloads/old.zip", in: home, ageDays: 200)
        try file("Downloads/Old.dmg", in: home, ageDays: 200)
        try file("Downloads/recent.zip", in: home, ageDays: 3)

        let items = byName(Scanner.scanOldDownloads(home, days: 90))
        #expect(Set(items.keys) == ["old.zip"])
        #expect(items["old.zip"]?.isSelected == false)
        #expect(items["old.zip"]?.badge != nil)
    }

    @Test("已知可重新下载的开发缓存才勾选，其余列出但不勾选")
    func devCachesTickOnlyKnownCaches() throws {
        let home = try sandbox()
        defer { try? fm.removeItem(at: home) }
        try file(".npm/_cacache/index", in: home)
        try file("Library/pnpm/store/v3/file", in: home)
        try file(".cache/pip/http/file", in: home)
        try file(".cache/mystery-tool/state", in: home)

        let items = byName(Scanner.scanDevCaches(home))
        #expect(items["_cacache"]?.isSelected == true)
        #expect(items["store"]?.isSelected == false)
        #expect(items["pip"]?.isSelected == true)
        #expect(items["mystery-tool"]?.isSelected == false)
    }
}
