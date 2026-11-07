using Avalonia.Threading;
using static Crumple.Desktop.Model.Strings;

namespace Crumple.Desktop.Model;

/// Breaks a folder down by what's inside it, measuring each child in the background.
internal sealed class SpaceAnalyzer(AppModel model)
{
    public enum Base { Home, Applications }

    public sealed class Entry
    {
        public required string Path { get; init; }
        public required string Name { get; init; }
        public bool IsFolder { get; init; }
        public long? Size { get; set; }
    }

    public Base Root { get; private set; } = Base.Home;
    /// The folders from the base down to the one being shown.
    public List<string> Trail { get; } = [];
    public List<Entry> Entries { get; private set; } = [];
    public int Pending { get; private set; }
    private readonly Dictionary<string, long> cache = new(StringComparer.OrdinalIgnoreCase);
    private int token;

    public string Title(Base root) => root == Base.Home ? L("个人文件夹") : L("应用程序");
    public string BasePath(Base root) => root == Base.Home ? model.Places.Home
        : model.Demo ? System.IO.Path.Combine(model.Places.Home, "Program Files")
        : Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
    public string Current => Trail.Count > 0 ? Trail[^1] : BasePath(Root);
    public long Total => Entries.Sum(x => x.Size ?? 0);

    public void Open(Base root)
    {
        Root = root;
        Trail.Clear();
        Trail.Add(BasePath(root));
        Load();
    }

    public void Open(Entry entry)
    {
        if (!entry.IsFolder) return;
        Trail.Add(entry.Path);
        Load();
    }

    public void GoBack(int index)
    {
        if (index >= Trail.Count - 1) return;
        Trail.RemoveRange(index + 1, Trail.Count - index - 1);
        Load();
    }

    public void Rescan()
    {
        cache.Clear();
        if (Trail.Count == 0) Open(Root); else Load();
    }

    private void Load()
    {
        var mine = ++token;
        var current = Current;
        Directory.CreateDirectory(current);
        // The demo's own bin and marker aren't part of the picture.
        Entries = SafeEntries(current).Where(x => !model.Demo || (x.FullName != model.Places.DemoBin && x.Name != ".demo-ready")).Select(info => new Entry
        {
            Path = info.FullName,
            Name = info.Name,
            IsFolder = info is DirectoryInfo,
            Size = info is FileInfo file ? file.Length : cache.TryGetValue(info.FullName, out var known) ? known : null,
        }).ToList();
        Sort();
        var todo = Entries.Where(x => x.Size == null).ToList();
        Pending = todo.Count;
        model.Notify();
        foreach (var entry in todo)
            Task.Run(() => Measure(entry.Path)).ContinueWith(t => Dispatcher.UIThread.Post(() =>
            {
                if (mine != token) return;
                entry.Size = t.IsCompletedSuccessfully ? t.Result : 0;
                cache[entry.Path] = entry.Size.Value;
                Pending--;
                if (Pending == 0) Sort();
                model.Notify();
            }));
    }

    private void Sort() => Entries = Entries.OrderByDescending(x => x.Size ?? -1)
        .ThenBy(x => x.Name, StringComparer.CurrentCultureIgnoreCase).ToList();

    private static IEnumerable<FileSystemInfo> SafeEntries(string path)
    {
        try
        {
            return new DirectoryInfo(path).EnumerateFileSystemInfos()
                .Where(x => (x.Attributes & (FileAttributes.ReparsePoint | FileAttributes.System)) == 0).ToList();
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { return []; }
    }

    /// Adds up a folder without following links (junctions and symbolic links would count things twice).
    private static long Measure(string path)
    {
        long total = 0;
        var options = new EnumerationOptions { RecurseSubdirectories = true, IgnoreInaccessible = true, AttributesToSkip = FileAttributes.ReparsePoint };
        try { foreach (var file in new DirectoryInfo(path).EnumerateFiles("*", options)) total += file.Length; }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
        return total;
    }
}
