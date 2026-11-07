using Avalonia;
using Avalonia.Threading;
using Crumple.Core;
using Crumple.Desktop.Art;
using Crumple.Desktop.Platform;
using static Crumple.Desktop.Model.Strings;

namespace Crumple.Desktop.Model;

internal enum FileSort { Size, Oldest }

/// What one cleaning run did, for the done page, the list banner and the receipt.
internal sealed class CleanSummary
{
    public ScanKind Source { get; init; }
    public int Count { get; set; }
    public long Bytes { get; set; }
    public List<(string Name, string Reason)> Failures { get; } = [];
    public Dictionary<CategoryKind, (int Count, long Bytes)> Lines { get; } = [];
    public DateTimeOffset Started { get; } = DateTimeOffset.Now;
    public DateTimeOffset Finished { get; set; } = DateTimeOffset.Now;
    public string? ReceiptId { get; set; }
    public bool TrashEmptied { get; set; }
    public double Seconds => Math.Max(1, (Finished - Started).TotalSeconds);
}

internal sealed partial class AppModel
{
    public PaperStage Stage { get; } = new();
    public HashSet<CategoryKind> Revealed { get; } = [];
    public CategoryKind ReviewKind { get; set; } = CategoryKind.Temporary;
    public DateTimeOffset ResultsShownAt { get; private set; } = DateTimeOffset.Now;
    public int FilesChecked { get; private set; }
    public string DupProgress { get; private set; } = "";
    public FileTag? FileFilter { get; set; }
    public FileSort FileSort { get; set; } = FileSort.Size;

    public CategoryKind? CleaningKind { get; private set; }
    public int CleanDone { get; private set; }
    public int CleanTotal { get; private set; }
    public CleanSummary? LastSummary { get; private set; }
    public DateTimeOffset DoneAt { get; private set; } = DateTimeOffset.Now;
    public CleanSummary? Banner { get; set; }
    /// Short message shown above the basket when a paper bounces off.
    public string? BasketNote { get; private set; }

    /// Where each row's icon sits in the window, so its paper can start from there.
    public Dictionary<string, Rect> IconFrames { get; } = [];
    public Rect ListViewport { get; set; }

    private CancellationTokenSource? smartScan;
    private readonly Dictionary<Page, (CancellationTokenSource Cancel, ListPhase Previous)> listScans = [];
    private int noteToken;

    private PathPolicy Policy() => Places.Policy(Preferences.IgnoredPaths, Preferences.ExtraFolders, Preferences.OldDownloadDays);
    private IEnumerable<string> ScanFolders => Places.PersonalFolders.Concat(Preferences.ExtraFolders).Distinct(PathPolicy.Comparer);
    private Func<string, string?>? FileIdentity => OperatingSystem.IsWindows() ? Native.FileIdentity : null;

    public static bool IsRunning(string[] names)
    {
        foreach (var name in names)
        {
            var processes = System.Diagnostics.Process.GetProcessesByName(name);
            try { if (processes.Length > 0) return true; }
            finally { foreach (var p in processes) p.Dispose(); }
        }
        return false;
    }

    public Category CategoryFor(CategoryKind kind) => kind switch
    {
        CategoryKind.LargeFiles => LargeFiles,
        CategoryKind.Duplicates => Duplicates,
        _ => Junk.First(x => x.Kind == kind),
    };

    public long JunkSelectedBytes => Junk.Sum(x => x.SelectedBytes);
    public int JunkSelectedCount => Junk.Sum(x => x.SelectedRows.Count());
    public long RevealedBytes => Junk.Where(x => Revealed.Contains(x.Kind)).Sum(x => x.TotalBytes);
    public double ScanProgress => (double)Revealed.Count / CategoryInfo.Junk.Length;
    public int DuplicateGroups => Duplicates.Live.Select(x => x.Keeper).Distinct().Count();

    /// The rows a list shows, after the page's filter and sort. While cleaning, only the queue.
    public List<CleanRow> VisibleRows(Category category)
    {
        if (CleaningKind == category.Kind) return category.Rows.Where(x => x.Selected && x.Status == RowStatus.Ready).ToList();
        var rows = category.Live;
        if (category.Kind == CategoryKind.LargeFiles)
        {
            if (FileFilter is { } tag) rows = rows.Where(x => x.Tag == tag);
            rows = FileSort == FileSort.Oldest ? rows.OrderBy(x => x.LastUsed) : rows.OrderByDescending(x => x.Size);
        }
        return rows.ToList();
    }

