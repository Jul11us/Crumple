using Avalonia.Threading;
using Crumple.Core;
using Crumple.Desktop.Platform;
using static Crumple.Desktop.Model.Strings;

namespace Crumple.Desktop.Model;

internal enum Page { Overview, Status, SmartClean, Analysis, LargeFiles, Duplicates, Optimize, Uninstaller, History }
internal enum SmartPhase { Landing, Scanning, Results, Review, Cleaning, Done }
internal enum ListPhase { Landing, Scanning, Results }

internal static class PageInfo
{
    public static string Title(this Page page) => page switch
    {
        Page.Overview => L("概览"),
        Page.Status => L("状态"),
        Page.SmartClean => L("智能清理"),
        Page.Analysis => L("空间分析"),
        Page.LargeFiles => L("大文件"),
        Page.Duplicates => L("重复文件"),
        Page.Optimize => L("优化"),
        Page.Uninstaller => L("应用卸载"),
        _ => L("清理记录"),
    };

    /// A few useful groups, rather than a heading for every tool.
    public static string? Section(this Page page) => page switch
    {
        Page.SmartClean => L("清理与空间"),
        Page.Optimize => L("管理"),
        _ => null,
    };

    public static string Icon(this Page page) => page switch
    {
        Page.Overview => Ui.IconData.LayoutPanelTop,
        Page.Status => Ui.IconData.Activity,
        Page.SmartClean => Ui.IconData.Trash2,
        Page.Analysis => Ui.IconData.ChartColumn,
        Page.LargeFiles => Ui.IconData.File,
        Page.Duplicates => Ui.IconData.Files,
        Page.Optimize => Ui.IconData.SlidersHorizontal,
        Page.Uninstaller => Ui.IconData.LayoutGrid,
        _ => Ui.IconData.History,
    };
}

/// Everything the interface shows. Views read it and redraw when `Changed` fires.
internal sealed partial class AppModel
{
    public event Action? Changed;
    private bool notifyQueued;

    /// Coalesces many changes into one redraw on the next turn of the UI loop.
    public void Notify()
    {
        if (notifyQueued) return;
        notifyQueued = true;
        Dispatcher.UIThread.Post(() => { notifyQueued = false; Changed?.Invoke(); }, DispatcherPriority.Background);
    }

    public Places Places { get; }
    public JsonStore Store { get; }
    public Preferences Preferences { get; }
    public ITrashService Trash { get; }
    public bool Demo => Places.Demo;

    // Navigation
    public Page Page { get; private set; } = Page.Overview;
    public SmartPhase SmartPhase { get; private set; } = SmartPhase.Landing;
    public ListPhase FilesPhase { get; private set; } = ListPhase.Landing;
    public ListPhase DupPhase { get; private set; } = ListPhase.Landing;
    public ListPhase AppsPhase { get; private set; } = ListPhase.Landing;

    // History, disk, Recycle Bin
    public List<CleanupReceipt> History { get; private set; }
    public DiskInfo? Disk { get; private set; }
    public long? TrashSize { get; private set; }
    public DateTimeOffset? LastSmartScan { get; private set; }
    public long SessionFreed { get; private set; }
    public bool IsCleaning { get; private set; }

    public AppModel(string? demoHome)
    {
        Places = new Places(demoHome);
        Store = new JsonStore(Places.DataDirectory);
        Preferences = Store.Read("settings", () => new Preferences());
        Strings.Load(Preferences.Language);
        Ui.Ink.Palette = PaletteFor(Preferences.Appearance);
        History = Store.Read("history", () => new List<CleanupReceipt>());
        RecoverPending();
        Trash = Demo || !OperatingSystem.IsWindows() ? new DemoTrash(Places.DemoBin) : new WindowsTrash();
        TrashSynced += (bytes, shrank) => Stage.SyncPile(PileCount(bytes), shrank);
        TrashEmptied += Stage.ClearPile;
        RefreshDisk();
    }

    public static Ui.Palette PaletteFor(string appearance) => appearance switch
    {
        "kraft" => Ui.Palette.Kraft,
        "dark" => Ui.Palette.Dark,
        "system" => SystemPrefersDark() ? Ui.Palette.Dark : Ui.Palette.Mist,
        _ => Ui.Palette.Mist,
    };

    private static bool SystemPrefersDark()
    {
        if (!OperatingSystem.IsWindows()) return false;
        using var key = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
        return Convert.ToString(key?.GetValue("AppsUseLightTheme")) == "0";
    }

    public void Go(Page page)
    {
        if (Page == page || IsCleaning) return;
        Page = page;
        Notify();
    }

    /// The basket sits in the corner of every page, except where the page's own picture already shows one.
    public bool ShowsBasket => Page switch
    {
        Page.SmartClean => SmartPhase != SmartPhase.Landing,
        Page.LargeFiles => FilesPhase != ListPhase.Landing,
        Page.Duplicates => DupPhase != ListPhase.Landing,
        Page.Uninstaller => AppsPhase != ListPhase.Landing,
        Page.History => History.Count > 0,
        _ => true,
    };

    public string SourceTitle(ScanKind source) => source switch
    {
        ScanKind.Smart => L("智能清理"),
        ScanKind.Large => L("大文件"),
        ScanKind.Duplicates => L("重复文件"),
        _ => L("手动扔掉"),
    };

    public string SourceIcon(ScanKind source) => source switch
    {
        ScanKind.Smart => Page.SmartClean.Icon(),
        ScanKind.Large => Page.LargeFiles.Icon(),
        ScanKind.Duplicates => Page.Duplicates.Icon(),
        _ => Ui.IconData.Hand,
    };

    // Disk and Recycle Bin

    public void RefreshDisk()
    {
        Disk = DiskInfo.Current(Demo);
        Task.Run(() => Demo || !OperatingSystem.IsWindows() ? FolderSize(Places.DemoBin) : Native.RecycleBinBytes())
            .ContinueWith(t => Dispatcher.UIThread.Post(() =>
            {
                var previous = TrashSize;
                TrashSize = t.IsCompletedSuccessfully ? t.Result : null;
                if (TrashSize is { } size) TrashSynced?.Invoke(size, size < (previous ?? long.MaxValue));
                Notify();
            }));
        Notify();
    }

    /// Lets the basket keep its pile in step with what is really in the Recycle Bin.
    public event Action<long, bool>? TrashSynced;

    private static long? FolderSize(string path)
    {
        try
        {
            return !Directory.Exists(path) ? 0 : new DirectoryInfo(path)
                .EnumerateFiles("*", SearchOption.AllDirectories).Sum(x => x.Length);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { return null; }
    }

    /// How many balls show in the basket for what is in the bin: a few for a little, more as it grows.
    public static int PileCount(long bytes)
    {
        if (bytes <= 0) return 0;
        var megabytes = bytes / 1_000_000.0;
        return Math.Min(30, 1 + (int)Math.Round(Math.Log2(megabytes + 1) * 1.6));
    }

    public void SaveSettings() => Store.Write("settings", Preferences);
}
