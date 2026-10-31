import Foundation
import CryptoKit

/// Finds files whose contents are byte-for-byte identical. Only reads the disk.
///
/// Files are first grouped by size, then by a hash of a few small samples, and only the
/// survivors are hashed in full, so most files are never read at all.
enum DuplicateFinder {
    private struct Candidate {
        let url: URL
        let size: Int64
        let allocated: Int64
        let created: Date
        let modified: Date
    }

    static func scan(minBytes: Int64, ignored: [String], progress: @escaping @Sendable (String) -> Void) -> [CleanItem] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isPackageKey, .fileSizeKey, .totalFileAllocatedSizeKey,
                                      .creationDateKey, .contentModificationDateKey, .fileResourceIdentifierKey]
        var bySize: [Int64: [Candidate]] = [:]
        var seenFiles = Set<NSObject>()
        var checked = 0

        for folder in Scanner.largeFileFolders {
            let root = Paths.home.appendingPathComponent(folder)
            guard let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { continue }
            for case let url as URL in enumerator {
                checked += 1
                if checked % 500 == 0 { progress(String(localized: "已检查 \(checked.formatted()) 个文件")) }
                if IgnoreList.contains(url, in: ignored) {
                    enumerator.skipDescendants()
                    continue
                }
                guard let values = try? url.resourceValues(forKeys: Set(keys)),
                      values.isPackage != true, values.isRegularFile == true,
                      let size = values.fileSize.map(Int64.init), size >= minBytes else { continue }
                let allocated = Int64(values.totalFileAllocatedSize ?? 0)
                // Files that live only in iCloud take no space here, and reading them would download them.
                guard allocated > 0 else { continue }
                // Hard links are one file under two names; removing one frees nothing.
                if let identity = values.fileResourceIdentifier as? NSObject {
                    guard seenFiles.insert(identity).inserted else { continue }
                }
                bySize[size, default: []].append(Candidate(
                    url: url, size: size, allocated: allocated,
                    created: values.creationDate ?? .distantPast,
                    modified: values.contentModificationDate ?? .distantPast
                ))
            }
        }

        let sameSize = bySize.values.filter { $0.count > 1 }
        let total = sameSize.reduce(0) { $0 + $1.count }
        var compared = 0
        var items: [CleanItem] = []
        for group in sameSize {
            // Cheap pass: a few samples from each file.
            var bySample: [String: [Candidate]] = [:]
            for file in group {
                compared += 1
                if compared % 20 == 0 { progress(String(localized: "正在比对内容 \(compared)/\(total)")) }
                guard let key = sampleHash(file.url, size: file.size) else { continue }
                bySample[key, default: []].append(file)
            }
            // Thorough pass: the whole file, only for files that still look alike.
            for similar in bySample.values where similar.count > 1 {
                var byContent: [String: [Candidate]] = [:]
                for file in similar {
                    guard let key = fullHash(file.url) else { continue }
                    byContent[key, default: []].append(file)
                }
                for (hash, copies) in byContent where copies.count > 1 {
                    items += describe(copies, group: hash)
                }
            }
        }
        progress(String(localized: "已检查 \(checked.formatted()) 个文件"))

        // Biggest waste first, and copies of the same file next to each other.
        let wasted = Dictionary(grouping: items) { $0.keeper?.path ?? "" }.mapValues { $0.reduce(0) { $0 + $1.size } }
        return items.sorted {
            let a = wasted[$0.keeper?.path ?? ""] ?? 0, b = wasted[$1.keeper?.path ?? ""] ?? 0
            return a != b ? a > b : $0.url.path < $1.url.path
        }
    }

    /// One copy stays (the most "original" looking one); the others become items, already ticked.
    private static func describe(_ copies: [Candidate], group: String) -> [CleanItem] {
        let ranked = copies.sorted { originality($0) < originality($1) }
        let keeper = ranked[0]
        return ranked.dropFirst().map { copy in
            makeItem(copy.url, size: copy.allocated, modified: copy.modified, keeper: keeper.url)
        }
    }

    static func makeItem(_ url: URL, size: Int64, modified: Date?, keeper: URL) -> CleanItem {
        CleanItem(
            id: url.path, url: url, name: url.lastPathComponent,
            detail: String(localized: "\(Paths.display(url.deletingLastPathComponent())) · 和 \(Paths.display(keeper)) 一样"),
            size: size, isSelected: true, tag: FileTag.of(url), lastUsed: modified, keeper: keeper
        )
    }

    /// Lower is more likely the original: not in Downloads, no "copy" in the name, older, shallower.
    private static func originality(_ file: Candidate) -> (Int, Int, Date, Int, String) {
        let path = file.url.path
        let inDownloads = path.hasPrefix(Paths.home.appendingPathComponent("Downloads").path + "/") ? 1 : 0
        let name = file.url.deletingPathExtension().lastPathComponent.lowercased()
        // Finder's own suffixes for copies, in English and Chinese.
        let looksCopied = [" copy", "副本", "拷贝", "(1)", "(2)", "(3)", " 2", " 3"].contains { name.hasSuffix($0) || name.contains($0 + " ") } ? 1 : 0
        return (looksCopied, inDownloads, file.created, file.url.pathComponents.count, path)
    }

    // MARK: - Hashing

    private static let sampleLength = 16 * 1024

    /// Hashes the start, middle and end of a file.
    static func sampleHash(_ url: URL, size: Int64) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        let length = Int64(sampleLength)
        let offsets: [Int64] = size <= length * 3 ? [0] : [0, size / 2 - length / 2, size - length]
        for offset in offsets {
            do {
                try handle.seek(toOffset: UInt64(offset))
                guard let data = try handle.read(upToCount: size <= length * 3 ? Int(size) : sampleLength) else { return nil }
                hasher.update(data: data)
            } catch {
                return nil
            }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Hashes the whole file, a megabyte at a time.
    static func fullHash(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk: Data?
            do { chunk = try autoreleasepool { try handle.read(upToCount: 1 << 20) } } catch { return nil }
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Paths the user never wants to see in scan results. Anything inside an ignored folder is ignored too.
enum IgnoreList {
    static func contains(_ url: URL, in ignored: [String]) -> Bool {
        let path = Paths.normalized(url)
        return ignored.contains { entry in
            let entry = Paths.normalized(URL(fileURLWithPath: entry))
            return path == entry || path.hasPrefix(entry == "/" ? entry : entry + "/")
        }
    }
}
