import Foundation

/// Fills a sandbox folder with fake junk so the cleaning animation can be tried
/// without touching real files. Used when `CRUMPLE_DEMO_HOME` is set.
enum DemoData {
    static func populate(at home: URL) {
        let fm = FileManager.default
        let marker = home.appendingPathComponent(".demo-ready")
        guard !fm.fileExists(atPath: marker.path) else { return }

        let folders: [(path: String, kilobytes: Int)] = [
            ("Library/Caches/com.google.Chrome", 9_000),
            ("Library/Caches/com.apple.Safari", 3_200),
            ("Library/Caches/com.spotify.client", 6_200),
            ("Library/Caches/com.tinyspeck.slackmacgap", 2_100),
            ("Library/Caches/com.microsoft.VSCode", 1_600),
            ("Library/Caches/com.figma.Desktop", 1_300),
            ("Library/Caches/Homebrew", 4_900),
            ("Library/Caches/pip", 950),
            ("Library/Caches/com.anthropic.claudefordesktop", 600),
            ("Library/Caches/com.apple.locked-demo", 400),
            ("Library/Logs/DiagnosticReports", 450),
            ("Library/Logs/Zoom", 700),
            ("Library/Logs/Adobe", 300),
            ("Library/Developer/Xcode/DerivedData/Weather-bxkqzvhtwoepfnrdlgyiaxcumsjh", 11_000),
            ("Library/Developer/Xcode/DerivedData/TodoApp-ahdkwqpzmvneucjrbxlotyifsgk", 4_000),
            ("Library/Developer/Xcode/iOS DeviceSupport/iPhone16,1 18.2 (22C152)", 7_500),
            ("Library/Developer/CoreSimulator/Caches", 1_000),
            (".npm/_cacache", 2_700),
            (".gradle/caches", 1_600),
            (".cache/pip", 350),
            // AI tools: a desktop app's web caches, a VM image that is only listed, a CLI's cache and runtime,
            // and conversation folders, one for a project that is still there and one for a project that is gone.
            ("Library/Application Support/Claude/Cache", 1_800),
            ("Library/Application Support/Claude/Code Cache", 600),
            ("Library/Application Support/Claude/GPUCache", 90),
            ("Library/Application Support/Claude/vm_bundles/claudevm.bundle", 14_000),
            (".claude/cache", 120),
            (".claude/projects/\(Scanner.projectSlug(for: home.appendingPathComponent("Documents")))", 700),
            (".claude/projects/\(Scanner.projectSlug(for: home.appendingPathComponent("Desktop/OldProject")))", 900),
            (".codex/cache", 300),
            (".codex/sessions", 450),
            (".cache/codex-runtimes", 2_200),
        ]
        for folder in folders {
            let dir = home.appendingPathComponent(folder.path)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let parts = [folder.kilobytes / 2, folder.kilobytes / 3, folder.kilobytes - folder.kilobytes / 2 - folder.kilobytes / 3]
            for (i, kb) in parts.enumerated() {
                fm.createFile(atPath: dir.appendingPathComponent("blob-\(i).bin").path, contents: Data(count: kb * 1024))
            }
        }

        let downloads = home.appendingPathComponent("Downloads")
        try? fm.createDirectory(at: downloads, withIntermediateDirectories: true)
        for (name, kb) in [("Figma-Installer.dmg", 2_400), ("Zoom.pkg", 1_900), ("2023-年度报告.pdf", 550)] {
            fm.createFile(atPath: downloads.appendingPathComponent(name).path, contents: Data(count: kb * 1024))
        }
        var oldFile = downloads.appendingPathComponent("2023-年度报告.pdf")
        var values = URLResourceValues()
        values.contentModificationDate = Date().addingTimeInterval(-200 * 86_400)
        values.contentAccessDate = values.contentModificationDate
        try? oldFile.setResourceValues(values)

        // A folder that can't be deleted, to show a paper ball bouncing off the rim.
        try? fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: home.appendingPathComponent("Library/Caches/com.apple.locked-demo").path)

        // Big personal files for the 大文件 page (the demo uses a 1 MB threshold).
        for (path, kb) in [
            ("Movies/2024 旅行 4K.mov", 6_400), ("Movies/录屏 2023-11-02.mp4", 3_100),
            ("Desktop/项目备份.zip", 4_200), ("Documents/设计稿 v12.psd", 2_700),
            ("Downloads/ubuntu-24.04-desktop.iso", 5_200), ("Music/现场录音.wav", 1_800),
            ("Documents/年度报告 终稿.pdf", 1_300),
        ] {
            let url = home.appendingPathComponent(path)
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            fm.createFile(atPath: url.path, contents: Data(count: kb * 1024))
        }
        var oldMovie = home.appendingPathComponent("Movies/录屏 2023-11-02.mp4")
        try? oldMovie.setResourceValues(values)

