import Foundation
import Testing
@testable import Crumple

/// Tests run in parallel, so each removes only its own folder, and the shared parent once it is empty.
func removeSandbox(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
    rmdir(url.deletingLastPathComponent().path)
}

/// The one rule that keeps Crumple from deleting the wrong thing: it only touches items at least
/// two levels inside the home folder, or apps sitting directly in an Applications folder.
@Suite("删除保护")
struct CleanerSafetyTests {
    let home = Paths.home

    @Test("不碰家目录本身和第一层文件夹")
    func refusesHomeAndTopLevel() {
        for path in ["", "Library", "Documents", "Desktop", "Downloads", ".ssh"] {
            #expect(!Cleaner.isSafeTarget(home.appendingPathComponent(path)), "\(path)")
        }
    }

    @Test("不碰家目录以外的地方")
    func refusesOutsideHome() {
        for path in ["/", "/System", "/System/Library/Caches", "/Library/Caches/com.apple.x", "/Users", "/private/var/tmp/x", "/Applications"] {
            #expect(!Cleaner.isSafeTarget(URL(fileURLWithPath: path)), "\(path)")
        }
    }

    @Test("家目录里两层以下可以清理")
    func allowsDeepItems() {
        for path in ["Library/Caches/com.example.app", "Library/Logs/Example", "Downloads/Installer.dmg", ".npm/_cacache"] {
            #expect(Cleaner.isSafeTarget(home.appendingPathComponent(path)), "\(path)")
        }
    }

    @Test("文件在不在，路径都按同一个样子比较")
    func pathsCompareTheSameWhetherOrNotTheyExist() {
        let missing = "/private/tmp/crumple-\(UUID().uuidString)/a"
        #expect(Cleaner.components(URL(fileURLWithPath: missing)) == Cleaner.components(URL(fileURLWithPath: String(missing.dropFirst(8)))))
        #expect(Cleaner.components(URL(fileURLWithPath: "/private/tmp")) == ["/", "tmp"])
        #expect(Cleaner.components(URL(fileURLWithPath: "/private/x")) == ["/", "private", "x"])
    }

    @Test("用 .. 绕不出去")
    func dotDotCannotEscape() {
        #expect(!Cleaner.isSafeTarget(home.appendingPathComponent("Library/Caches/../..")))
        #expect(!Cleaner.isSafeTarget(home.appendingPathComponent("Library/Caches/../../..")))
        #expect(!Cleaner.isSafeTarget(home.appendingPathComponent("Library/../Documents")))
    }

    @Test("应用只能是“应用程序”文件夹里直接放着的 .app")
    func appsOnlyDirectlyInApplications() {
        #expect(Cleaner.isSafeTarget(URL(fileURLWithPath: "/Applications/Example.app")))
        #expect(!Cleaner.isSafeTarget(URL(fileURLWithPath: "/Applications/Utilities/Example.app")))
        #expect(!Cleaner.isSafeTarget(URL(fileURLWithPath: "/Applications/Example.app/Contents")))
        #expect(!Cleaner.isSafeTarget(URL(fileURLWithPath: "/System/Applications/Safari.app")))
        #expect(!Cleaner.isSafeTarget(URL(fileURLWithPath: "/Applications/Example")))
    }

    @Test("不安全的路径连碰都不碰")
    func cleanLeavesUnsafeItemsAlone() throws {
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("crumple-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        #expect(!Cleaner.clean(outside, mode: .delete))
        #expect(FileManager.default.fileExists(atPath: outside.path))
    }

    @Test("删掉指向外面的符号链接时，只删链接本身")
    func symlinkIsRemovedNotItsTarget() throws {
        let fm = FileManager.default
        let target = fm.temporaryDirectory.appendingPathComponent("crumple-target-\(UUID().uuidString)")
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("keep me".utf8).write(to: target.appendingPathComponent("keep.txt"))
        defer { try? fm.removeItem(at: target) }

        let sandbox = home.appendingPathComponent("Library/Caches/\(Scanner.ownBundleID).tests/\(UUID().uuidString)")
        try fm.createDirectory(at: sandbox, withIntermediateDirectories: true)
        defer { removeSandbox(sandbox) }
        let link = sandbox.appendingPathComponent("link")
        try fm.createSymbolicLink(at: link, withDestinationURL: target)

        #expect(Cleaner.clean(link, mode: .delete))
        #expect(!fm.fileExists(atPath: link.path))
        #expect(fm.fileExists(atPath: target.appendingPathComponent("keep.txt").path))
    }

    @Test("应用的残留文件也要过同一道检查")
    func componentsAreCheckedToo() throws {
        let fm = FileManager.default
        let sandbox = home.appendingPathComponent("Library/Caches/\(Scanner.ownBundleID).tests/\(UUID().uuidString)")
        let main = sandbox.appendingPathComponent("main")
        try fm.createDirectory(at: main, withIntermediateDirectories: true)
        defer { removeSandbox(sandbox) }
        let outside = fm.temporaryDirectory.appendingPathComponent("crumple-outside-\(UUID().uuidString)")
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: outside) }