    // MARK: Smart clean

    public void StartSmartScan()
    {
        if (IsCleaning) return;
        smartScan?.Cancel();
        var cancel = smartScan = new CancellationTokenSource();
        LastSummary = null;
        Page = Page.SmartClean;
        SmartPhase = SmartPhase.Scanning;
        Revealed.Clear();
        foreach (var category in Junk) { category.Rows = []; category.Scanning = true; }
        Notify();

        var locations = Places.Locations(Preferences.OldDownloadDays);
        var policy = Policy();
        var scanner = new Scanner(policy);
        foreach (var category in Junk)
        {
            var mine = locations.Where(x => CategoryInfo.From(x.Category) == category.Kind).ToList();
            Task.Run(() => SmartRows(scanner, mine, cancel.Token), cancel.Token).ContinueWith(t => Dispatcher.UIThread.Post(() =>
            {
                if (cancel.IsCancellationRequested) return;
                category.Rows = t.IsCompletedSuccessfully ? t.Result : [];
                category.Scanning = false;
            }));
        }
        // Reveal the groups one by one, so the scan reads as a sequence even when it is quick.
        _ = RevealInTurn(cancel);
    }

    private async Task RevealInTurn(CancellationTokenSource cancel)
    {
        await Task.Delay(500);
        foreach (var category in Junk)
        {
            while (category.Scanning && !cancel.IsCancellationRequested) await Task.Delay(80);
            if (cancel.IsCancellationRequested) return;
            Revealed.Add(category.Kind);
            Notify();
            await Task.Delay(320);
        }
        await Task.Delay(450);
        if (cancel.IsCancellationRequested) return;
        LastSmartScan = DateTimeOffset.Now;
        ResultsShownAt = DateTimeOffset.Now;
        SmartPhase = SmartPhase.Results;
        RefreshDisk();
        Notify();
    }

    /// Smart clean rows: a cache folder is one row; temporary files are grouped by their top folder; downloads are one row each.
    private List<CleanRow> SmartRows(Scanner scanner, List<ScanLocation> locations, CancellationToken token)
    {
        var rows = new Dictionary<string, (ScanLocation Location, List<CleanItem> Files)>(PathPolicy.Comparer);
        foreach (var location in locations)
        {
            if (!Directory.Exists(location.Path)) continue;
            var result = scanner.Smart([location], ScanFolders, Preferences, IsRunning, null, token);
            foreach (var item in result.Items)
            {
                if (IgnoreListContains(item.Path)) continue;
                var key = location.Category switch
                {
                    FileCategory.BrowserCache or FileCategory.DeveloperCache => location.Path,
                    FileCategory.Installers or FileCategory.OldDownloads => item.Path,
                    _ => Path.Combine(location.Path, Path.GetRelativePath(location.Path, item.Path).Split(Path.DirectorySeparatorChar)[0]),
                };
                if (!rows.TryGetValue(key, out var row)) rows[key] = row = (location, []);
                row.Files.Add(item);
            }
        }
        return rows.Select(pair =>
        {
            var (location, files) = pair.Value;
            var owners = location.OwnerProcesses ?? [];
            var running = owners.Length > 0 && IsRunning(owners);
            var isFile = files.Count == 1 && PathPolicy.Comparer.Equals(files[0].Path, pair.Key);
            var detail = isFile
                ? $"{Places.Display(Path.GetDirectoryName(pair.Key)!)} · {Format.Ago(new DateTimeOffset(files[0].Stamp.LastWriteUtc))}"
                : $"{Places.Display(pair.Key)} · {L("%lld 个文件", files.Count)}";
            return new CleanRow
            {
                Id = pair.Key,
                Name = RowName(location, pair.Key),
                Detail = detail,
                Path = pair.Key,
                Files = files,
                Selected = !running && files.Any(x => x.Selected),
                Badge = running ? L("运行中") : null,
                LastUsed = files.Max(x => x.Stamp.LastWriteUtc),
            };
        }).OrderByDescending(x => x.Size).ToList();
    }

