using Crumple.Core;
using Crumple.Desktop.Platform;
using static Crumple.Desktop.Model.Strings;

namespace Crumple.Desktop.Model;

/// Where Crumple looks and keeps its data. In demo mode everything lives in a sandbox full of fake files,
/// so the paper can be thrown around safely (and the interface can be previewed on a Mac).
internal sealed class Places
{
    public string Home { get; }
    public string Local { get; }
    public string Roaming { get; }
    public string Downloads { get; }
    public string DataDirectory { get; }
    public bool Demo { get; }
    public List<string> PersonalFolders { get; }
    /// The demo's stand-in for the Recycle Bin.
    public string DemoBin => Path.Combine(Home, "PaperBin");

    public Places(string? demoHome)
    {
        Demo = demoHome != null;
        Home = demoHome ?? Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        Local = Demo ? Path.Combine(Home, "AppData", "Local") : Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        Roaming = Demo ? Path.Combine(Home, "AppData", "Roaming") : Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        Downloads = Demo || !OperatingSystem.IsWindows() ? Path.Combine(Home, "Downloads")
            : Native.KnownFolder(new("374DE290-123F-4565-9164-39C4925E467B"), Path.Combine(Home, "Downloads"));
        DataDirectory = Path.Combine(Local, "Crumple");
        PersonalFolders = Demo
            ? new[] { "Desktop", "Documents", "Downloads", "Pictures", "Music", "Videos" }.Select(x => Path.Combine(Home, x)).ToList()
            : new[] { Environment.SpecialFolder.DesktopDirectory, Environment.SpecialFolder.MyDocuments, Environment.SpecialFolder.MyPictures,
                Environment.SpecialFolder.MyMusic, Environment.SpecialFolder.MyVideos }.Select(Environment.GetFolderPath).Append(Downloads)
                .Where(x => !string.IsNullOrEmpty(x)).Distinct(PathPolicy.Comparer).ToList();
        if (Demo) DemoFiles.Create(this);
    }

    /// The smart clean's places, each in one of the six groups shown on the results page.
    public List<ScanLocation> Locations(int oldDownloadDays)
    {
        var list = new List<ScanLocation>
        {
            new(Path.Combine(Local, "Temp"), FileCategory.Temporary, true, 7),
            new(Path.Combine(Local, "CrashDumps"), FileCategory.Logs, true, 7),
            new(Path.Combine(Local, "Microsoft", "Windows", "WER", "ReportArchive"), FileCategory.Logs, true, 7),
            new(Path.Combine(Local, "Microsoft", "Windows", "WER", "ReportQueue"), FileCategory.Logs, true, 7),
            new(Path.Combine(Local, "npm-cache", "_cacache"), FileCategory.DeveloperCache, true, 7, ["node"]),
            new(Path.Combine(Roaming, "npm-cache", "_cacache"), FileCategory.DeveloperCache, true, 7, ["node"]),
            new(Path.Combine(Home, ".npm", "_cacache"), FileCategory.DeveloperCache, true, 7, ["node"]),
            new(Path.Combine(Local, "pip", "Cache"), FileCategory.DeveloperCache, true, 7, ["python", "pythonw", "pip"]),
            new(Path.Combine(Local, "NuGet", "v3-cache"), FileCategory.DeveloperCache, true, 7, ["dotnet", "devenv", "MSBuild"]),
            new(Path.Combine(Local, "Yarn", "Cache"), FileCategory.DeveloperCache, true, 7, ["node"]),
            new(Path.Combine(Home, ".gradle", "caches"), FileCategory.DeveloperCache, true, 14, ["java", "javaw", "gradle"]),
            new(Path.Combine(Home, ".cargo", "registry", "cache"), FileCategory.DeveloperCache, true, 7, ["cargo", "rustc"]),
            new(Downloads, FileCategory.Installers, false, 0, TopLevelOnly: true),
            new(Downloads, FileCategory.OldDownloads, false, oldDownloadDays, TopLevelOnly: true),
        };
        list.AddRange(AILocations());
        foreach (var (baseDir, owner) in new[] {
            (Path.Combine(Local, "Google", "Chrome", "User Data"), "chrome"),
            (Path.Combine(Local, "Microsoft", "Edge", "User Data"), "msedge"),
            (Path.Combine(Local, "BraveSoftware", "Brave-Browser", "User Data"), "brave") })
        {
            foreach (var profile in Children(baseDir).Where(x => Path.GetFileName(x) == "Default" || Path.GetFileName(x).StartsWith("Profile ", StringComparison.Ordinal)))
                foreach (var cache in new[] { "Cache", "Code Cache", "GPUCache" })
                    list.Add(new(Path.Combine(profile, cache), FileCategory.BrowserCache, true, 1, [owner]));
        }
        foreach (var profile in Children(Path.Combine(Local, "Mozilla", "Firefox", "Profiles")))
            list.Add(new(Path.Combine(profile, "cache2"), FileCategory.BrowserCache, true, 1, ["firefox"]));
        return list;
    }

