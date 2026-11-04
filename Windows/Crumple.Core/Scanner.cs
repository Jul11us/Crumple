using System.Collections.Concurrent;
using System.Security.Cryptography;

namespace Crumple.Core;

public sealed record ScanLocation(string Path, FileCategory Category, bool SelectByDefault, int MinimumAgeDays = 0,
    string[]? OwnerProcesses = null, bool TopLevelOnly = false);

public sealed class Scanner(PathPolicy policy, Func<string, string?>? identity = null)
{
    public ScanResult Smart(IEnumerable<ScanLocation> locations, IEnumerable<string> personalFolders,
        Preferences preferences, Func<string[], bool> isRunning, IProgress<ScanProgress>? progress, CancellationToken token)
    {
        var items = new Dictionary<string, CleanItem>(PathPolicy.Comparer);
        int checkedCount = 0, skipped = 0;
        foreach (var location in locations)
        {
            token.ThrowIfCancellationRequested();
            var owners = location.OwnerProcesses ?? [];
            var running = isRunning(owners);
            foreach (var path in policy.WalkFiles(location.Path, token, () => skipped++))
            {
                checkedCount++;
                if (checkedCount % 100 == 0) progress?.Report(new(checkedCount, path));
                if (location.TopLevelOnly && !PathPolicy.Comparer.Equals(System.IO.Path.GetDirectoryName(path), location.Path)) continue;
                try
                {
                    var stamp = FileStamp.Read(path);
                    if (stamp.Length == 0 || stamp.LastWriteUtc > DateTime.UtcNow.AddDays(-location.MinimumAgeDays)) continue;
                    if (location.Category is FileCategory.Installers or FileCategory.OldDownloads)
                    {
                        var installer = IsInstaller(path);
                        if ((location.Category == FileCategory.Installers) != installer) continue;
                    }
                    items.TryAdd(path, new() { Path = path, Category = location.Category, Stamp = stamp,
                        Selected = location.SelectByDefault && !running, OwnerProcesses = owners });
                }
                catch (Exception e) when (e is IOException or UnauthorizedAccessException) { skipped++; }
            }
        }
        progress?.Report(new(checkedCount, ""));
        return new(items.Values.OrderByDescending(x => x.Size).ToList(), checkedCount, skipped);
    }

    public ScanResult Large(IEnumerable<string> folders, long minBytes, IProgress<ScanProgress>? progress, CancellationToken token)
    {
        var items = new List<CleanItem>();
        int checkedCount = 0, skipped = 0;
        var seen = new HashSet<string>(PathPolicy.Comparer);
        foreach (var root in folders)
        foreach (var path in policy.WalkFiles(root, token, () => skipped++))
        {
            if (!seen.Add(path)) continue;
            checkedCount++;
            if (checkedCount % 100 == 0) progress?.Report(new(checkedCount, path));
            try
            {
                var stamp = FileStamp.Read(path);
                if (stamp.Length >= minBytes) items.Add(new() { Path = path, Category = FileCategory.Large, Stamp = stamp });
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException) { skipped++; }
        }
        progress?.Report(new(checkedCount, ""));
        return new(items.OrderByDescending(x => x.Size).ToList(), checkedCount, skipped);
    }

    /// How many files the duplicate scan hashes at once.
    public const int HashWidth = 4;

