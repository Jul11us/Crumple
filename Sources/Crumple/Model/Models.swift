import SwiftUI
import AppKit

extension Color {
    static let brand = Theme.accent

    /// Resolve against the window's appearance, including an in-app override.
    static func adaptive(light: UInt32, dark: UInt32, opacity: Double = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((hex >> 16) & 0xFF) / 255,
                           green: Double((hex >> 8) & 0xFF) / 255,
                           blue: Double(hex & 0xFF) / 255, alpha: opacity)
        })
    }

    /// A colour from the current theme. It's looked up when drawn, so switching themes repaints everything.
    static func themed(_ key: KeyPath<Palette, UInt32>, opacity: Double = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let palette = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? Palette.dark : Palette.light
            let hex = palette[keyPath: key]
            return NSColor(srgbRed: Double((hex >> 16) & 0xFF) / 255,
                           green: Double((hex >> 8) & 0xFF) / 255,
                           blue: Double(hex & 0xFF) / 255, alpha: opacity)
        })
    }

    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// Every colour of one theme.
struct Palette {
    var base: UInt32, sidebar: UInt32, card: UInt32, raised: UInt32
    var primary: UInt32, secondary: UInt32, tertiary: UInt32
    var accent: UInt32, onAccent: UInt32, accentSurface: UInt32
    var warning: UInt32, danger: UInt32
    var basketRim: UInt32, basketSlat: UInt32, basketWall: UInt32, basketInside: UInt32

    /// Cool grey with a slate-blue button: quiet, a little like stationery from a museum shop.
    static let mist = Palette(
        base: 0xF1F1EE, sidebar: 0xE7E7E3, card: 0xF8F8F6, raised: 0xDCDCD8,
        primary: 0x2B2D30, secondary: 0x5F6267, tertiary: 0x7D8085,
        accent: 0x3E5568, onAccent: 0xF4F4F1, accentSurface: 0xE3E6E9,
        warning: 0x94661C, danger: 0xA5403A,
        basketRim: 0x2B2D30, basketSlat: 0x3B3E42, basketWall: 0x4B4F54, basketInside: 0x1C1D1F)

    /// Kraft paper with dark brown ink: warmer, more hand-made.
    static let kraft = Palette(
        base: 0xE9E3D9, sidebar: 0xDFD7CA, card: 0xF0EBE3, raised: 0xD3C9BA,
        primary: 0x33291F, secondary: 0x66594C, tertiary: 0x85776A,
        accent: 0x33291F, onAccent: 0xEFE9E0, accentSurface: 0xDDD3C4,
        warning: 0x8A5A18, danger: 0x9C3A2B,
        basketRim: 0x3A2F25, basketSlat: 0x4A3D31, basketWall: 0x5A4B3D, basketInside: 0x231C15)

    /// Close to the system's own dark mode, with almost no colour of its own.
    static let dark = Palette(
        base: 0x1C1C1E, sidebar: 0x161618, card: 0x242426, raised: 0x333336,
        primary: 0xF2F2F2, secondary: 0xAEAEB2, tertiary: 0x8E8E93,
        accent: 0xF2F2F2, onAccent: 0x1C1C1E, accentSurface: 0x2A2A2D,
        warning: 0xE0B060, danger: 0xF08A7E,
        basketRim: 0xD9D9DC, basketSlat: 0xBDBDC1, basketWall: 0xA3A3A8, basketInside: 0x0E0E0F)

    /// The light theme in use; dark always uses `dark`. Only written on the main thread.
    nonisolated(unsafe) static var light = mist
}

enum AppAppearance: String, CaseIterable, Identifiable {
    // "light" keeps its stored name so an earlier "浅色" choice opens as 雾灰.
    case system, mist = "light", kraft, dark

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: String(localized: "跟随系统")
        case .mist: String(localized: "雾灰")
        case .kraft: String(localized: "牛皮纸")
        case .dark: String(localized: "深色")
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .mist, .kraft: .light
        case .dark: .dark
        }
    }
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .mist, .kraft: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
    /// The palette used whenever this choice shows light: kraft only when chosen, otherwise mist.
    var lightPalette: Palette { self == .kraft ? .kraft : .mist }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, english = "en", simplifiedChinese = "zh-Hans"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: String(localized: "跟随系统")
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        }
    }
}