    /// Cache subfolders Electron and VS Code-based apps rebuild on their own.
    private static readonly string[] ElectronCaches =
        ["Cache", "Code Cache", "GPUCache", "DawnWebGPUCache", "DawnGraphiteCache", "GraphiteDawnCache", "DawnCache", "ShaderCache", "CachedData", "CachedExtensionVSIXs"];

    /// What AI tools leave behind. Caches are ticked; runtimes and models are only listed, with a note saying why.
    /// Conversations are never offered: anything touching `AIConversations.Stores` is dropped.
    private List<ScanLocation> AILocations()
    {
        var list = new List<ScanLocation>();
        foreach (var (folder, owners) in new (string, string[])[] { (Path.Combine(Roaming, "Claude"), ["Claude", "claude"]),
            (Path.Combine(Roaming, "Cursor"), ["Cursor"]), (Path.Combine(Roaming, "Windsurf"), ["Windsurf"]) })
            foreach (var cache in ElectronCaches)
                list.Add(new(Path.Combine(folder, cache), FileCategory.AITools, true, 1, owners));
        string[] codex = ["Codex", "codex"], claude = ["claude"];
        list.Add(new(Path.Combine(Home, ".claude", "cache"), FileCategory.AITools, true, 1, claude));
        list.Add(new(Path.Combine(Home, ".claude", "shell-snapshots"), FileCategory.AITools, true, 1, claude));
        list.Add(new(Path.Combine(Home, ".claude", "telemetry"), FileCategory.AITools, true, 1, claude));
        list.Add(new(Path.Combine(Home, ".codex", "cache"), FileCategory.AITools, true, 1, codex));
        list.Add(new(Path.Combine(Home, ".codex", ".tmp"), FileCategory.AITools, true, 1, codex));
        list.Add(new(Path.Combine(Home, ".codex", "shell_snapshots"), FileCategory.AITools, true, 1, codex));
        list.Add(new(Path.Combine(Home, ".codex", "plugins", "cache"), FileCategory.AITools, true, 1, codex));
        list.Add(new(Path.Combine(Home, ".cache", "codex-runtimes"), FileCategory.AITools, false, 0, codex, Badge: L("删后需重新下载")));
        list.Add(new(Path.Combine(Home, ".ollama", "models"), FileCategory.AITools, false, 0, ["ollama", "ollama app"], Badge: L("删后需重新下载")));
        list.Add(new(Path.Combine(Home, ".lmstudio", "models"), FileCategory.AITools, false, 0, ["LM Studio"], Badge: L("删后需重新下载")));
        var stores = AIConversations.Stores(Home, Roaming);
        list.RemoveAll(x => AIConversations.Touches(x.Path, stores));
        return list;
    }

    /// The row's label for an AI tool's folder: what it is.
    public static string AIToolLabel(ScanLocation location) => Path.GetFileName(location.Path) switch
    {
        "cache" => L("缓存"), ".tmp" => L("临时文件"), "shell-snapshots" or "shell_snapshots" => L("终端快照"),
        "telemetry" => L("遥测日志"), "codex-runtimes" => L("运行时"), "models" => L("模型文件"),
        var name => ElectronCaches.Contains(name) ? L("应用缓存") : name,
    };