    private static string RowName(ScanLocation location, string key)
    {
        var path = location.Path.Replace('\\', '/');
        string? app = path.Contains("Google/Chrome") ? "Chrome" : path.Contains("Microsoft/Edge") ? "Edge"
            : path.Contains("Brave-Browser") ? "Brave" : path.Contains("Firefox") ? "Firefox"
            : path.Contains("npm") ? "npm" : path.Contains("/pip/") ? "pip" : path.Contains("NuGet") ? "NuGet"
            : path.Contains("Yarn") ? "Yarn" : path.Contains(".gradle") ? "Gradle" : path.Contains(".cargo") ? "Cargo" : null;
        return location.Category switch
        {
            FileCategory.BrowserCache => $"{app} · {Path.GetFileName(location.Path)}",
            FileCategory.DeveloperCache => L("%@ 缓存", app ?? Path.GetFileName(location.Path)),
            _ => Path.GetFileName(key),
        };
    }

    public void CancelSmartScan()
    {
        smartScan?.Cancel();
        foreach (var category in Junk) category.Scanning = false;
        SmartPhase = LastSmartScan == null ? SmartPhase.Landing : SmartPhase.Results;
        Notify();
    }

    public void ShowSmartResults()
    {
        if (LastSmartScan == null) { StartSmartScan(); return; }
        ResultsShownAt = DateTimeOffset.Now;
        Page = Page.SmartClean;
        SmartPhase = SmartPhase.Results;
        Notify();
    }

    public void OpenReview(CategoryKind? kind = null)
    {
        if (kind is { } k) ReviewKind = k;
        SmartPhase = SmartPhase.Review;
        Notify();
    }

    public void BackToResults() { ResultsShownAt = DateTimeOffset.Now; SmartPhase = SmartPhase.Results; Notify(); }
    public void FinishSmartClean() { SmartPhase = SmartPhase.Landing; Notify(); }

    public void RequestSmartClean()
    {
        var work = Junk.Where(x => x.SelectedRows.Any()).ToList();
        if (IsCleaning || work.Count == 0) return;
        StartCleaning(work, ScanKind.Smart);
    }

    // MARK: Large files and duplicates

    public void ScanLargeFiles()
    {
        if (IsCleaning || FilesPhase == ListPhase.Scanning) return;
        Banner = null;
        FilesChecked = 0;
        var previous = FilesPhase;
        FilesPhase = ListPhase.Scanning;
        LargeFiles.Scanning = true;
        Notify();
        var minBytes = Demo ? 1_000_000L : Preferences.LargeFileMegabytes * 1_000_000L;
        var cancel = new CancellationTokenSource();
        listScans[Page.LargeFiles] = (cancel, previous);
        var progress = new Progress<ScanProgress>(p => { FilesChecked = p.Files; Notify(); });
        var scanner = new Scanner(Policy());
        RunScan(Page.LargeFiles, cancel, () => scanner.Large(ScanFolders, minBytes, progress, cancel.Token).Items
            .Where(x => !IgnoreListContains(x.Path)).Select(FileRow).ToList(), rows =>
        {
            FileFilter = null;
            LargeFiles.Rows = rows;
            LargeFiles.Scanning = false;
            FilesPhase = ListPhase.Results;
        });
    }

    private CleanRow FileRow(CleanItem item)
    {
        var lastUsed = item.Stamp.LastWriteUtc;
        try { lastUsed = new[] { lastUsed, File.GetLastAccessTimeUtc(item.Path) }.Max(); } catch (IOException) { }
        return new CleanRow
        {
            Id = item.Path,
            Name = item.Name,
            Detail = L("%@ · %@打开过", Places.Display(Path.GetDirectoryName(item.Path)!), Format.Ago(new DateTimeOffset(lastUsed))),
            Path = item.Path,
            Files = [item],
            Tag = CategoryInfo.TagOf(item.Path),
            LastUsed = lastUsed,
            Badge = DateTime.UtcNow - lastUsed > TimeSpan.FromDays(180) ? L("半年没打开") : null,
        };
    }