/// Where the app looks for junk. `CRUMPLE_DEMO_HOME` swaps the real home
/// folder for a sandbox full of fake files, so the animation can be tried safely.
enum Paths {
    static let demoHome: URL? = ProcessInfo.processInfo.environment["CRUMPLE_DEMO_HOME"]
        .map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL }
    static var isDemo: Bool { demoHome != nil }
    static let home: URL = demoHome ?? FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL

    /// Folders that hold applications. In demo mode only the sandbox's own Applications folder.
    static var applicationFolders: [URL] {
        let userApps = home.appendingPathComponent("Applications")
        return isDemo ? [userApps] : [URL(fileURLWithPath: "/Applications"), userApps]
    }

    /// Our own data (cleaning history).
    static var appSupport: URL {
        let base = isDemo
            ? home.appendingPathComponent("Library/Application Support")
            : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Crumple")
    }

    /// The user's Trash. In demo mode a folder inside the sandbox, so fake files never reach the real one.
    static var trash: URL { home.appendingPathComponent(".Trash") }

    /// Shortens a path under home to "~/…" for display.
    static func display(_ url: URL) -> String {
        let path = normalized(url)
        let homePath = normalized(home)
        return path.hasPrefix(homePath + "/") ? "~" + path.dropFirst(homePath.count) : url.path
    }

    /// Path components with `.` and `..` resolved, and the `/private` in front of /tmp, /var and /etc
    /// dropped. `standardizedFileURL` only drops it for files that exist, so without this the same
    /// place could read differently before and after a file is moved.
    static func components(_ url: URL) -> [String] {
        var parts = url.standardizedFileURL.pathComponents
        if parts.count > 2, parts[1] == "private", ["tmp", "var", "etc"].contains(parts[2]) {
            parts.remove(at: 1)
        }
        return parts
    }

    static func normalized(_ url: URL) -> String {
        NSString.path(withComponents: components(url))
    }
}

// MARK: - Navigation

enum Page: String, CaseIterable, Identifiable {
    case overview, status, smartClean, analysis, largeFiles, duplicates, optimize, uninstaller, history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: String(localized: "概览")
        case .status: String(localized: "状态")
        case .smartClean: String(localized: "智能清理")
        case .analysis: String(localized: "空间分析")
        case .largeFiles: String(localized: "大文件")
        case .duplicates: String(localized: "重复文件")
        case .optimize: String(localized: "优化")
        case .uninstaller: String(localized: "应用卸载")
        case .history: String(localized: "清理记录")
        }
    }

    /// A few useful groups, rather than a heading for every tool.
    var section: String? {
        switch self {
        case .smartClean: String(localized: "清理与空间")
        case .optimize: String(localized: "管理")
        default: nil
        }
    }

    var symbol: String {
        switch self {
        case .overview: "rectangle.grid.1x2"
        case .status: "waveform.path.ecg"
        case .smartClean: "arrow.up.trash"
        case .analysis: "chart.bar.xaxis"
        case .largeFiles: "doc"
        case .duplicates: "doc.on.doc"
        case .optimize: "slider.horizontal.3"
        case .uninstaller: "square.grid.2x2"
        case .history: "clock.arrow.circlepath"
        }
    }

    var accent: Color { Theme.accent }
}

enum SmartPhase { case landing, scanning, results, review, cleaning, done }
enum ListPhase { case landing, scanning, results }

// MARK: - Categories

enum CategoryKind: String, CaseIterable, Identifiable {
    case appCaches, logs, xcode, devCaches, installers, oldDownloads, largeFiles, duplicates, applications

