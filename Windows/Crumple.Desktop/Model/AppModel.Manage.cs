using Avalonia.Threading;
using Crumple.Desktop.Platform;
using static Crumple.Desktop.Model.Strings;

namespace Crumple.Desktop.Model;

internal enum AppFilter { All, Large, PerUser }

internal sealed record MaintenanceTask(string Id, string Title, string Detail, string Icon, string Target, string? Arguments = null, bool NeedsAdmin = false);

/// Uninstalling, startup apps and Windows' own maintenance tools.
internal sealed partial class AppModel
{
    private SpaceAnalyzer? analyzer;
    private SystemMonitor? monitor;
    public SpaceAnalyzer Analyzer => analyzer ??= new SpaceAnalyzer(this);
    public SystemMonitor Monitor => monitor ??= new SystemMonitor(this);

    public AppFilter AppFilter { get; set; } = AppFilter.All;
    public string? FocusedApp { get; set; }
    public HashSet<string> Uninstalling { get; } = [];
    public List<StartupItem> StartupItems { get; private set; } = [];

    public IEnumerable<InstalledApp> FilteredApps => AppFilter switch
    {
        AppFilter.Large => Apps.Where(x => x.Bytes >= 500_000_000),
        AppFilter.PerUser => Apps.Where(x => x.PerUser),
        _ => Apps,
    };

    public static string Key(InstalledApp app) => app.Name + "|" + app.Version;

    public void ScanApps()
    {
        if (IsCleaning || AppsPhase == ListPhase.Scanning) return;
        var previous = AppsPhase;
        AppsPhase = ListPhase.Scanning;
        Notify();
        var cancel = new CancellationTokenSource();
        listScans[Page.Uninstaller] = (cancel, previous);
        var started = DateTime.UtcNow;
        Task.Run(() => OperatingSystem.IsWindows() && !Demo ? Native.InstalledApps() : DemoApps(), cancel.Token).ContinueWith(async t =>
        {
            var remaining = 1.4 - (DateTime.UtcNow - started).TotalSeconds;
            if (remaining > 0) await Task.Delay(TimeSpan.FromSeconds(remaining));
            Dispatcher.UIThread.Post(() =>
            {
                if (cancel.IsCancellationRequested) return;
                listScans.Remove(Page.Uninstaller);
                Apps = t.IsCompletedSuccessfully ? t.Result : [];
                Uninstalling.RemoveWhere(x => Apps.Any(a => Key(a) == x) is false);
                FocusedApp = Apps.FirstOrDefault() is { } first ? Key(first) : null;
                AppsPhase = ListPhase.Results;
                Notify();
            });
        });
    }

    private static List<InstalledApp> DemoApps() =>
    [
        new("Retro Racer", "2.0", "Pixel Garage", 7_300_000_000, "", @"C:\Program Files\Retro Racer", DateTime.Today.AddDays(-400), false),
        new("PixelPaint", "3.2.1", "Example Software", 5_600_000_000, "", @"C:\Program Files\PixelPaint", DateTime.Today.AddDays(-120), false),
        new("Notely", "1.8", "Notely Ltd.", 2_100_000_000, "", @"C:\Users\demo\AppData\Local\Programs\Notely", DateTime.Today.AddDays(-30), true),
        new("Zoom Workplace", "6.2.5", "Zoom Video Communications", 420_000_000, "", @"C:\Users\demo\AppData\Roaming\Zoom", DateTime.Today.AddDays(-12), true),
    ];

    /// Hands the app to its own uninstaller; the list is read again when Crumple comes back to the front.
    public void RequestUninstall(InstalledApp app)
    {
        Confirm(new(L("卸载 %@？", app.Name), L("会打开 %@ 自己的卸载程序，按它的步骤完成。卸载完回到 Crumple，列表会自动更新。", app.Name), L("卸载"), () =>
        {
            Uninstalling.Add(Key(app));
            if (OperatingSystem.IsWindows() && !Demo)
            {
                try { Native.RunUninstaller(app.UninstallCommand); }
                catch (Exception e) when (e is System.ComponentModel.Win32Exception or InvalidOperationException)
                {
                    Uninstalling.Remove(Key(app));
                    ShowToast(L("没能打开 %@ 的卸载程序", app.Name));
                }
            }
            Notify();
        }));
    }

    /// Back from an uninstaller: see what is still installed.
    public void RefreshAfterUninstall()
    {
        if (Uninstalling.Count > 0 && AppsPhase == ListPhase.Results && OperatingSystem.IsWindows() && !Demo)
        {
            var before = Apps.Count;
            Apps = Native.InstalledApps();
            Uninstalling.RemoveWhere(x => Apps.All(a => Key(a) != x));
            if (Apps.Count < before) ShowToast(L("已卸载 %lld 个应用", before - Apps.Count));
            Notify();
        }
    }

    // Startup apps