    public void ScanDuplicates()
    {
        if (IsCleaning || DupPhase == ListPhase.Scanning) return;
        Banner = null;
        DupProgress = L("正在列出文件…");
        var previous = DupPhase;
        DupPhase = ListPhase.Scanning;
        Duplicates.Scanning = true;
        Notify();
        var minBytes = Demo ? 50_000L : Preferences.DuplicateMinKilobytes * 1024L;
        var cancel = new CancellationTokenSource();
        listScans[Page.Duplicates] = (cancel, previous);
        var progress = new Progress<ScanProgress>(p => { DupProgress = L("已检查 %@ 个文件", p.Files.ToString("N0")); Notify(); });
        var scanner = new Scanner(Policy(), FileIdentity);
        RunScan(Page.Duplicates, cancel, () => scanner.Duplicates(ScanFolders, minBytes, progress, cancel.Token).Items
            .Where(x => !IgnoreListContains(x.Path)).Select(item => new CleanRow
            {
                Id = item.Path,
                Name = item.Name,
                Detail = L("%@ · 和 %@ 一样", Places.Display(Path.GetDirectoryName(item.Path)!), Places.Display(item.Keeper!)),
                Path = item.Path,
                Files = [item],
                Selected = true,
                Keeper = item.Keeper,
                LastUsed = item.Stamp.LastWriteUtc,
            }).ToList(), rows =>
        {
            Duplicates.Rows = rows;
            Duplicates.Scanning = false;
            DupPhase = ListPhase.Results;
        });
    }

    /// Runs a page's scan in the background, keeps the scanning screen up for at least a moment, then shows the rows.
    private void RunScan(Page page, CancellationTokenSource cancel, Func<List<CleanRow>> work, Action<List<CleanRow>> done)
    {
        var started = DateTime.UtcNow;
        Task.Run(work, cancel.Token).ContinueWith(async t =>
        {
            var remaining = 1.4 - (DateTime.UtcNow - started).TotalSeconds;
            if (remaining > 0) await Task.Delay(TimeSpan.FromSeconds(remaining));
            Dispatcher.UIThread.Post(() =>
            {
                if (cancel.IsCancellationRequested) return;
                listScans.Remove(page);
                done(t.IsCompletedSuccessfully ? t.Result : []);
                Notify();
            });
        });
    }

    /// Calls off a page's scan and goes back to what was on the page before it.
    public void CancelScan(Page page)
    {
        if (page == Page.SmartClean) { CancelSmartScan(); return; }
        if (!listScans.Remove(page, out var scan)) return;
        scan.Cancel.Cancel();
        var back = scan.Previous == ListPhase.Results ? ListPhase.Results : ListPhase.Landing;
        if (page == Page.LargeFiles) { LargeFiles.Scanning = false; FilesPhase = back; }
        if (page == Page.Duplicates) { Duplicates.Scanning = false; DupPhase = back; }
        if (page == Page.Uninstaller) AppsPhase = back;
        Notify();
    }

    public void RequestLargeFileClean() { if (!IsCleaning && LargeFiles.SelectedRows.Any()) StartCleaning([LargeFiles], ScanKind.Large); }
    public void RequestDuplicateClean() { if (!IsCleaning && Duplicates.SelectedRows.Any()) StartCleaning([Duplicates], ScanKind.Duplicates); }

    // MARK: Cleaning

    private void StartCleaning(List<Category> work, ScanKind source)
    {
        IsCleaning = true;
        Banner = null;
        CleanDone = 0;
        CleanTotal = work.Sum(x => x.SelectedRows.Count());
        if (source == ScanKind.Smart) SmartPhase = SmartPhase.Cleaning;
        Notify();
        _ = RunCleaning(work, source);
    }