    /// The categories that make up a smart clean.
    static let junk: [CategoryKind] = [.appCaches, .logs, .xcode, .devCaches, .installers, .oldDownloads]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appCaches: String(localized: "应用缓存")
        case .logs: String(localized: "日志文件")
        case .xcode: String(localized: "Xcode 垃圾")
        case .devCaches: String(localized: "开发工具缓存")
        case .installers: String(localized: "安装包")
        case .oldDownloads: String(localized: "旧下载文件")
        case .largeFiles: String(localized: "大文件")
        case .duplicates: String(localized: "重复文件")
        case .applications: String(localized: "应用")
        }
    }

    var summary: String {
        switch self {
        case .appCaches: String(localized: "应用为了加快加载而保存的临时数据，删除后会自动重新生成。正在运行的应用的缓存投不进纸篓，先退出它再清理。")
        case .logs: String(localized: "应用和系统组件写下的运行日志与崩溃报告。")
        case .xcode: String(localized: "编译产物（DerivedData）、旧设备支持文件和模拟器缓存。归档默认不勾选。")
        case .devCaches: String(localized: "npm、Gradle、Cargo、pip 等包管理器下载的缓存，需要时会重新下载。")
        case .installers: String(localized: "下载文件夹里的 .dmg / .pkg 安装包，装完通常就不需要了。默认不勾选。")
        case .oldDownloads: String(localized: "下载文件夹中很久没碰过的文件。这是你自己的文件，请确认后再勾选。")
        case .largeFiles: String(localized: "个人文件夹里体积很大的文件。")
        case .duplicates: String(localized: "内容一模一样的文件，每组只留一份。")
        case .applications: String(localized: "已安装的应用和它们留下的文件。")
        }
    }

    var symbol: String {
        switch self {
        case .appCaches: "square.stack.3d.up"
        case .logs: "doc.text"
        case .xcode: "hammer"
        case .devCaches: "shippingbox"
        case .installers: "arrow.down.app"
        case .oldDownloads: "clock"
        case .largeFiles: "doc"
        case .duplicates: "doc.on.doc"
        case .applications: "square.grid.2x2"
        }
    }

    var color: Color { Theme.accent }

    /// Color carries category information only inside the share chart.
    var chartColor: Color {
        switch self {
        case .appCaches: Theme.accent
        // Shades of the same ink, from dark to pale, so the chart reads like a printed graph.
        case .logs: Theme.primary.opacity(0.72)
        case .xcode: Theme.primary.opacity(0.52)
        case .devCaches: Theme.primary.opacity(0.36)
        case .installers: Theme.primary.opacity(0.24)
        case .oldDownloads: Theme.primary.opacity(0.14)
        default: Theme.chart
        }
    }
}

enum CleanMode: String, CaseIterable, Identifiable, Codable {
    case trash, delete

    var id: String { rawValue }
    var title: String { self == .trash ? String(localized: "移到废纸篓") : String(localized: "直接删除") }
}

/// What kind of large file this is, for the filter chips.
enum FileTag: String, CaseIterable, Identifiable {
    case video, archive, diskImage, document, audio, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .video: String(localized: "视频")
        case .archive: String(localized: "压缩包")
        case .diskImage: String(localized: "磁盘镜像")
        case .document: String(localized: "文档")
        case .audio: String(localized: "音频")
        case .other: String(localized: "其他")
        }
    }

    var symbol: String {
        switch self {
        case .video: "film.fill"
        case .archive: "doc.zipper"
        case .diskImage: "externaldrive.fill"
        case .document: "doc.richtext.fill"
        case .audio: "waveform"
        case .other: "doc.fill"
        }
    }

    static func of(_ url: URL) -> FileTag {
        switch url.pathExtension.lowercased() {
        case "mp4", "mov", "m4v", "mkv", "avi", "webm", "flv", "wmv": .video
        case "zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz": .archive
        case "dmg", "iso", "img", "pkg", "xip", "vmdk", "qcow2": .diskImage
        case "pdf", "psd", "ai", "key", "pages", "numbers", "docx", "pptx", "xlsx", "sketch", "fig": .document
        case "mp3", "wav", "aiff", "aif", "flac", "m4a", "caf": .audio
        default: .other
        }
    }
}

enum AppFilter: String, CaseIterable, Identifiable {
    case all, unused, large, appStore

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: String(localized: "全部")
        case .unused: String(localized: "很久没用")
        case .large: String(localized: "超过 500 MB")
        case .appStore: "App Store"
        }
    }
}

enum FileSort: String, CaseIterable, Identifiable {
    case size, oldest

    var id: String { rawValue }
    var title: String { self == .size ? String(localized: "按大小") : String(localized: "按最久没用") }
}

struct CleanItem: Identifiable, Hashable {
    /// `tossed`: the user picked it up and it is in the air, so its row is hidden.
    enum Status: Hashable { case ready, cleaned, failed, tossed }

    /// A file that goes with this item, e.g. an app's leftover caches and preferences.
    struct Component: Hashable {
        let name: String
        let url: URL
        let size: Int64
    }

