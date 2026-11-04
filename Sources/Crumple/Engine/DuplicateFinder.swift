import Foundation
import CryptoKit

/// Finds files whose contents are byte-for-byte identical. Only reads the disk.
///
/// Files are first grouped by size, then by a hash of a few small samples, and only the
/// survivors are hashed in full, so most files are never read at all.
enum DuplicateFinder {
    private struct Candidate: Sendable {
        let url: URL
        let size: Int64
        let allocated: Int64
        let created: Date
        let modified: Date
    }

    static func scan(minBytes: Int64, ignored: [String], progress: @escaping @Sendable (String) -> Void) async -> [CleanItem] {
        guard let (bySize, checked) = listBySize(minBytes: minBytes, ignored: ignored, progress: progress) else { return [] }

        let sameSize = bySize.values.filter { $0.count > 1 }.flatMap { $0 }
        let total = sameSize.count
        var compared = 0

        // Cheap pass: a few samples from each file that shares its size with another.
        let sampled = await hashAll(sameSize) {
            compared += 1
            if compared % 20 == 0 { progress(String(localized: "正在比对内容 \(compared)/\(total)")) }
        } hash: { sampleHash($0.url, size: $0.size) }
        if Task.isCancelled { return [] }

        // Thorough pass: the whole file, only for files that still look alike.
        let alike = Dictionary(grouping: sampled) { "\($0.file.size):\($0.hash)" }.values
            .filter { $0.count > 1 }.flatMap { $0.map(\.file) }
        let hashed = await hashAll(alike) {} hash: { fullHash($0.url) }
        if Task.isCancelled { return [] }

        var items: [CleanItem] = []
        for copies in Dictionary(grouping: hashed, by: { "\($0.file.size):\($0.hash)" }).values where copies.count > 1 {
            items += describe(copies.map(\.file), group: copies[0].hash)
        }
        progress(String(localized: "已检查 \(checked.formatted()) 个文件"))

        // Biggest waste first, and copies of the same file next to each other.
        let wasted = Dictionary(grouping: items) { $0.keeper?.path ?? "" }.mapValues { $0.reduce(0) { $0 + $1.size } }
        return items.sorted {
            let a = wasted[$0.keeper?.path ?? ""] ?? 0, b = wasted[$1.keeper?.path ?? ""] ?? 0
            return a != b ? a > b : $0.url.path < $1.url.path
        }
    }

    /// Walks the personal folders and groups the files worth comparing by size; nil when the scan is
    /// stopped. Kept synchronous: the directory enumerator can't be iterated from async code.
    private static func listBySize(minBytes: Int64, ignored: [String],
                                   progress: @Sendable (String) -> Void) -> (bySize: [Int64: [Candidate]], checked: Int)? {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isPackageKey, .fileSizeKey, .totalFileAllocatedSizeKey,
                                      .creationDateKey, .contentModificationDateKey, .fileResourceIdentifierKey]
        let keySet = Set(keys)
        let ignore = IgnoreList.Matcher(ignored)
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
                if checked % 500 == 0, Task.isCancelled { return nil }
                if checked % 500 == 0 { progress(String(localized: "已检查 \(checked.formatted()) 个文件")) }
                if ignore.contains(url) {
                    enumerator.skipDescendants()
                    continue
                }
                guard let values = try? url.resourceValues(forKeys: keySet),
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
        return (bySize, checked)
    }

    /// How many files are hashed at once. A few keep a solid-state disk busy; more only make the reads queue.
    private static let hashWidth = 4

    /// Hashes `files` a few at a time, dropping any that can't be read. The child tasks see the
    /// scan's cancellation, so `fullHash` stops mid-file when the scan is stopped.
    private static func hashAll(_ files: [Candidate], onEach: () -> Void,
                                hash: @escaping @Sendable (Candidate) -> String?) async -> [(file: Candidate, hash: String)] {
        await withTaskGroup(of: (Candidate, String?).self) { group in
            var results: [(file: Candidate, hash: String)] = []
            var queue = files.makeIterator()
            for _ in 0..<hashWidth {
                guard let file = queue.next() else { break }
                group.addTask { (file, hash(file)) }
            }
            while let (file, key) = await group.next() {
                onEach()
                if let key { results.append((file, key)) }
                if !Task.isCancelled, let next = queue.next() { group.addTask { (next, hash(next)) } }
            }
            return results
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
            if Task.isCancelled { return nil }
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
        Matcher(ignored).contains(url)
    }

    /// Normalizes the ignored folders once, for scans that check every file they walk past.
    struct Matcher: Sendable {
        private let entries: [(path: String, prefix: String)]

        init(_ ignored: [String]) {
            entries = ignored.map { entry in
                let path = Paths.normalized(URL(fileURLWithPath: entry))
                return (path, path == "/" ? path : path + "/")
            }
        }

        func contains(_ url: URL) -> Bool {
            guard !entries.isEmpty else { return false }
            let path = Paths.normalized(url)
            return entries.contains { path == $0.path || path.hasPrefix($0.prefix) }
        }
    }
}
