import Foundation

/// A one-click maintenance job on the 优化 page.
struct MaintenanceTask: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    /// Asks for the administrator password (macOS shows its own dialog).
    let needsAdmin: Bool
    let command: String

    static let all: [MaintenanceTask] = [
        MaintenanceTask(id: "quicklook", title: String(localized: "重置快速查看缓存"), detail: String(localized: "预览图不对、按空格预览很慢时有用。"),
                        symbol: "eye.fill", needsAdmin: false, command: "qlmanage -r cache && qlmanage -r"),
        MaintenanceTask(id: "launchservices", title: String(localized: "重建“打开方式”菜单"), detail: String(localized: "清掉“打开方式”里重复和失效的应用。"),
                        symbol: "contextualmenu.and.cursorarrow", needsAdmin: false,
                        command: "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -r -domain local -domain system -domain user"),
        MaintenanceTask(id: "dock", title: String(localized: "重启程序坞和访达"), detail: String(localized: "程序坞卡住、桌面图标不刷新时试试。"),
                        symbol: "dock.rectangle", needsAdmin: false, command: "killall Dock; killall Finder"),
        MaintenanceTask(id: "dns", title: String(localized: "刷新 DNS 缓存"), detail: String(localized: "换了网络后网站打不开、解析不对时有用。"),
                        symbol: "network", needsAdmin: true, command: "dscacheutil -flushcache; killall -HUP mDNSResponder"),
        MaintenanceTask(id: "purge", title: String(localized: "释放不活跃内存"), detail: String(localized: "把系统缓着的内存还回来，内存紧张时有用。"),
                        symbol: "memorychip", needsAdmin: true, command: "purge"),
        MaintenanceTask(id: "spotlight", title: String(localized: "重建聚焦索引"), detail: String(localized: "搜索找不到文件时用，重建要花一些时间。"),
                        symbol: "magnifyingglass", needsAdmin: true, command: "mdutil -E /"),
    ]

    /// Runs the command; tasks that need an administrator go through macOS's password dialog.
    func run() -> Bool {
        let process = Process()
        if needsAdmin {
            let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", "do shell script \"\(escaped)\" with administrator privileges"]
        } else {
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", command]
        }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

/// A launchd job that starts at login: something running in the background without a window.
struct LaunchAgent: Identifiable, Hashable {
    let url: URL
    let label: String
    let program: String?
    let isEnabled: Bool
    /// Only the user's own agents can be switched; system-wide ones need an administrator.
    let isUserLevel: Bool

    var id: URL { url }

    private static var userFolder: URL { Paths.home.appendingPathComponent("Library/LaunchAgents") }
    /// Switched-off agents are parked here, so switching them back on is just a move back.
    private static var parkingFolder: URL { userFolder.appendingPathComponent("Disabled by Crumple") }

    static func list() -> [LaunchAgent] {
        func read(_ folder: URL, enabled: Bool, user: Bool) -> [LaunchAgent] {
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            return files.filter { $0.pathExtension == "plist" }.map { url in
                let plist = NSDictionary(contentsOf: url)
                let arguments = plist?["ProgramArguments"] as? [String]
                return LaunchAgent(url: url, label: plist?["Label"] as? String ?? url.deletingPathExtension().lastPathComponent,
                                   program: plist?["Program"] as? String ?? arguments?.first, isEnabled: enabled, isUserLevel: user)
            }
        }
        var agents = read(userFolder, enabled: true, user: true) + read(parkingFolder, enabled: false, user: true)
        if !Paths.isDemo {
            agents += read(URL(fileURLWithPath: "/Library/LaunchAgents"), enabled: true, user: false)
            agents += read(URL(fileURLWithPath: "/Library/LaunchDaemons"), enabled: true, user: false)
        }
        return agents.sorted { ($0.isUserLevel ? 0 : 1, $0.label) < ($1.isUserLevel ? 0 : 1, $1.label) }
    }

    /// Stops the agent and parks its plist (or brings it back). Returns false if the move failed.
    func setEnabled(_ enabled: Bool) -> Bool {
        guard isUserLevel, enabled != isEnabled else { return false }
        let target = (enabled ? Self.userFolder : Self.parkingFolder).appendingPathComponent(url.lastPathComponent)
        if !enabled { launchctl("bootout", url) }
        do {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: url, to: target)
        } catch {
            return false
        }
        if enabled { launchctl("bootstrap", target) }
        return true
    }

    private func launchctl(_ verb: String, _ plist: URL) {
        guard !Paths.isDemo else { return } // demo agents are fake
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = [verb, "gui/\(getuid())", plist.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}