        let item = CleanItem(id: main.path, url: main, name: "main", detail: "", size: 0, isSelected: true,
                             components: [.init(name: "outside", url: outside, size: 0)])
        #expect(Cleaner.clean(item, mode: .delete).removed)
        #expect(!fm.fileExists(atPath: main.path))
        #expect(fm.fileExists(atPath: outside.path))
    }
}

/// Undo puts files back from the Trash. These use a pretend Trash folder so the real one is never touched.
@Suite("撤销和忽略")
struct RestoreTests {
    let fm = FileManager.default

    func sandbox() throws -> URL {
        let url = Paths.home.appendingPathComponent("Library/Caches/\(Scanner.ownBundleID).tests/\(UUID().uuidString)")
        try fm.createDirectory(at: url.appendingPathComponent(".Trash"), withIntermediateDirectories: true)
        return url
    }

    @Test("从废纸篓放回原处，缺的文件夹会补上")
    func restoresToOriginalPlace() throws {
        let box = try sandbox()
        defer { removeSandbox(box) }
        let trashed = box.appendingPathComponent(".Trash/report.pdf")
        try Data("hello".utf8).write(to: trashed)
        let original = box.appendingPathComponent("Documents/2024/report.pdf")

        #expect(Cleaner.restore(TrashedFile(original: original.path, trashed: trashed.path)))
        #expect(fm.fileExists(atPath: original.path))
        #expect(!fm.fileExists(atPath: trashed.path))
    }

    @Test("原处已经有同名文件时不覆盖")
    func neverOverwrites() throws {
        let box = try sandbox()
        defer { removeSandbox(box) }
        let trashed = box.appendingPathComponent(".Trash/a.txt")
        let original = box.appendingPathComponent("a.txt")
        try Data("old".utf8).write(to: trashed)
        try Data("new".utf8).write(to: original)

        #expect(!Cleaner.restore(TrashedFile(original: original.path, trashed: trashed.path)))
        #expect(try String(contentsOf: original, encoding: .utf8) == "new")
    }

    @Test("只从废纸篓里往回搬，也只搬回安全的位置")
    func onlyFromTrashToSafePlaces() throws {
        let box = try sandbox()
        defer { removeSandbox(box) }
        let loose = box.appendingPathComponent("loose.txt")
        try Data("x".utf8).write(to: loose)
        #expect(!Cleaner.restore(TrashedFile(original: box.appendingPathComponent("moved.txt").path, trashed: loose.path)))
        #expect(fm.fileExists(atPath: loose.path))

        let trashed = box.appendingPathComponent(".Trash/b.txt")
        try Data("x".utf8).write(to: trashed)
        #expect(!Cleaner.restore(TrashedFile(original: Paths.home.appendingPathComponent("b.txt").path, trashed: trashed.path)))
        #expect(!Cleaner.restore(TrashedFile(original: "/private/tmp/b.txt", trashed: trashed.path)))
        #expect(fm.fileExists(atPath: trashed.path))
    }

    @Test("忽略一个文件夹，也忽略里面的一切，但不连带名字相近的")
    func ignoreListMatchesFolders() {
        let ignored = ["/Users/x/Movies/Projects"]
        #expect(IgnoreList.contains(URL(fileURLWithPath: "/Users/x/Movies/Projects"), in: ignored))
        #expect(IgnoreList.contains(URL(fileURLWithPath: "/Users/x/Movies/Projects/a/b.mov"), in: ignored))
        #expect(!IgnoreList.contains(URL(fileURLWithPath: "/Users/x/Movies/Projects 2/b.mov"), in: ignored))
        #expect(!IgnoreList.contains(URL(fileURLWithPath: "/Users/x/Movies"), in: ignored))
        #expect(IgnoreList.contains(URL(fileURLWithPath: "/private/tmp/cache/a"), in: ["/tmp/cache"]))
    }

