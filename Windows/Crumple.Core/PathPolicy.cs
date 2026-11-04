namespace Crumple.Core;

/// Only individual files below an explicitly allowed root can be moved. Links, junctions,
/// cloud placeholders, protected roots and Crumple's own state are excluded at scan AND cleanup time.
public sealed class PathPolicy
{
    public static StringComparison Comparison => OperatingSystem.IsWindows()
        ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal;
    public static StringComparer Comparer => OperatingSystem.IsWindows()
        ? StringComparer.OrdinalIgnoreCase : StringComparer.Ordinal;
    public IReadOnlyList<string> Roots { get; }
    public IReadOnlyList<string> Exclusions { get; }
    public IReadOnlyList<string> ProtectedRoots { get; }

    public PathPolicy(IEnumerable<string> roots, IEnumerable<string> exclusions, IEnumerable<string>? protectedRoots = null)
    {
        Roots = NormalizeMany(roots);
        Exclusions = NormalizeMany(exclusions);
        ProtectedRoots = NormalizeMany(protectedRoots ?? []);
    }

    private static string[] NormalizeMany(IEnumerable<string> paths) => paths.Where(x => !string.IsNullOrWhiteSpace(x))
        .Select(Normalize).Distinct(Comparer).ToArray();
    public static string Normalize(string path) => System.IO.Path.TrimEndingDirectorySeparator(System.IO.Path.GetFullPath(path));

    public static bool IsBelow(string path, string root) => path.StartsWith(
        System.IO.Path.EndsInDirectorySeparator(root) ? root : root + System.IO.Path.DirectorySeparatorChar, Comparison);

    public bool IsIgnored(string path)
    {
        path = Normalize(path);
        return Exclusions.Any(x => Comparer.Equals(path, x) || IsBelow(path, x));
    }

    public bool InScope(string path)
    {
        try
        {
            path = Normalize(path);
            if (path.Contains(':') && OperatingSystem.IsWindows() && path.AsSpan(2).Contains(':')) return false; // NTFS ADS
            if (OperatingSystem.IsWindows())
            {
                var components = path[(System.IO.Path.GetPathRoot(path)?.Length ?? 0)..].Split(System.IO.Path.DirectorySeparatorChar);
                if (components.Any(x => x.EndsWith('.') || x.EndsWith(' '))) return false; // Win32 path aliases
            }
            if (path.StartsWith(@"\\", StringComparison.Ordinal) || path.StartsWith(@"\\?", StringComparison.Ordinal)) return false;
            return Roots.Any(x => IsBelow(path, x)) && !IsIgnored(path) && !IsSensitive(path)
                && !ProtectedRoots.Any(x => Comparer.Equals(path, x) || IsBelow(path, x));
        }
        catch (ArgumentException) { return false; }
        catch (NotSupportedException) { return false; }
    }

    /// Folders that hold keys and credentials. Nothing re-creates them once they are gone, so they are
    /// refused wherever they appear, even below a root the user chose. The macOS edition refuses the
    /// same kinds of places; both are checked against Tests/Shared/never-touch.json.
    public static IReadOnlyList<string> SensitiveFolderNames { get; } = [".ssh", ".gnupg", ".aws", ".azure", ".kube"];
    /// Runs of folder names refused wherever they appear (for example AppData\Roaming\Microsoft\Credentials).
    public static IReadOnlyList<string[]> SensitiveFolderRuns { get; } =
        [["Microsoft", "Credentials"], ["Microsoft", "Protect"], ["Microsoft", "Vault"], ["Microsoft", "Crypto"], ["Microsoft", "SystemCertificates"]];

    /// Compared without case on every system, since Windows ignores it.
    public static bool IsSensitive(string path)
    {
        var parts = Normalize(path).Split(new[] { System.IO.Path.DirectorySeparatorChar, System.IO.Path.AltDirectorySeparatorChar },
            StringSplitOptions.RemoveEmptyEntries);
        for (var i = 0; i < parts.Length; i++)
        {
            if (SensitiveFolderNames.Contains(parts[i], StringComparer.OrdinalIgnoreCase)) return true;
            foreach (var run in SensitiveFolderRuns)
            {
                if (i + run.Length > parts.Length) continue;
                var matches = true;
                for (var j = 0; j < run.Length && matches; j++) matches = string.Equals(run[j], parts[i + j], StringComparison.OrdinalIgnoreCase);
                if (matches) return true;
            }
        }
        return false;
    }

    public bool CanReadFile(string path)
    {
        if (!InScope(path) || HasUnsafeAncestor(path)) return false;
        try { return IsOrdinary(File.GetAttributes(path)); }
        catch (IOException) { return false; }
        catch (UnauthorizedAccessException) { return false; }
    }

    public bool CanRestoreTo(string path) => InScope(path) && !HasUnsafeAncestor(path)
        && !File.Exists(path) && !Directory.Exists(path);

    public static bool IsOrdinary(FileAttributes attributes) =>
        (attributes & (FileAttributes.Directory | FileAttributes.ReparsePoint | FileAttributes.Offline | FileAttributes.System)) == 0
        && ((int)attributes & 0x00440000) == 0; // recall-on-open / recall-on-data-access

    public static bool HasUnsafeAncestor(string path)
    {
        try
        {
            for (var current = Normalize(path); !string.IsNullOrEmpty(current); current = System.IO.Path.GetDirectoryName(current))
            {
                try
                {
                    var attrs = File.GetAttributes(current);
                    if ((attrs & (FileAttributes.ReparsePoint | FileAttributes.Offline)) != 0) return true;
                }
                catch (FileNotFoundException) { }
                catch (DirectoryNotFoundException) { }
            }
            return false;
        }
        catch (IOException) { return true; }
        catch (UnauthorizedAccessException) { return true; }
    }

    public IEnumerable<string> WalkFiles(string root, CancellationToken cancellation, Action? skipped = null)
    {
        if (!Directory.Exists(root) || IsIgnored(root) || HasUnsafeAncestor(root)) yield break;
        var pending = new Stack<string>();
        pending.Push(root);
        while (pending.TryPop(out var directory))
        {
            cancellation.ThrowIfCancellationRequested();
            string[] entries;
            try { entries = Directory.GetFileSystemEntries(directory); }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException) { skipped?.Invoke(); continue; }
            foreach (var path in entries)
            {
                cancellation.ThrowIfCancellationRequested();
                if (IsIgnored(path)) continue;
                FileAttributes attrs;
                try { attrs = File.GetAttributes(path); }
                catch (Exception e) when (e is IOException or UnauthorizedAccessException) { skipped?.Invoke(); continue; }
                if ((attrs & (FileAttributes.ReparsePoint | FileAttributes.System | FileAttributes.Offline)) != 0
                    || ((int)attrs & 0x00440000) != 0) { skipped?.Invoke(); continue; }
                if ((attrs & FileAttributes.Directory) != 0)
                {
                    var name = System.IO.Path.GetFileName(path);
                    if (name is not (".git" or ".svn" or ".hg" or "$RECYCLE.BIN") && !IsIgnored(path) && !IsSensitive(path)) pending.Push(path);
                }
                else if (InScope(path)) yield return path;
            }
        }
    }
}