    private async Task RunCleaning(List<Category> work, ScanKind source)
    {
        var summary = new CleanSummary { Source = source };
        var receipt = new CleanupReceipt { Source = source };
        var cleaner = new Cleaner(Policy(), Trash, IsRunning);
        foreach (var category in work)
        {
            CleaningKind = category.Kind;
            if (source == ScanKind.Smart) ReviewKind = category.Kind;
            foreach (var row in category.Rows.Where(x => x.Selected && x.Status == RowStatus.Failed)) row.Status = RowStatus.Ready;
            Notify();
            // Give the list a moment to lay out so we know where every icon is.
            await Task.Delay(450);
            var queue = category.Rows.Where(x => x.Selected && x.Status == RowStatus.Ready).ToList();
            var gap = Math.Max(0.035, Math.Min(0.28, 5.5 / Math.Max(queue.Count, 1)));
            foreach (var row in queue)
            {
                var block = BlockReason(row);
                var (moved, error) = block == null ? await CleanRow(cleaner, row, receipt) : (0, block);
                var ok = moved > 0;
                var bytes = row.Files.Where(x => x.Removed).Sum(x => x.Size);
                Stage.Launch(LaunchOrigin(row.Id), ok, () =>
                {
                    if (ok) SessionFreed += bytes; else ShowNote(error ?? L("%@ 删不掉，投不进去", row.Name));
                    Notify();
                });
                row.Status = ok ? RowStatus.Cleaned : RowStatus.Failed;
                if (!ok) row.Selected = false;
                CleanDone++;
                if (ok)
                {
                    summary.Count++;
                    summary.Bytes += bytes;
                    summary.Lines[category.Kind] = summary.Lines.TryGetValue(category.Kind, out var line)
                        ? (line.Count + 1, line.Bytes + bytes) : (1, bytes);
                }
                else summary.Failures.Add((row.Name, error ?? L("删除失败（受系统保护或正在使用）")));
                Notify();
                await Task.Delay(TimeSpan.FromSeconds(gap));
            }
        }
        // Let the last paper balls land before wrapping up.
        for (var i = 0; i < 40 && Stage.Papers.Count > 0; i++) await Task.Delay(100);
        summary.Finished = DateTimeOffset.Now;
        foreach (var category in work) category.Rows.RemoveAll(x => x.Status == RowStatus.Cleaned);
        CleaningKind = null;
        IsCleaning = false;
        if (receipt.Files.Count > 0 || receipt.Errors.Count > 0) { SaveReceipt(receipt); summary.ReceiptId = receipt.Id; }
        RefreshDisk();
        if (source == ScanKind.Smart)
        {
            LastSummary = summary;
            DoneAt = DateTimeOffset.Now;
            SmartPhase = SmartPhase.Done;
        }
        else Banner = summary;
        Notify();
    }

    /// Moves one row's files to the bin, on an STA thread as the Shell expects. Returns how many moved and the first error.
    private Task<(int Moved, string? Error)> CleanRow(Cleaner cleaner, CleanRow row, CleanupReceipt batch)
    {
        return StaTask(() =>
        {
            // Journal every move as it happens, so an interrupted clean can still be undone (see RecoverPending).
            var result = cleaner.Clean(row.Files, ScanKind.Manual, current =>
            {
                lock (batch)
                {
                    var pending = new CleanupReceipt { Source = batch.Source, Date = batch.Date };
                    pending.Files.AddRange(batch.Files.Concat(current.Files));
                    Store.Write("pending", pending);
                }
            }, null, CancellationToken.None);
            lock (batch) { batch.Files.AddRange(result.Files); batch.Errors.AddRange(result.Errors); }
            var error = result.Errors.FirstOrDefault()?.Split('\n').LastOrDefault();
            return (result.Files.Count, result.Files.Count == 0 ? error : null);
        });
    }

    public static Task<T> StaTask<T>(Func<T> work)
    {
        var result = new TaskCompletionSource<T>(TaskCreationOptions.RunContinuationsAsynchronously);
        var thread = new Thread(() => { try { result.SetResult(work()); } catch (Exception e) { result.SetException(e); } }) { IsBackground = true };
        if (OperatingSystem.IsWindows()) thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        return result.Task;
    }

    private Point LaunchOrigin(string id)
    {
        var viewport = ListViewport.Inflate(4);
        if (IconFrames.TryGetValue(id, out var frame) && viewport.Contains(frame.Center)) return frame.Center;
        return new Point(ListViewport.X + 70, ListViewport.Y + 30);
    }

    /// Why a row can't go in the basket right now (its app is running, or a duplicate's keeper is gone).
    public string? BlockReason(CleanRow row)
    {
        if (row.Owners.Length > 0 && IsRunning(row.Owners)) return L("%@ 正在运行，投不进去", row.Name);
        if (row.Keeper != null && !File.Exists(row.Keeper)) return L("另一份已经不在了，%@ 要留着", row.Name);
        return null;
    }