    @Test("重复文件要逐字节相同：抽样一样但内容不同的不算")
    func duplicatesNeedIdenticalBytes() throws {
        let folder = fm.temporaryDirectory.appendingPathComponent("crumple-dup-\(UUID().uuidString)")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: folder) }
        var bytes = [UInt8](repeating: 3, count: 400_000)
        let a = folder.appendingPathComponent("a"), b = folder.appendingPathComponent("b"), c = folder.appendingPathComponent("c")
        try Data(bytes).write(to: a)
        try Data(bytes).write(to: b)
        bytes[100_000] = 4 // between the sampled parts
        try Data(bytes).write(to: c)
        let size = Int64(bytes.count)

        #expect(DuplicateFinder.sampleHash(a, size: size) == DuplicateFinder.sampleHash(c, size: size))
        #expect(DuplicateFinder.fullHash(a) == DuplicateFinder.fullHash(b))
        #expect(DuplicateFinder.fullHash(a) != DuplicateFinder.fullHash(c))
    }
}

@Suite("扫描和格式")
struct ScannerTests {
    @Test("按实际占用计算文件夹大小")
    func measuresFolders() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("crumple-size-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("inner"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data(count: 300_000).write(to: folder.appendingPathComponent("a.bin"))
        try Data(count: 200_000).write(to: folder.appendingPathComponent("inner/b.bin"))
        let size = Scanner.allocatedSize(of: folder)
        #expect(size >= 500_000 && size < 600_000)
        #expect(Scanner.measure([folder, folder.appendingPathComponent("missing")]) == [size, 0])
    }

    @Test("大文件按扩展名分类")
    func tagsByExtension() {
        #expect(FileTag.of(URL(fileURLWithPath: "/x/movie.MOV")) == .video)
        #expect(FileTag.of(URL(fileURLWithPath: "/x/backup.zip")) == .archive)
        #expect(FileTag.of(URL(fileURLWithPath: "/x/macOS.dmg")) == .diskImage)
        #expect(FileTag.of(URL(fileURLWithPath: "/x/report.pdf")) == .document)
        #expect(FileTag.of(URL(fileURLWithPath: "/x/live.wav")) == .audio)
        #expect(FileTag.of(URL(fileURLWithPath: "/x/data.bin")) == .other)
    }

    @Test("版本号按数字比较")
    func comparesVersions() {
        #expect(UpdateCheck.isNewer("1.10", than: "1.9"))
        #expect(UpdateCheck.isNewer("2.0", than: "1.9.9"))
        #expect(UpdateCheck.isNewer("1.0.1", than: "1.0"))
        #expect(!UpdateCheck.isNewer("1.0", than: "1"))
        #expect(!UpdateCheck.isNewer("1.2", than: "1.10"))
    }

    @Test("家目录里的路径显示成 ~/…")
    func displaysHomePaths() {
        #expect(Paths.display(Paths.home.appendingPathComponent("Downloads/a.zip")) == "~/Downloads/a.zip")
        #expect(Paths.display(URL(fileURLWithPath: "/Applications/Safari.app")) == "/Applications/Safari.app")
    }

    @Test("大小和日期的中文写法")
    func formatting() {
        #expect(Int64(0).byteString == "0 KB")
        #expect(Date().agoText == "今天")
        #expect(Date().addingTimeInterval(-86_400 * 1.5).agoText == "昨天")
        #expect(Date().addingTimeInterval(-86_400 * 10).agoText == "10 天前")
    }
}

@Suite("健康分")
struct HealthScoreTests {
    func healthy() -> [HealthScore.Factor] {
        [HealthScore.memory(pressure: 1, swap: 0),
         HealthScore.cpu(history: Array(repeating: 0.1, count: 20), load: 2, cores: 10),
         HealthScore.disk(available: 300_000_000_000, total: 500_000_000_000),
         HealthScore.thermal(.nominal),
         HealthScore.battery(health: 100)]
    }

    @Test("一切正常时是满分")
    func healthyIsFull() {
        #expect(HealthScore.combine(healthy()) == 100)
        #expect(HealthScore.label(100) == "很好")
    }

    @Test("内存用满本身不扣分，压力和交换才扣")
    func memoryJudgedByPressure() {
        #expect(HealthScore.memory(pressure: 1, swap: 0).score == 100)
        #expect(HealthScore.memory(pressure: 2, swap: 0).score < 70)
        #expect(HealthScore.memory(pressure: 1, swap: 4_000_000_000).score < 100)
        #expect(HealthScore.memory(pressure: 4, swap: 0).score < HealthScore.memory(pressure: 2, swap: 0).score)
    }

    @Test("CPU 偶尔冲高一下不扣分，一直忙才扣")
    func cpuLooksAtTheLastHalfMinute() {
        let spike = Array(repeating: 0.1, count: 19) + [1.0]
        #expect(HealthScore.cpu(history: spike, load: 2, cores: 10).score == 100)
        #expect(HealthScore.cpu(history: Array(repeating: 0.95, count: 20), load: 12, cores: 10).score < 60)
    }

