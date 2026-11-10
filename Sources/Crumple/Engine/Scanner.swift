import Foundation
import AppKit
import CoreServices

/// Finds cleanable items. Everything here only reads the disk.
enum Scanner {
    static let ownBundleID = "com.ziyuanjing.Crumple"
    static let installerExtensions: Set<String> = ["dmg", "pkg", "mpkg", "xip", "iso"]

    /// Package-manager caches that are always safe to re-download.
    private static let devCacheSpecs: [(path: String, name: String, selected: Bool)] = [
        (".npm/_cacache", String(localized: "npm 缓存"), true),
        (".yarn/berry/cache", String(localized: "Yarn 缓存"), true),
        (".bun/install/cache", String(localized: "Bun 缓存"), true),
        (".gradle/caches", String(localized: "Gradle 缓存"), true),
        (".cargo/registry/cache", String(localized: "Cargo 下载缓存"), true),
        ("go/pkg/mod/cache/download", String(localized: "Go 模块下载缓存"), true),
        (".android/cache", String(localized: "Android 缓存"), true),
        ("Library/pnpm/store", String(localized: "pnpm 存储"), false),
        (".m2/repository", String(localized: "Maven 本地仓库"), false),
        (".cocoapods/repos", String(localized: "CocoaPods 索引"), false),
    ]

    /// Folders in ~/.cache that we know are plain caches. Anything else there is listed but left unticked.
    private static let knownDotCaches: Set<String> = [
        "pip", "uv", "node-gyp", "pre-commit", "typescript", "yarn", "ms-playwright", "puppeteer", "huggingface", "torch",
    ]

    /// `runningProcesses` guards the files of command-line tools, which have no bundle ID (see `ProcessWatch`).
    static func scan(_ kind: CategoryKind, runningBundleIDs: Set<String>, runningProcesses: Set<String> = [],
                     oldDownloadDays: Int = 90) -> [CleanItem] {
        let home = Paths.home
        let items: [CleanItem]
        switch kind {
        case .appCaches:
            items = scanAppFolders(in: home.appendingPathComponent("Library/Caches"), running: runningBundleIDs)
        case .logs:
            items = scanAppFolders(in: home.appendingPathComponent("Library/Logs"), running: nil)
        case .xcode:
            items = scanXcode(home)
        case .devCaches:
            items = scanDevCaches(home)
        case .aiTools:
            items = scanAITools(home, running: runningProcesses)
        case .installers:
            let urls = children(of: home.appendingPathComponent("Downloads"))
                .filter { installerExtensions.contains($0.pathExtension.lowercased()) }
            items = makeItems(urls, selected: false) { $0.lastPathComponent }
        case .oldDownloads:
            items = scanOldDownloads(home, days: oldDownloadDays)
        case .largeFiles, .duplicates, .applications:
            items = [] // scanned by their own pages, see scanLargeFiles / DuplicateFinder / scanApplications
        }
        return items.filter { $0.size > 0 }.sorted { $0.size > $1.size }
    }

    // MARK: - Large files

    static let largeFileFolders = ["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures"]

