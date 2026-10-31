// Run against the assembled app so these checks exercise shipped resources, including plurals.
// bash Localization/verify.sh [build/Crumple.app]
import Foundation

guard CommandLine.arguments.count >= 3,
      let bundle = Bundle(path: CommandLine.arguments[1]) else {
    fatalError("Usage: swift Localization/verify.swift <app-bundle> <en|zh-Hans> -AppleLanguages '(<language>)'")
}
let english = CommandLine.arguments[2] == "en"
var checks = 0
print("Checking \(bundle.preferredLocalizations), locale \(Locale.current.identifier), preferred \(Locale.preferredLanguages)")

func expect(_ actual: String, _ expected: String) {
    guard actual == expected else {
        print("Expected \(expected.debugDescription), got \(actual.debugDescription)")
        exit(1)
    }
    checks += 1
}

expect(String(localized: "智能清理", bundle: bundle), english ? "Smart Clean" : "智能清理")
expect(String(localized: "跟随系统", bundle: bundle), english ? "System" : "跟随系统")
expect(String(localized: "重新打开 Crumple 后生效", bundle: bundle),
       english ? "Takes effect after Crumple reopens" : "重新打开 Crumple 后生效")
for count in [0, 1, 2, 11, 100] {
    expect(String(localized: "共 \(count) 项", bundle: bundle),
           english ? "\(count) \(count == 1 ? "item" : "items")" : "共 \(count) 项")
    expect(String(localized: "\(count) 个纸团", bundle: bundle),
           english ? "\(count) paper \(count == 1 ? "ball" : "balls")" : "\(count) 个纸团")
    let name = "Sample.app", bytes = "10 MB"
    expect(String(localized: "\(name) 以及 \(count) 个残留文件（共 \(bytes)）会被移到废纸篓。", bundle: bundle),
           english ? "\(name) and \(count) leftover \(count == 1 ? "file" : "files") (\(bytes) in total) will be moved to the Trash."
                   : "\(name) 以及 \(count) 个残留文件（共 \(bytes)）会被移到废纸篓。")
    expect(String(localized: "还在算 \(count) 项…", bundle: bundle),
           english ? "Still measuring \(count) \(count == 1 ? "item" : "items")…" : "还在算 \(count) 项…")
    expect(String(localized: "\(count) 天前", bundle: bundle),
           english ? "\(count) \(count == 1 ? "day" : "days") ago" : "\(count) 天前")
}
let percent = 88
expect(String(localized: "健康 \(percent)%", bundle: bundle), english ? "Health 88%" : "健康 88%")
let back = 1, missing = 2
expect(String(localized: "放回了 \(back) 个，\(missing) 个已不在废纸篓里", bundle: bundle),
       english ? "Put back 1 file; 2 missing from the Trash" : "放回了 1 个，2 个已不在废纸篓里")
precondition(bundle.localizedInfoDictionary?["NSDownloadsFolderUsageDescription"] as? String ==
             (english ? "Crumple looks for installers, old downloads and large files in Downloads."
                      : "Crumple 会扫描下载文件夹，找出安装包、旧下载、大文件和重复文件。"))
checks += 1
print("\(checks) shipped-resource checks passed (\(bundle.preferredLocalizations.joined(separator: ", ")))")