    public void LoadStartupItems()
    {
        StartupItems = OperatingSystem.IsWindows() && !Demo ? Native.StartupItems() :
        [
            new("PixelPaint Updater", @"C:\Program Files\PixelPaint\Updater.exe --background", true, true),
            new("Notely Sync", @"C:\Users\demo\AppData\Local\Programs\Notely\SyncAgent.exe", true, false),
            new("SecurityHealth", @"%windir%\system32\SecurityHealthSystray.exe", false, true),
        ];
        Notify();
    }

    public void SetStartupItem(StartupItem item, bool enabled)
    {
        if (OperatingSystem.IsWindows() && !Demo) Native.SetStartupItem(item, enabled);
        StartupItems = StartupItems.Select(x => x == item ? x with { Enabled = enabled } : x).ToList();
        Notify();
    }

    public void RequestEndProcess(int pid, string name) =>
        Confirm(new(L("结束 %@？", name), L("没保存的内容会丢失。只在它卡住、没反应时这样做。"), L("结束"), () =>
        {
            try { using var process = System.Diagnostics.Process.GetProcessById(pid); process.Kill(true); }
            catch (Exception e) when (e is ArgumentException or InvalidOperationException or System.ComponentModel.Win32Exception)
            { ShowToast(L("没能结束 %@", name)); }
        }));

    // Maintenance: Windows' own tools, opened where they live.
    public static MaintenanceTask[] Maintenance =>
    [
        new("storage", L("存储感知"), L("让 Windows 自动清理临时文件和回收站里的旧文件。"), Ui.IconData.HardDrive, "ms-settings:storagesense"),
        new("cleanmgr", L("磁盘清理"), L("Windows 自带的清理工具，能清掉更新留下的旧文件。"), Ui.IconData.Sparkles, "cleanmgr.exe"),
        new("defrag", L("优化驱动器"), L("整理机械硬盘、修剪固态硬盘，让读写更快。"), Ui.IconData.ChartColumn, "dfrgui.exe", NeedsAdmin: true),
        new("dns", L("刷新 DNS 缓存"), L("网页打不开或跳到旧地址时试试。"), Ui.IconData.RefreshCw, "ipconfig.exe", "/flushdns"),
        new("update", L("Windows 更新"), L("装上最新的修复和驱动。"), Ui.IconData.ArrowUpRight, "ms-settings:windowsupdate"),
        new("taskmgr", L("任务管理器"), L("看看哪些程序在后台跑、开机时启动了什么。"), Ui.IconData.Activity, "taskmgr.exe"),
    ];

    public Dictionary<string, string> TaskStates { get; } = [];

    public void RunMaintenance(MaintenanceTask task)
    {
        if (!OperatingSystem.IsWindows() || Demo) { TaskStates[task.Id] = "done"; Notify(); return; }
        try
        {
            var start = new System.Diagnostics.ProcessStartInfo(task.Target, task.Arguments ?? "")
                { UseShellExecute = task.Arguments == null, CreateNoWindow = task.Arguments != null };
            using var process = System.Diagnostics.Process.Start(start);
            TaskStates[task.Id] = "done";
        }
        catch (Exception e) when (e is System.ComponentModel.Win32Exception or InvalidOperationException) { TaskStates[task.Id] = "failed"; }
        Notify();
    }
}

internal sealed partial class AppModel
{
    /// The list the current page is showing, for Ctrl+A and Delete.
    private List<Category> CurrentList => Page switch
    {
        Page.SmartClean when SmartPhase == SmartPhase.Review => [CategoryFor(ReviewKind)],
        Page.SmartClean when SmartPhase == SmartPhase.Results => Junk,
        Page.LargeFiles when FilesPhase == ListPhase.Results => [LargeFiles],
        Page.Duplicates when DupPhase == ListPhase.Results => [Duplicates],
        _ => [],
    };

    public bool IsScanning(Page page) => page switch
    {
        Page.SmartClean => SmartPhase == SmartPhase.Scanning,
        Page.LargeFiles => FilesPhase == ListPhase.Scanning,
        Page.Duplicates => DupPhase == ListPhase.Scanning,
        Page.Uninstaller => AppsPhase == ListPhase.Scanning,
        _ => false,
    };

    public void SelectAllInList()
    {
        if (IsCleaning) return;
        foreach (var category in CurrentList) category.SelectAll();
        Notify();
    }

    public void ThrowSelection()
    {
        if (IsCleaning) return;
        switch (Page)
        {
            case Page.SmartClean when SmartPhase is SmartPhase.Results or SmartPhase.Review: RequestSmartClean(); break;
            case Page.LargeFiles: RequestLargeFileClean(); break;
            case Page.Duplicates: RequestDuplicateClean(); break;
        }
    }

    public void Rescan()
    {
        if (IsCleaning || IsScanning(Page)) return;
        switch (Page)
        {
            case Page.SmartClean: StartSmartScan(); break;
            case Page.LargeFiles: ScanLargeFiles(); break;
            case Page.Duplicates: ScanDuplicates(); break;
            case Page.Uninstaller: ScanApps(); break;
            case Page.Analysis: Analyzer.Rescan(); break;
            default: RefreshDisk(); break;
        }
    }
}