    /// Walks the personal folders for files of at least `minBytes`. Packages (apps, photo libraries…)
    /// are skipped as a whole, so nothing inside them is ever offered for deletion.
    static func scanLargeFiles(minBytes: Int64, progress: @escaping @Sendable (Int) -> Void) -> [CleanItem] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isPackageKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
                                      .contentModificationDateKey, .contentAccessDateKey]
        var items: [CleanItem] = []
        var checked = 0
        for folder in largeFileFolders {
            let root = Paths.home.appendingPathComponent(folder)
            guard let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { continue }
            for case let url as URL in enumerator {
                checked += 1
                if checked % 400 == 0 {
                    if Task.isCancelled { return [] }
                    progress(checked)
                }
                guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
                if values.isPackage == true { continue }
                guard values.isRegularFile == true else { continue }
                let size = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
                guard size >= minBytes else { continue }
                let lastUsed = max(values.contentModificationDate ?? .distantPast, values.contentAccessDate ?? .distantPast)
                let tag = FileTag.of(url)
                items.append(CleanItem(
                    id: url.path, url: url, name: url.lastPathComponent,
                    detail: String(localized: "\(Paths.display(url.deletingLastPathComponent())) · \(lastUsed.agoText)打开过"),
                    size: size, isSelected: false, tag: tag, lastUsed: lastUsed
                ))
            }
        }
        progress(checked)
        return items.sorted { $0.size > $1.size }
    }

    // MARK: - Applications

    /// Lists third-party apps with their size, last use, and the files they left in ~/Library.
    static func scanApplications(progress: @escaping @Sendable (Int, Int) -> Void) -> [CleanItem] {
        var bundles: [(url: URL, bundle: Bundle, id: String)] = []
        for folder in Paths.applicationFolders {
            for url in children(of: folder) where url.pathExtension == "app" {
                guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
                      !id.hasPrefix("com.apple."), id != ownBundleID else { continue }
                bundles.append((url, bundle, id))
            }
        }
        let total = bundles.count
        progress(0, total)

        let counter = Counter()
        var results = [CleanItem?](repeating: nil, count: total)
        results.withUnsafeMutableBufferPointer { buffer in
            let base = buffer.baseAddress
            DispatchQueue.concurrentPerform(iterations: total) { i in
                base?[i] = describeApp(bundles[i].url, bundle: bundles[i].bundle, id: bundles[i].id)
                progress(counter.increment(), total)
            }
        }
        return results.compactMap { $0 }.sorted { $0.size > $1.size }
    }

    private static func describeApp(_ url: URL, bundle: Bundle, id: String) -> CleanItem {
        let info = bundle.infoDictionary ?? [:]
        var name = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? ""
        if name.isEmpty { name = url.deletingPathExtension().lastPathComponent }
        let version = info["CFBundleShortVersionString"] as? String
        let appSize = allocatedSize(of: url)

        let library = Paths.home.appendingPathComponent("Library")
        let candidates: [(String, String)] = [
            ("Application Support/\(id)", String(localized: "支持文件")),
            ("Application Support/\(name)", String(localized: "支持文件")),
            ("Caches/\(id)", String(localized: "缓存")),
            ("Preferences/\(id).plist", String(localized: "偏好设置")),
            ("Saved Application State/\(id).savedState", String(localized: "窗口状态")),
            ("HTTPStorages/\(id)", String(localized: "网络存储")),
            ("WebKit/\(id)", String(localized: "网页数据")),
            ("Logs/\(name)", String(localized: "日志")),
            ("Logs/\(id)", String(localized: "日志")),
        ]
        var seen: Set<String> = []
        var leftovers: [CleanItem.Component] = []
        for (path, label) in candidates {
            let leftover = library.appendingPathComponent(path)
            guard !seen.contains(leftover.path), FileManager.default.fileExists(atPath: leftover.path) else { continue }
            seen.insert(leftover.path)
            leftovers.append(.init(name: label, url: leftover, size: allocatedSize(of: leftover)))
        }

        var lastUsed: Date?
        if let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL) {
            lastUsed = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
        }
        let isAppStore = FileManager.default.fileExists(atPath: url.appendingPathComponent("Contents/_MASReceipt/receipt").path)
        let leftoverSize = leftovers.reduce(Int64(0)) { $0 + $1.size }

        var detailParts: [String] = []
        if let version { detailParts.append(String(localized: "版本 \(version)")) }
        detailParts.append(lastUsed.map { String(localized: "\($0.agoText)用过") } ?? String(localized: "没有使用记录"))
        if !leftovers.isEmpty { detailParts.append(String(localized: "\(leftovers.count) 个残留文件")) }

        let unused = lastUsed.map { Date().timeIntervalSince($0) > 180 * 86_400 } ?? false
        return CleanItem(
            id: url.path, url: url, name: name, detail: detailParts.joined(separator: " · "),
            size: appSize + leftoverSize, isSelected: false,
            badge: unused ? String(localized: "很久没用") : nil, appURL: url, ownerBundleID: id,
            lastUsed: lastUsed, version: version, isAppStore: isAppStore,
            components: [.init(name: String(localized: "应用本体"), url: url, size: appSize)] + leftovers
        )
    }

    private final class Counter: @unchecked Sendable {
        private var value = 0
        private let lock = NSLock()

        func increment() -> Int {
            lock.lock()
            defer { lock.unlock() }
            value += 1
            return value
        }
    }

    // MARK: - Categories

    /// `running` is nil for folders where a running app doesn't matter (logs).
    private static func scanAppFolders(in dir: URL, running: Set<String>?) -> [CleanItem] {
        let urls = children(of: dir).filter { !$0.lastPathComponent.hasPrefix(ownBundleID) }
        let sizes = measure(urls)
        return zip(urls, sizes).map { url, size in
            let folder = url.lastPathComponent
            let app = application(forFolderNamed: folder)
            let isRunning = running?.contains { folder == $0 || folder.hasPrefix($0 + ".") } ?? false
            return CleanItem(
                id: url.path,
                url: url,
                name: app?.name ?? folder,
                detail: Paths.display(url),
                size: size,
                isSelected: !isRunning,
                badge: isRunning ? String(localized: "运行中") : nil,
                appURL: app?.url,
                ownerBundleID: running != nil && folder.split(separator: ".").count >= 3 ? folder : nil
            )
        }
    }

    private static func scanXcode(_ home: URL) -> [CleanItem] {
        let developer = home.appendingPathComponent("Library/Developer")
        let xcode = developer.appendingPathComponent("Xcode")
        var result: [CleanItem] = []

        result += makeItems(children(of: xcode.appendingPathComponent("DerivedData")), selected: true) { url in
            let name = url.lastPathComponent
            // "MyApp-abcdefghijklmnopqrstuvwxyzab" → "MyApp"
            if let dash = name.lastIndex(of: "-"), name.distance(from: dash, to: name.endIndex) > 20 {
                return String(localized: "\(name[..<dash]) 编译产物")
            }
            return name
        }
        for platform in ["iOS", "watchOS", "tvOS", "visionOS"] {
            let dir = xcode.appendingPathComponent("\(platform) DeviceSupport")
            result += makeItems(children(of: dir), selected: true) { String(localized: "\(platform) 设备支持 \($0.lastPathComponent)") }
        }
        result += makeItems(children(of: xcode.appendingPathComponent("Archives")), selected: false) { String(localized: "归档 \($0.lastPathComponent)") }
        result += makeItems(existing([developer.appendingPathComponent("CoreSimulator/Caches")]), selected: true) { _ in String(localized: "模拟器缓存") }
        return result
    }

    private static func scanDevCaches(_ home: URL) -> [CleanItem] {
        var entries: [(url: URL, name: String, selected: Bool)] = devCacheSpecs.compactMap { spec in
            let url = home.appendingPathComponent(spec.path)
            return FileManager.default.fileExists(atPath: url.path) ? (url, spec.name, spec.selected) : nil
        }
        for child in children(of: home.appendingPathComponent(".cache")) where !aiDotCaches.contains(child.lastPathComponent) {
            let name = child.lastPathComponent
            entries.append((child, "~/.cache/\(name)", knownDotCaches.contains(name)))
        }
        let sizes = measure(entries.map(\.url))
        return zip(entries, sizes).map { entry, size in
            CleanItem(id: entry.url.path, url: entry.url, name: entry.name, detail: Paths.display(entry.url), size: size, isSelected: entry.selected)
        }
    }

    private static func scanOldDownloads(_ home: URL, days minimumDays: Int) -> [CleanItem] {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .contentAccessDateKey]
        let now = Date()
        var idleDays: [URL: Int] = [:]
        for url in children(of: home.appendingPathComponent("Downloads"))
        where !installerExtensions.contains(url.pathExtension.lowercased()) {
            let values = try? url.resourceValues(forKeys: keys)
            let lastTouched = max(values?.contentModificationDate ?? .distantPast, values?.contentAccessDate ?? .distantPast)
            let days = Int(now.timeIntervalSince(lastTouched) / 86_400)
            if days >= minimumDays { idleDays[url] = days }
        }
        let urls = Array(idleDays.keys)
        return zip(urls, measure(urls)).map { url, size in
            CleanItem(id: url.path, url: url, name: url.lastPathComponent, detail: Paths.display(url), size: size,
                      isSelected: false, badge: String(localized: "\(idleDays[url] ?? 0) 天没动过"))
        }
    }


    // MARK: - AI tools

    /// How an AI tool's folder is treated. Caches are ticked. Downloads (runtimes, VM images, models) come back
    /// when needed but are big, so they are only listed. Conversations are never offered at all: see `conversationStores`.
    enum AITier { case cache, download }

    struct AITool {
        let name: String
        /// Process names that own these files; while one runs, the items stay out of the basket.
        let processes: [String]
        /// An Electron-style folder under ~/Library/Application Support whose cache subfolders make one item.
        let appSupport: String?
        let places: [(path: String, label: String, tier: AITier)]
    }

    static let aiTools: [AITool] = [
        AITool(name: "Claude", processes: ["Claude"], appSupport: "Claude", places: [
            ("Library/Application Support/Claude/vm_bundles", String(localized: "虚拟机镜像"), .download),
        ]),
        AITool(name: "Claude Code", processes: ["claude"], appSupport: nil, places: [
            (".claude/cache", String(localized: "缓存"), .cache),
            (".claude/shell-snapshots", String(localized: "终端快照"), .cache),
            (".claude/telemetry", String(localized: "遥测日志"), .cache),
        ]),
        AITool(name: "Codex", processes: ["Codex", "codex"], appSupport: nil, places: [
            (".codex/cache", String(localized: "缓存"), .cache),
            (".codex/.tmp", String(localized: "临时文件"), .cache),
            (".codex/shell_snapshots", String(localized: "终端快照"), .cache),
            (".codex/plugins/cache", String(localized: "插件缓存"), .cache),
            (".cache/codex-runtimes", String(localized: "运行时"), .download),
        ]),
        AITool(name: "Cursor", processes: ["Cursor"], appSupport: "Cursor", places: []),
        AITool(name: "Windsurf", processes: ["Windsurf"], appSupport: "Windsurf", places: []),
        AITool(name: "Ollama", processes: ["Ollama", "ollama"], appSupport: nil, places: [
            (".ollama/models", String(localized: "模型文件"), .download),
        ]),
        AITool(name: "LM Studio", processes: ["LM Studio"], appSupport: nil, places: [
            (".lmstudio/models", String(localized: "模型文件"), .download),
            (".cache/lm-studio/models", String(localized: "模型文件"), .download),
        ]),
    ]

    /// Where AI tools keep past conversations, their checkpoints and the history people come back to. Nothing inside
    /// these, and nothing that holds one of them, is ever offered, even if a place above is later widened by mistake.
    static let conversationStores = [
        ".claude/projects", ".claude/history.jsonl", ".claude/todos", ".claude/file-history", ".claude/plans",
        ".codex/sessions", ".codex/archived_sessions", ".codex/history.jsonl",
        ".gemini/tmp", ".gemini/history",
        "Library/Application Support/Claude/claude-code-sessions",
        "Library/Application Support/Claude/local-agent-mode-sessions",
        "Library/Application Support/Claude/IndexedDB",
        "Library/Application Support/Claude/Local Storage",
        "Library/Application Support/Cursor/User",
        "Library/Application Support/Windsurf/User",
    ]

    /// Whether `url` is a conversation store, lies inside one, or contains one.
    static func touchesConversations(_ url: URL, home: URL) -> Bool {
        let path = Paths.components(url)
        return conversationStores.contains { store in
            let guarded = Paths.components(home.appendingPathComponent(store))
            return path.starts(with: guarded) || guarded.starts(with: path)
        }
    }

    /// Cache subfolders Electron and VS Code-based apps rebuild on their own.
    static let electronCaches = ["Cache", "Code Cache", "GPUCache", "DawnWebGPUCache", "DawnGraphiteCache", "GraphiteDawnCache",
                                 "DawnCache", "ShaderCache", "CachedData", "CachedExtensionVSIXs"]

    /// ~/.cache folders that belong to an AI tool, so the developer-cache scan leaves them to this one.
    private static let aiDotCaches: Set<String> = Set(aiTools.flatMap(\.places).compactMap { place in
        let parts = place.path.split(separator: "/")
        return parts.count > 1 && parts[0] == ".cache" ? String(parts[1]) : nil
    })

    static func scanAITools(_ home: URL, running: Set<String>) -> [CleanItem] {
        var entries: [(url: URL, id: String, name: String, detail: String, tier: AITier, components: [URL], processes: [String])] = []
        for tool in aiTools {
            if let folder = tool.appSupport {
                let base = home.appendingPathComponent("Library/Application Support/\(folder)")
                let caches = existing(electronCaches.map { base.appendingPathComponent($0) })
                if let first = caches.first {
                    entries.append((first, base.path + "#caches", String(localized: "\(tool.name) · 应用缓存"),
                                    String(localized: "\(Paths.display(base)) · \(caches.count) 个缓存文件夹"),
                                    .cache, caches, tool.processes))
                }
            }
            for place in tool.places {
                let url = home.appendingPathComponent(place.path)
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                entries.append((url, url.path, "\(tool.name) · \(place.label)", Paths.display(url), place.tier, [], tool.processes))
            }
        }
        entries.removeAll { entry in
            ([entry.url] + entry.components).contains { touchesConversations($0, home: home) }
        }

        let sizes = measure(entries.map { entry in entry.components.isEmpty ? [entry.url] : entry.components }.flatMap { $0 })
        var offset = 0
        return entries.map { entry in
            let urls = entry.components.isEmpty ? [entry.url] : entry.components
            let own = sizes[offset..<offset + urls.count]
            offset += urls.count
            let isRunning = ProcessWatch.isRunning(any: entry.processes, among: running)
            let badge: String? = isRunning ? String(localized: "运行中")
                : entry.tier == .download ? String(localized: "删后需重新下载") : nil
            return CleanItem(
                id: entry.id, url: entry.url, name: entry.name, detail: entry.detail, size: own.reduce(0, +),
                isSelected: entry.tier == .cache && !isRunning, badge: badge, ownerProcesses: entry.processes,
                components: zip(urls, own).map { .init(name: $0.lastPathComponent, url: $0, size: $1) }
            )
        }
    }

    // MARK: - Helpers

    private static func children(of dir: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
    }

    private static func existing(_ urls: [URL]) -> [URL] {
        urls.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func makeItems(_ urls: [URL], selected: Bool, name: (URL) -> String) -> [CleanItem] {
        zip(urls, measure(urls)).map { url, size in
            CleanItem(id: url.path, url: url, name: name(url), detail: Paths.display(url), size: size, isSelected: selected)
        }
    }

    /// Cache folders are usually named after a bundle ID; map them back to the app for a friendly name and icon.
    private static func application(forFolderNamed folder: String) -> (name: String, url: URL)? {
        guard folder.split(separator: ".").count >= 3 else { return nil }
        var candidate = folder
        var suffix: String?
        for _ in 0..<2 {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: candidate) {
                var name = FileManager.default.displayName(atPath: url.path)
                if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
                return (suffix.map { "\(name) · \($0)" } ?? name, url)
            }
            guard let dot = candidate.lastIndex(of: ".") else { break }
            suffix = String(candidate[candidate.index(after: dot)...])
            candidate = String(candidate[..<dot])
        }
        return nil
    }

    /// Sizes many folders in parallel.
    static func measure(_ urls: [URL]) -> [Int64] {
        var sizes = [Int64](repeating: 0, count: urls.count)
        sizes.withUnsafeMutableBufferPointer { buffer in
            let base = buffer.baseAddress
            DispatchQueue.concurrentPerform(iterations: urls.count) { i in
                base?[i] = allocatedSize(of: urls[i])
            }
        }
        return sizes
    }

    static func allocatedSize(of url: URL) -> Int64 {
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
            guard let v = try? file.resourceValues(forKeys: keys), v.isRegularFile == true else { continue }
            total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        return total
    }
}
