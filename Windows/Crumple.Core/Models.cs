using System.Text.Json;

namespace Crumple.Core;

public enum ScanKind { Smart, Large, Duplicates, Manual }
public enum FileCategory { Temporary, BrowserCache, Logs, DeveloperCache, AITools, Installers, OldDownloads, Large, Duplicate }

public sealed record FileStamp(long Length, DateTime LastWriteUtc, DateTime CreatedUtc)
{
    public static FileStamp Read(string path)
    {
        var info = new FileInfo(path);
        info.Refresh();
        if (!info.Exists || (info.Attributes & FileAttributes.Directory) != 0)
            throw new IOException("The file is no longer available.");
        return new(info.Length, info.LastWriteTimeUtc, info.CreationTimeUtc);
    }

    public bool Matches(string path)
    {
        try { return this == Read(path); }
        catch (IOException) { return false; }
        catch (UnauthorizedAccessException) { return false; }
    }
}

public sealed class CleanItem
{
    public required string Path { get; init; }
    public required FileCategory Category { get; init; }
    public required FileStamp Stamp { get; init; }
    public string Name => System.IO.Path.GetFileName(Path);
    public long Size => Stamp.Length;
    public bool Selected { get; set; }
    public string[] OwnerProcesses { get; init; } = [];
    public string? Keeper { get; init; }
    public FileStamp? KeeperStamp { get; init; }
    public string? ContentHash { get; init; }
    public bool Removed { get; set; }
}

public sealed record ScanProgress(int Files, string Path);
public sealed record ScanResult(List<CleanItem> Items, int Checked, int Skipped);
public sealed record FolderSize(string Path, long Bytes, int Files, int Skipped);
public sealed record TrashRecord(string Original, string RecycledPath, FileStamp Stamp)
{
    public bool Restored { get; set; }
}

public sealed class CleanupReceipt
{
    public string Id { get; init; } = Guid.NewGuid().ToString("N");
    public DateTimeOffset Date { get; init; } = DateTimeOffset.Now;
    public ScanKind Source { get; init; }
    public List<TrashRecord> Files { get; init; } = [];
    public List<string> Errors { get; init; } = [];
    public long Bytes => Files.Sum(x => x.Stamp.Length);
}

public sealed class Preferences
{
    public string Language { get; set; } = "system";
    public string Appearance { get; set; } = "light";
    public int OldDownloadDays { get; set; } = 90;
    public int LargeFileMegabytes { get; set; } = 100;
    public int DuplicateMinKilobytes { get; set; } = 64;
    public bool MinimizeToTray { get; set; }
    public bool PlaysSounds { get; set; } = true;
    public List<string> IgnoredPaths { get; set; } = [];
    public List<string> ExtraFolders { get; set; } = [];
}

public static class SizeText
{
    public static string Format(long bytes)
    {
        string[] units = ["B", "KB", "MB", "GB", "TB", "PB"];
        double value = Math.Max(0, bytes);
        var i = 0;
        while (value >= 1024 && i < units.Length - 1) { value /= 1024; i++; }
        return $"{value:0.##} {units[i]}";
    }
}

/// Writes beside the destination and replaces it atomically; a damaged history is never silently overwritten.
public sealed class JsonStore(string directory)
{
    private static readonly JsonSerializerOptions Options = new() { WriteIndented = true };
    public T Read<T>(string name, Func<T> empty)
    {
        var path = System.IO.Path.Combine(directory, name + ".json");
        return !File.Exists(path) ? empty() : JsonSerializer.Deserialize<T>(File.ReadAllText(path), Options)
            ?? throw new InvalidDataException($"Invalid data: {path}");
    }

    public void Write<T>(string name, T data)
    {
        Directory.CreateDirectory(directory);
        var target = System.IO.Path.Combine(directory, name + ".json");
        var temp = target + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            using (var stream = new FileStream(temp, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            {
                JsonSerializer.Serialize(stream, data, Options);
                stream.Flush(true);
            }
            File.Move(temp, target, true);
        }
        finally { if (File.Exists(temp)) File.Delete(temp); }
    }
}