    public static IEnumerable<string> Children(string path)
    {
        try { return Directory.GetDirectories(path); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { return []; }
    }

    /// Where cleaning may act: the scanned places, minus the ignore list, Crumple's own data and the system folders.
    public PathPolicy Policy(IEnumerable<string> ignored, IEnumerable<string> extraFolders, int oldDownloadDays, string? analysisFolder = null)
    {
        var protectedFolders = Demo ? [] : new[] { Environment.SpecialFolder.Windows,
            Environment.SpecialFolder.ProgramFiles, Environment.SpecialFolder.ProgramFilesX86, Environment.SpecialFolder.CommonApplicationData }
            .Select(Environment.GetFolderPath).Where(x => !string.IsNullOrEmpty(x)).ToArray();
        var roots = PersonalFolders.Concat(Locations(oldDownloadDays).Select(x => x.Path)).Concat(extraFolders);
        if (analysisFolder != null) roots = roots.Append(analysisFolder);
        return new(roots, ignored.Append(DataDirectory).Append(DemoBin)
            .Append(Environment.ProcessPath ?? Path.Combine(DataDirectory, "Crumple.exe")), protectedFolders);
    }

    /// Short form for display: "~\Downloads\…" inside the user folder.
    public string Display(string path)
    {
        var home = PathPolicy.Normalize(Home);
        var full = PathPolicy.Normalize(path);
        return PathPolicy.IsBelow(full, home) && full.Length > home.Length ? "~" + full[home.Length..] : full;
    }
}

/// The demo's stand-in for the Recycle Bin: a folder inside the sandbox.
internal sealed class DemoTrash(string root) : ITrashService
{
    public TrashRecord Recycle(CleanItem item)
    {
        Directory.CreateDirectory(root);
        var target = Path.Combine(root, Guid.NewGuid().ToString("N") + "-" + item.Name);
        File.Move(item.Path, target);
        return new(item.Path, target, item.Stamp);
    }