    private void ShowNote(string text)
    {
        var token = ++noteToken;
        BasketNote = text;
        Notify();
        DispatcherTimer.RunOnce(() => { if (token == noteToken) { BasketNote = null; Notify(); } }, TimeSpan.FromSeconds(2.4));
    }

    // MARK: Throwing by hand

    private CleanRow? heldRow;
    private Category? heldCategory;

    public void BeginToss(CleanRow row, Category category, Point origin, Point location)
    {
        if (IsCleaning || Stage.Held != null || row.Status is not (RowStatus.Ready or RowStatus.Failed)) return;
        heldRow = row;
        heldCategory = category;
        Stage.Grab(row.Id, origin, location, BlockReason(row) != null);
        row.Status = RowStatus.Tossed;
        Notify();
    }

    public void MoveToss(Point location) => Stage.MoveHeld(location);

    /// Lets go of the paper. Only a ball that lands in the basket gets its file cleaned; a miss or a rim shot
    /// puts the file back in the list. Files that can't be moved are spat back out.
    public void EndToss(Vector velocity)
    {
        if (heldRow is not { } row || heldCategory is not { } category) return;
        heldRow = null;
        heldCategory = null;
        var block = BlockReason(row);
        var toss = Stage.Release(velocity);
        if (toss == null) return;
        if (toss.Kind != TossKind.Make)
        {
            DispatcherTimer.RunOnce(() => { row.Status = RowStatus.Ready; Notify(); }, TimeSpan.FromSeconds(Math.Min(toss.Lifetime, 1.2)));
            return;
        }
        _ = FinishToss(row, category, toss, block);
    }

    private async Task FinishToss(CleanRow row, Category category, TossedPaper toss, string? block)
    {
        var receipt = new CleanupReceipt { Source = ScanKind.Manual };
        var (moved, error) = block == null ? await CleanRow(new Cleaner(Policy(), Trash, IsRunning), row, receipt) : (0, block);
        var ok = moved > 0;
        Stage.Settle(toss.Id, ok);
        var wait = toss.Born + toss.ImpactTime - M.Now;
        if (wait > 0) await Task.Delay(TimeSpan.FromSeconds(wait));
        if (!ok) ShowNote(error ?? L("%@ 删不掉，投不进去", row.Name));
        // A refused file simply comes back; one whose move actually failed is flagged.
        row.Status = ok ? RowStatus.Cleaned : block == null ? RowStatus.Failed : RowStatus.Ready;
        if (ok)
        {
            SessionFreed += row.Files.Where(x => x.Removed).Sum(x => x.Size);
            SaveReceipt(receipt);
            RefreshDisk();
        }
        Notify();
    }

    /// Throws one row without dragging it: from the row's menu or the keyboard.
    public void ThrowAway(CleanRow row, Category category)
    {
        if (IsCleaning || row.Status is not (RowStatus.Ready or RowStatus.Failed)) return;
        var block = BlockReason(row);
        _ = Task.Run(async () =>
        {
            var receipt = new CleanupReceipt { Source = ScanKind.Manual };
            var (moved, error) = block == null ? await CleanRow(new Cleaner(Policy(), Trash, IsRunning), row, receipt) : (0, block);
            Dispatcher.UIThread.Post(() =>
            {
                var ok = moved > 0;
                var bytes = row.Files.Where(x => x.Removed).Sum(x => x.Size);
                Stage.Launch(LaunchOrigin(row.Id), ok, () =>
                {
                    if (ok) SessionFreed += bytes; else ShowNote(error ?? L("%@ 删不掉，投不进去", row.Name));
                    Notify();
                });
                row.Status = ok ? RowStatus.Cleaned : block == null ? RowStatus.Failed : RowStatus.Ready;
                if (ok) { SaveReceipt(receipt); RefreshDisk(); }
                Notify();
            });
        });
    }

    // MARK: History and undo