        // Identical files under different names for the 重复文件 page. Each set has its own content.
        var random = SeededRandom(2024)
        let copies: [(kb: Int, paths: [String])] = [
            (2_300, ["Pictures/IMG_2041.jpg", "Downloads/IMG_2041 (1).jpg", "Desktop/IMG_2041 副本.jpg"]),
            (3_600, ["Movies/婚礼剪辑.mp4", "Desktop/婚礼剪辑 最终.mp4"]),
            (900, ["Documents/租房合同.pdf", "Downloads/租房合同.pdf"]),
            (1_400, ["Music/demo-混音.m4a", "Downloads/demo-混音 copy.m4a"]),
            (600, ["Pictures/截图 2024-05-12.png", "Desktop/截图 2024-05-12.png"]),
        ]
        for set in copies {
            var bytes = [UInt8](repeating: 0, count: set.kb * 1024)
            for i in stride(from: 0, to: bytes.count, by: 8) {
                withUnsafeBytes(of: random.next()) { word in
                    for j in 0..<min(8, bytes.count - i) { bytes[i + j] = word[j] }
                }
            }
            for path in set.paths {
                let url = home.appendingPathComponent(path)
                try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                fm.createFile(atPath: url.path, contents: Data(bytes))
            }
        }
        // A near miss: same size, one byte different, so it must not be listed.
        var almost = [UInt8](repeating: 7, count: 700 * 1024)
        fm.createFile(atPath: home.appendingPathComponent("Documents/草稿 A.key").path, contents: Data(almost))
        almost[100 * 1024] = 8 // outside the sampled parts, so only the full comparison tells them apart
        fm.createFile(atPath: home.appendingPathComponent("Documents/草稿 B.key").path, contents: Data(almost))

        // Fake apps with leftovers for the 应用卸载 page. "Claude" reuses a real bundle ID,
        // so while Claude is running it shows how a running app refuses to go in.
        let apps: [(name: String, id: String, version: String, kb: Int, leftovers: [(String, Int)])] = [
            ("PixelPaint", "com.example.PixelPaint", "3.2.1", 5_600, [("Application Support/com.example.PixelPaint", 2_200), ("Preferences/com.example.PixelPaint.plist", 4)]),
            ("Notely", "com.example.Notely", "1.8", 2_100, [("Caches/com.example.Notely", 900), ("Saved Application State/com.example.Notely.savedState", 12)]),
            ("Retro Racer", "com.example.RetroRacer", "2.0", 7_300, [("Application Support/Retro Racer", 3_100)]),
            ("Claude", "com.anthropic.claudefordesktop", "1.0", 1_500, []),
        ]
        for app in apps {
            let bundle = home.appendingPathComponent("Applications/\(app.name).app/Contents")
            try? fm.createDirectory(at: bundle.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
            let info: [String: Any] = [
                "CFBundleIdentifier": app.id, "CFBundleName": app.name,
                "CFBundleShortVersionString": app.version, "CFBundleExecutable": app.name, "CFBundlePackageType": "APPL",
            ]
            (info as NSDictionary).write(to: bundle.appendingPathComponent("Info.plist"), atomically: true)
            fm.createFile(atPath: bundle.appendingPathComponent("MacOS/\(app.name)").path, contents: Data(count: app.kb * 1024))
            for (path, kb) in app.leftovers {
                let url = home.appendingPathComponent("Library/\(path)")
                if url.pathExtension == "plist" {
                    try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    fm.createFile(atPath: url.path, contents: Data(count: kb * 1024))
                } else {
                    try? fm.createDirectory(at: url, withIntermediateDirectories: true)
                    fm.createFile(atPath: url.appendingPathComponent("data.bin").path, contents: Data(count: kb * 1024))
                }
            }
        }

        // Background launch items for the 优化 page (never loaded into launchd in demo mode).
        let agents = home.appendingPathComponent("Library/LaunchAgents")
        try? fm.createDirectory(at: agents, withIntermediateDirectories: true)
        for (label, program) in [("com.example.PixelPaint.updater", "/Applications/PixelPaint.app/Contents/MacOS/Updater"),
                                 ("com.example.Notely.sync", "/Applications/Notely.app/Contents/Helpers/SyncAgent")] {
            let plist: NSDictionary = ["Label": label, "ProgramArguments": [program], "RunAtLoad": true]
            plist.write(to: agents.appendingPathComponent("\(label).plist"), atomically: true)
        }

        // A little history so the 清理记录 page has something to show.
        let now = Date()
        HistoryStore.save([
            HistoryEntry(date: now.addingTimeInterval(-6 * 86_400), source: .smartClean, mode: .trash, count: 42, bytes: 1_850_000_000, failed: 1),
            HistoryEntry(date: now.addingTimeInterval(-4 * 86_400), source: .largeFiles, mode: .trash, count: 3, bytes: 6_200_000_000, failed: 0),
            HistoryEntry(date: now.addingTimeInterval(-2 * 86_400), source: .uninstaller, mode: .trash, count: 1, bytes: 980_000_000, failed: 0),
            HistoryEntry(date: now.addingTimeInterval(-2 * 86_400 + 3600), source: .manual, mode: .trash, count: 1, bytes: 120_000_000, failed: 0),
            HistoryEntry(date: now.addingTimeInterval(-1 * 86_400), source: .smartClean, mode: .trash, count: 18, bytes: 640_000_000, failed: 2),
        ])

        fm.createFile(atPath: marker.path, contents: nil)
    }
}