    public bool Restore(TrashRecord record)
    {
        if (!PathPolicy.IsBelow(PathPolicy.Normalize(record.RecycledPath), PathPolicy.Normalize(root))
            || PathPolicy.HasUnsafeAncestor(record.RecycledPath) || !record.Stamp.Matches(record.RecycledPath)) return false;
        Directory.CreateDirectory(Path.GetDirectoryName(record.Original)!);
        File.Move(record.RecycledPath, record.Original, false);
        return true;
    }
}

/// The same fake files as the Mac version's demo, laid out the Windows way.
internal static class DemoFiles
{
    public static void Create(Places places)
    {
        var marker = Path.Combine(places.Home, ".demo-ready");
        if (File.Exists(marker)) return;
        foreach (var dir in places.PersonalFolders) Directory.CreateDirectory(dir);
        var random = new Random(2024);

        void Make(string relative, int kilobytes, int ageDays = 30, int? seed = null)
        {
            var path = Path.Combine(places.Home, relative.Replace('/', Path.DirectorySeparatorChar));
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            var data = new byte[kilobytes * 1024];
            if (seed is { } s) new Random(s).NextBytes(data);
            File.WriteAllBytes(path, data);
            File.SetLastWriteTimeUtc(path, DateTime.UtcNow.AddDays(-ageDays));
            File.SetLastAccessTimeUtc(path, DateTime.UtcNow.AddDays(-ageDays));
        }
        void Folder(string relative, int kilobytes, int ageDays = 30)
        {
            int[] parts = [kilobytes / 2, kilobytes / 3, kilobytes - kilobytes / 2 - kilobytes / 3];
            for (var i = 0; i < parts.Length; i++) Make($"{relative}/blob-{i}.bin", parts[i], ageDays);
        }

        // Smart clean: temporary files, browser and developer caches, crash reports.
        Folder("AppData/Local/Temp/WinGet", 4_200);
        Folder("AppData/Local/Temp/chrome_installer", 2_600);
        Folder("AppData/Local/Temp/Teams-update", 3_100);
        Make("AppData/Local/Temp/~DF3A1B.tmp", 900);
        Make("AppData/Local/Temp/setup-log-2024.txt", 300);
        Folder("AppData/Local/Google/Chrome/User Data/Default/Cache", 9_000, 3);
        Folder("AppData/Local/Google/Chrome/User Data/Default/Code Cache", 2_400, 3);
        Folder("AppData/Local/Microsoft/Edge/User Data/Default/Cache", 3_200, 3);
        Folder("AppData/Local/Mozilla/Firefox/Profiles/x7k2.default-release/cache2", 2_100, 3);
        Folder("AppData/Local/CrashDumps", 450, 14);
        Folder("AppData/Local/Microsoft/Windows/WER/ReportArchive/AppCrash_Zoom", 700, 14);
        Folder("AppData/Local/npm-cache/_cacache", 2_700);
        Folder("AppData/Local/pip/Cache", 950);
        Folder("AppData/Local/NuGet/v3-cache", 1_600);
        Folder(".gradle/caches", 1_600, 30);
        // AI tools: a desktop app's web caches, a CLI's cache and runtime, and conversations, which the scan must leave out.
        Folder("AppData/Roaming/Claude/Cache", 1_800, 3);
        Folder("AppData/Roaming/Claude/Code Cache", 600, 3);
        Folder(".claude/cache", 120, 3);
        Folder(".claude/projects/C--Users-demo-Documents", 900, 10);
        Folder(".codex/cache", 300, 3);
        Folder(".codex/sessions", 450, 10);
        Folder(".cache/codex-runtimes", 2_200, 10);
        Make("Downloads/Figma-Setup.exe", 2_400, 10);
        Make("Downloads/Zoom-Installer.msi", 1_900, 10);
        Make("Downloads/2023-年度报告.pdf", 550, 200);

        // Large files (the demo uses a 1 MB threshold).
        foreach (var (path, kb, age) in new[] {
            ("Videos/2024 旅行 4K.mov", 6_400, 3), ("Videos/录屏 2023-11-02.mp4", 3_100, 200),
            ("Desktop/项目备份.zip", 4_200, 20), ("Documents/设计稿 v12.psd", 2_700, 40),
            ("Downloads/ubuntu-24.04-desktop.iso", 5_200, 60), ("Music/现场录音.wav", 1_800, 90),
            ("Documents/年度报告 终稿.pdf", 1_300, 12) })
            Make(path, kb, age);

        // Identical files under different names, each set with its own contents.
        foreach (var (kb, paths) in new (int, string[])[] {
            (2_300, ["Pictures/IMG_2041.jpg", "Downloads/IMG_2041 (1).jpg", "Desktop/IMG_2041 副本.jpg"]),
            (3_600, ["Videos/婚礼剪辑.mp4", "Desktop/婚礼剪辑 最终.mp4"]),
            (900, ["Documents/租房合同.pdf", "Downloads/租房合同.pdf"]),
            (1_400, ["Music/demo-混音.m4a", "Downloads/demo-混音 copy.m4a"]),
            (600, ["Pictures/截图 2024-05-12.png", "Desktop/截图 2024-05-12.png"]) })
        {
            var seed = random.Next();
            foreach (var path in paths) Make(path, kb, 20, seed);
        }

        // A little history so the 清理记录 page has something to show.
        var store = new JsonStore(places.DataDirectory);
        CleanupReceipt Receipt(int daysAgo, ScanKind source, int count, long bytes, int failed)
        {
            var each = bytes / count;
            var receipt = new CleanupReceipt { Date = DateTimeOffset.Now.AddDays(-daysAgo), Source = source };
            for (var i = 0; i < count; i++)
                receipt.Files.Add(new($"demo-{i}", Path.Combine(places.DemoBin, "gone", $"{i}"), new(each, DateTime.UtcNow, DateTime.UtcNow)));
            for (var i = 0; i < failed; i++) receipt.Errors.Add("demo\nIn use");
            return receipt;
        }
        store.Write("history", new List<CleanupReceipt> {
            Receipt(1, ScanKind.Smart, 18, 640_000_000, 2),
            Receipt(2, ScanKind.Manual, 1, 120_000_000, 0),
            Receipt(4, ScanKind.Large, 3, 6_200_000_000, 0),
            Receipt(6, ScanKind.Smart, 42, 1_850_000_000, 1),
        });
        // Something already in the bin, so the basket isn't empty.
        Make("PaperBin/old-notes.txt", 75_000);
        File.WriteAllText(marker, "");
    }
}