    public ScanResult Duplicates(IEnumerable<string> folders, long minBytes, IProgress<ScanProgress>? progress, CancellationToken token)
    {
        var candidates = Large(folders, minBytes, progress, token);
        var items = new List<CleanItem>();
        var identities = new HashSet<string>(StringComparer.Ordinal);
        var unique = new List<CleanItem>();
        foreach (var file in candidates.Items)
        {
            token.ThrowIfCancellationRequested();
            var id = identity?.Invoke(file.Path);
            if (identity != null && id == null) { candidates = candidates with { Skipped = candidates.Skipped + 1 }; continue; }
            if (id == null || identities.Add(id)) unique.Add(file);
        }
        // A few files at a time keep a solid-state disk busy; more only make the reads queue.
        var parallel = new ParallelOptions { CancellationToken = token, MaxDegreeOfParallelism = HashWidth };
        // Cheap pass: a few samples from each file that shares its size with another.
        var sampled = new ConcurrentBag<(CleanItem File, string Hash)>();
        Parallel.ForEach(unique.GroupBy(x => x.Size).Where(x => x.Count() > 1).SelectMany(x => x), parallel, file =>
        {
            try { sampled.Add((file, SampleHash(file.Path, file.Size, token))); }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
        });
        // Thorough pass: the whole file, only for files that still look alike.
        var alike = sampled.GroupBy(x => (x.File.Size, x.Hash)).Where(x => x.Count() > 1).SelectMany(x => x.Select(y => y.File));
        var hashed = new ConcurrentBag<(CleanItem File, string Hash)>();
        var compared = 0;
        Parallel.ForEach(alike, parallel, file =>
        {
            progress?.Report(new(Interlocked.Increment(ref compared), file.Path));
            try
            {
                if (!policy.CanReadFile(file.Path) || !file.Stamp.Matches(file.Path)) return;
                using var stream = OpenRead(file.Path);
                var hash = FullHash(stream, token);
                if (file.Stamp.Matches(file.Path)) hashed.Add((file, hash));
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
        });
        foreach (var copies in hashed.GroupBy(x => (x.File.Size, x.Hash)).Where(x => x.Count() > 1))
        {
            var ordered = copies.Select(x => x.File).OrderBy(x => LooksCopied(x.Name)).ThenBy(x => x.Stamp.CreatedUtc)
                .ThenBy(x => x.Path.Length).ThenBy(x => x.Path, PathPolicy.Comparer).ToList();
            var keeper = ordered[0];
            items.AddRange(ordered.Skip(1).Select(x => new CleanItem { Path = x.Path, Category = FileCategory.Duplicate,
                Stamp = x.Stamp, Selected = true, Keeper = keeper.Path, KeeperStamp = keeper.Stamp, ContentHash = copies.Key.Hash }));
        }
        return new(items.OrderByDescending(x => x.Size).ThenBy(x => x.Keeper, PathPolicy.Comparer).ToList(), candidates.Checked, candidates.Skipped);
    }

    public List<FolderSize> Analyze(string root, IProgress<ScanProgress>? progress, CancellationToken token)
    {
        var groups = new Dictionary<string, (long Bytes, int Files)>(PathPolicy.Comparer);
        int count = 0, skipped = 0;
        foreach (var path in policy.WalkFiles(root, token, () => skipped++))
        {
            try
            {
                var relative = System.IO.Path.GetRelativePath(root, path);
                var first = relative.Split(System.IO.Path.DirectorySeparatorChar)[0];
                var key = System.IO.Path.Combine(root, first);
                groups.TryGetValue(key, out var value);
                groups[key] = (value.Bytes + FileStamp.Read(path).Length, value.Files + 1);
                if (++count % 100 == 0) progress?.Report(new(count, path));
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException) { skipped++; }
        }
        return groups.Select(x => new FolderSize(x.Key, x.Value.Bytes, x.Value.Files, skipped))
            .OrderByDescending(x => x.Bytes).ToList();
    }

    public static bool IsInstaller(string path) => System.IO.Path.GetExtension(path).ToLowerInvariant()
        is ".exe" or ".msi" or ".msix" or ".msixbundle" or ".appx" or ".appxbundle" or ".iso";
    private static bool LooksCopied(string name) => new[] { "copy", "副本", "拷贝", "(1)", "(2)" }
        .Any(x => name.Contains(x, StringComparison.OrdinalIgnoreCase));
    public static FileStream OpenRead(string path, bool allowDelete = false) => new(path, FileMode.Open, FileAccess.Read,
        allowDelete ? FileShare.Read | FileShare.Delete : FileShare.Read, 1024 * 1024, FileOptions.SequentialScan);

    public static string SampleHash(string path, long length, CancellationToken token)
    {
        using var stream = OpenRead(path);
        using var hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        byte[] bytes = new byte[16 * 1024];
        long[] offsets = length <= bytes.Length * 3 ? [0] : [0, length / 2 - bytes.Length / 2, length - bytes.Length];
        foreach (var offset in offsets)
        {
            token.ThrowIfCancellationRequested();
            stream.Position = offset;
            var remaining = length <= bytes.Length * 3 ? length : bytes.Length;
            while (remaining > 0)
            {
                var read = stream.Read(bytes, 0, (int)Math.Min(remaining, bytes.Length));
                if (read == 0) throw new EndOfStreamException();
                hash.AppendData(bytes, 0, read);
                remaining -= read;
            }
        }
        return Convert.ToHexString(hash.GetHashAndReset());
    }

    public static string FullHash(Stream stream, CancellationToken token)
    {
        using var hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        byte[] buffer = new byte[1024 * 1024];
        int read;
        while ((read = stream.Read(buffer, 0, buffer.Length)) > 0)
        {
            token.ThrowIfCancellationRequested();
            hash.AppendData(buffer, 0, read);
        }
        return Convert.ToHexString(hash.GetHashAndReset());
    }
}
