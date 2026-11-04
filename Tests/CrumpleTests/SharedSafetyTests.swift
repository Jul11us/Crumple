import Foundation
import Testing
@testable import Crumple

/// One entry of Tests/Shared/never-touch.json. The Windows tests read the same file.
struct SharedSafetyCase: Decodable, CustomStringConvertible {
    let path: String
    let expect: String
    let platform: String?

    var description: String { path }
}

private struct SharedSafetyFile: Decodable {
    let cases: [SharedSafetyCase]
}

@Suite("两端共用的禁区")
struct SharedSafetyTests {
    static let cases: [SharedSafetyCase] = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Shared/never-touch.json")
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(SharedSafetyFile.self, from: data) else { return [] }
        return file.cases.filter { $0.platform == nil || $0.platform == "macos" }
    }()

    @Test("共用用例文件读得到")
    func casesLoad() {
        #expect(Self.cases.count > 10)
        #expect(Self.cases.allSatisfy { $0.path.hasPrefix("~/") && ["allow", "refuse"].contains($0.expect) })
    }

    @Test("每条路径都按约定放行或拒绝", arguments: SharedSafetyTests.cases)
    func followsSharedCase(_ entry: SharedSafetyCase) {
        let url = Paths.home.appendingPathComponent(String(entry.path.dropFirst(2)))
        #expect(Cleaner.isSafeTarget(url) == (entry.expect == "allow"), "\(entry.path)")
    }

    @Test("禁区里的东西不会被移走")
    func cleanRefusesNeverTouchPlaces() throws {
        let fm = FileManager.default
        let sandbox = Paths.home.appendingPathComponent("Library/Caches/\(Scanner.ownBundleID).tests/\(UUID().uuidString)")
        let keys = sandbox.appendingPathComponent(".ssh")
        try fm.createDirectory(at: keys, withIntermediateDirectories: true)
        defer { removeSandbox(sandbox) }
        let key = keys.appendingPathComponent("id_ed25519")
        try Data("secret".utf8).write(to: key)

        #expect(!Cleaner.clean(key, mode: .delete))
        #expect(!Cleaner.clean(keys, mode: .delete))
        #expect(fm.fileExists(atPath: key.path))
        #expect(!Cleaner.restore(TrashedFile(original: keys.appendingPathComponent("restored").path,
                                             trashed: sandbox.appendingPathComponent(".Trash/x").path)))
    }
}