    let id: String
    let url: URL
    var name: String
    var detail: String
    var size: Int64
    var isSelected: Bool
    var badge: String? = nil
    var appURL: URL? = nil
    /// Bundle ID of the app this belongs to; while that app runs, the item won't go in the basket.
    var ownerBundleID: String? = nil
    var tag: FileTag? = nil
    var lastUsed: Date? = nil
    var version: String? = nil
    var isAppStore = false
    var components: [Component] = []
    /// For a duplicate: the identical copy that stays. The item is only cleaned while that copy is still there.
    var keeper: URL? = nil
    var status: Status = .ready
}

enum CleanSource: String, Codable, CaseIterable {
    case smartClean, largeFiles, duplicates, uninstaller, manual

    var title: String {
        switch self {
        case .smartClean: String(localized: "智能清理")
        case .largeFiles: String(localized: "大文件")
        case .duplicates: String(localized: "重复文件")
        case .uninstaller: String(localized: "应用卸载")
        case .manual: String(localized: "亲手投")
        }
    }

    var symbol: String {
        switch self {
        case .smartClean: Page.smartClean.symbol
        case .largeFiles: Page.largeFiles.symbol
        case .duplicates: Page.duplicates.symbol
        case .uninstaller: Page.uninstaller.symbol
        case .manual: "hand.draw.fill"
        }
    }

    var color: Color {
        switch self {
        case .smartClean: Page.smartClean.accent
        case .largeFiles: Page.largeFiles.accent
        case .duplicates: Page.duplicates.accent
        case .uninstaller: Page.uninstaller.accent
        case .manual: Page.history.accent
        }
    }
}

struct CleanSummary {
    struct Failure: Hashable {
        let name: String
        let reason: String
    }

    /// What one category contributed, for the receipt on the done page.
    struct Line: Hashable {
        let kind: CategoryKind
        var count: Int
        var bytes: Int64
    }

    var source: CleanSource
    var mode: CleanMode
    var count = 0
    var bytes: Int64 = 0
    var lines: [Line] = []
    var failures: [Failure] = []
    var startedAt = Date()
    var finishedAt = Date()
    var trashEmptied = false
    /// Where each file went in the Trash, so the clean can be undone.
    var trashed: [TrashedFile] = []
    /// The history entry this clean was saved as.
    var historyID: UUID?

    var failed: Int { failures.count }
    var duration: TimeInterval { finishedAt.timeIntervalSince(startedAt) }
}

/// A file moved to the Trash: where it was, and where it is now.
struct TrashedFile: Codable, Hashable, Sendable {
    let original: String
    let trashed: String
}

struct HistoryEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var source: CleanSource
    var mode: CleanMode
    var count: Int
    var bytes: Int64
    var failed: Int
    // Optional so history saved by older versions still loads.
    var trashed: [TrashedFile]? = nil
    var restored: Bool? = nil

    var isRestored: Bool { restored == true }
}

enum CheckState { case on, off, mixed }

struct DiskInfo {
    let name: String
    let total: Int64
    let available: Int64

    var used: Int64 { total - available }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    static func current() -> DiskInfo? {
        let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity else { return nil }
        return DiskInfo(
            name: values.volumeName ?? "Macintosh HD",
            total: Int64(total),
            available: values.volumeAvailableCapacityForImportantUsage ?? 0
        )
    }
}

struct SystemInfo {
    let computerName: String
    let chip: String
    let memory: Int64
    let osVersion: String

    static let current: SystemInfo = {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return SystemInfo(
            computerName: Host.current().localizedName ?? String(localized: "这台 Mac"),
            chip: String(cString: buffer),
            memory: Int64(ProcessInfo.processInfo.physicalMemory),
            osVersion: "macOS \(version.majorVersion).\(version.minorVersion)" + (version.patchVersion > 0 ? ".\(version.patchVersion)" : "")
        )
    }()
}

private let byteFormatter: ByteCountFormatter = {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
    return formatter
}()

extension Int64 {
    var byteString: String { self <= 0 ? "0 KB" : byteFormatter.string(fromByteCount: self) }
}

extension Date {
    /// "今天", "3 天前", "2 个月前"…
    var agoText: String {
        let days = Int(Date().timeIntervalSince(self) / 86_400)
        switch days {
        case ..<1: return String(localized: "今天")
        case 1: return String(localized: "昨天")
        case ..<31: return String(localized: "\(days) 天前")
        case ..<365: return String(localized: "\(days / 30) 个月前")
        default: return String(localized: "\(days / 365) 年前")
        }
    }
}