    /// A clean that was interrupted (the app quit or crashed) left its journal behind: keep it in the history.
    private void RecoverPending()
    {
        try
        {
            var pending = Store.Read<CleanupReceipt?>("pending", () => null);
            if (pending is { Files.Count: > 0 }) History.Insert(0, pending);
            if (pending != null) { Store.Write("history", History); File.Delete(Path.Combine(Places.DataDirectory, "pending.json")); }
        }
        catch (Exception e) when (e is IOException or System.Text.Json.JsonException or InvalidDataException) { }
    }

    private void SaveReceipt(CleanupReceipt receipt)
    {
        try { File.Delete(Path.Combine(Places.DataDirectory, "pending.json")); } catch (IOException) { }
        var index = History.FindIndex(x => x.Id == receipt.Id);
        if (index < 0) History.Insert(0, receipt); else History[index] = receipt;
        Store.Write("history", History);
    }

    /// A clean can be undone while its files are still in the bin.
    public bool CanRestore(CleanupReceipt receipt) => !IsCleaning && receipt.Files.Any(x => !x.Restored && File.Exists(x.RecycledPath));
    public bool CanRestore(CleanSummary summary) => History.FirstOrDefault(x => x.Id == summary.ReceiptId) is { } r && CanRestore(r);

    public void Restore(CleanSummary summary)
    {
        if (History.FirstOrDefault(x => x.Id == summary.ReceiptId) is { } receipt) Restore(receipt);
    }

    /// Puts every file of a clean back where it was.
    public void Restore(CleanupReceipt receipt)
    {
        var cleaner = new Cleaner(Policy(), Trash, IsRunning);
        var files = receipt.Files.Where(x => !x.Restored).ToList();
        StaTask(() => files.Count(cleaner.Restore)).ContinueWith(t => Dispatcher.UIThread.Post(() =>
        {
            var back = t.IsCompletedSuccessfully ? t.Result : 0;
            Store.Write("history", History);
            var target = ListViewport == default ? new Point(Stage.CanvasSize.Width * 0.55, Stage.CanvasSize.Height * 0.42) : ListViewport.Center;
            if (ShowsBasket) Stage.Unthrow(Math.Min(8, back), target);
            if (back == 0) { ShowToast(L("没能放回：文件已经不在废纸篓里，或原处已有同名文件")); return; }
            if (LastSummary?.ReceiptId == receipt.Id) LastSummary.ReceiptId = null;
            if (Banner?.ReceiptId == receipt.Id) Banner = null;
            RefreshDisk();
            // The files are back, so a list that was showing them is out of date.
            if (receipt.Source == ScanKind.Large && FilesPhase == ListPhase.Results) ScanLargeFiles();
            if (receipt.Source == ScanKind.Duplicates && DupPhase == ListPhase.Results) ScanDuplicates();
            var missing = files.Count - back;
            ShowToast(missing > 0 ? L("放回了 %lld 个，%lld 个已不在废纸篓里", back, missing) : L("已全部放回原处（%lld 个）", back));
        }));
    }

    public CleanupReceipt? UndoableReceipt => History.FirstOrDefault() is { } latest && CanRestore(latest) ? latest : null;

    public void UndoLastClean()
    {
        if (UndoableReceipt is { } receipt) Restore(receipt);
        else ShowToast(L("没有可以撤销的清理"));
    }

    public void ClearHistory() => Confirm(new(L("清空清理记录？"), L("只会删除记录，不影响任何文件。"), L("清空"), () =>
    {
        History = [];
        Store.Write("history", History);
        Notify();
    }));

    // MARK: Ignore list

    private bool IgnoreListContains(string path) => Preferences.IgnoredPaths.Any(x =>
        PathPolicy.Comparer.Equals(PathPolicy.Normalize(x), PathPolicy.Normalize(path)) || PathPolicy.IsBelow(PathPolicy.Normalize(path), PathPolicy.Normalize(x)));

    /// Hides a row from now on. It disappears from the list it was in.
    public void Ignore(CleanRow row, Category category)
    {
        var path = PathPolicy.Normalize(row.Path);
        if (!Preferences.IgnoredPaths.Contains(path, PathPolicy.Comparer)) Preferences.IgnoredPaths.Add(path);
        SaveSettings();
        category.Rows.Remove(row);
        ShowToast(L("以后不再列出 %@，可以在设置里恢复", row.Name));
    }
}