    @Test("磁盘越满分越低，而且是连续变化的")
    func diskIsSmooth() {
        let total: Int64 = 500_000_000_000
        let scores = stride(from: 0.0, through: 0.3, by: 0.01).map {
            HealthScore.disk(available: Int64(Double(total) * $0), total: total).score
        }
        #expect(scores == scores.sorted())
        #expect(zip(scores, scores.dropFirst()).allSatisfy { $1 - $0 <= 12 })
    }

    @Test("一项严重问题不会被其他几项平均掉")
    func weakestPartCapsTheTotal() {
        var factors = healthy()
        factors[2] = HealthScore.disk(available: 8_000_000_000, total: 500_000_000_000) // 1.6% free
        #expect(HealthScore.combine(factors) <= 50)
        #expect(HealthScore.label(Int(HealthScore.combine(factors))) == "需要关注")
    }

    @Test("没有电池时按其余几项算")
    func noBattery() {
        #expect(HealthScore.combine(Array(healthy().dropLast())) == 100)
    }
}

@Suite("纸篓和声音")
struct BasketTests {
    @Test("纸篓里的纸团跟着废纸篓变多，空了就没有")
    func pileFollowsTrash() {
        #expect(AppModel.pileCount(forTrash: 0) == 0)
        let sizes: [Int64] = [1_000, 1_000_000, 100_000_000, 5_000_000_000, 500_000_000_000]
        let counts = sizes.map(AppModel.pileCount(forTrash:))
        #expect(counts.allSatisfy { $0 >= 1 && $0 <= 30 })
        #expect(counts == counts.sorted())
        #expect(counts.last == 30)
    }

    @Test("每种声音都有声、不爆音、长度合适")
    func soundsAreSane() {
        for sound in SoundBoard.Sound.allCases {
            let samples = SoundBoard.synthesize(sound)
            let seconds = Double(samples.count) / 44_100
            #expect(seconds > 0.2 && seconds < 1.2, "\(sound)")
            #expect(samples.allSatisfy { $0.isFinite && abs($0) <= 0.81 }, "\(sound)")
            let loudness = samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count)
            #expect(loudness > 0.002, "\(sound)")
        }
    }
}

@Suite("亲手投纸团")
struct TossTests {
    let size = CGSize(width: 900, height: 560)
    var basket: BasketGeometry { BasketGeometry(rect: BasketGeometry.rect(in: size)) }

    func toss(_ dx: CGFloat, _ dy: CGFloat, from start: CGPoint = CGPoint(x: 300, y: 250)) -> TossedPaper {
        TossedPaper(itemID: "", born: 0, start: start, velocity: CGVector(dx: dx, dy: dy), seed: 1, icon: nil,
                    startCrumple: 1, basket: basket, canvas: size)
    }

    @Test("投中、擦框、投偏")
    func classifiesThrows() {
        #expect(toss(867, -323).kind == .make)
        #expect(toss(768, -323).kind == .rim)
        #expect(toss(600, -323).kind == .miss)
    }

    @Test("按住 ⌥ 时落到碎纸机口才算粉碎，松开 ⌥ 同样的一投进纸篓")
    func shredderOnlyCatchesWhenArmed() {
        let shredder = ShredderGeometry(rect: ShredderGeometry.rect(above: basket))
        let above = CGPoint(x: shredder.slot.midX, y: shredder.slot.midY - 120)
        let armed = TossedPaper(itemID: "", born: 0, start: above, velocity: .zero, seed: 1, icon: nil,
                                startCrumple: 0, basket: basket, canvas: size, shredder: shredder)
        #expect(armed.kind == .shred)
        #expect(toss(0, 0, from: above).kind == .make)
    }

    @Test("按着 ⌥ 但扔偏了，不会被当成粉碎")
    func armedMissIsNotShred() {
        let shredder = ShredderGeometry(rect: ShredderGeometry.rect(above: basket))
        let wide = TossedPaper(itemID: "", born: 0, start: CGPoint(x: 300, y: 250), velocity: CGVector(dx: 600, dy: -323),
                               seed: 1, icon: nil, startCrumple: 0, basket: basket, canvas: size, shredder: shredder)
        #expect(wide.kind != .shred)
    }

    @Test("直接放进篓里也算投中")
    func droppingInsideCounts() {
        let inside = CGPoint(x: basket.rect.midX, y: basket.rect.midY + 10)
        #expect(toss(0, 0, from: inside).kind == .make)
    }

    @Test("往上扔、没落回篓口高度就算没中")
    func upwardThrowFromBelowMisses() {
        let below = CGPoint(x: 200, y: basket.mouth.midY + 80)
        #expect(toss(100, -50, from: below).kind == .miss)
    }
}
