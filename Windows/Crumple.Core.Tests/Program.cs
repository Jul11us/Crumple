using Crumple.Core;

var root = Path.Combine(Directory.GetCurrentDirectory(), "build", "windows-tests", Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(root);
int passed = 0, failed = 0;
try
{
    void Test(string name, Action test)
    {
        try { test(); Console.WriteLine("PASS " + name); passed++; }
        catch (Exception error) { Console.WriteLine("FAIL " + name + ": " + error); failed++; }
    }
    void Expect(bool condition, string message = "Assertion failed") { if (!condition) throw new InvalidOperationException(message); }
    string Folder(string name) { var path = Path.Combine(root, name); Directory.CreateDirectory(path); return path; }
    string Make(string dir, string name, int bytes = 65536, int seed = 1, int age = 30)
    {
        var path = Path.Combine(dir, name); Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var data = new byte[bytes]; new Random(seed).NextBytes(data); File.WriteAllBytes(path, data);
        File.SetLastWriteTimeUtc(path, DateTime.UtcNow.AddDays(-age)); return path;
    }
    CleanItem Item(string path, string? keeper = null, string[]? owners = null) => new()
    {
        Path = path, Stamp = FileStamp.Read(path), Category = keeper == null ? FileCategory.Temporary : FileCategory.Duplicate,
        Selected = true, Keeper = keeper, KeeperStamp = keeper == null ? null : FileStamp.Read(keeper),
        ContentHash = keeper == null ? null : Hash(path), OwnerProcesses = owners ?? []
    };
    string Hash(string path) { using var stream = Scanner.OpenRead(path); return Scanner.FullHash(stream, CancellationToken.None); }
    CleanupReceipt Clean(PathPolicy policy, TestTrash trash, params CleanItem[] items) =>
        new Cleaner(policy, trash, _ => false).Clean(items, ScanKind.Smart, _ => { }, null, CancellationToken.None);

    Test("Scope boundaries and parent traversal", () =>
    {
        var dir = Folder("boundaries"); var policy = new PathPolicy([dir], []);
        Expect(!policy.InScope(dir)); Expect(policy.InScope(Path.Combine(dir, "a.txt")));
        Expect(!policy.InScope(Path.Combine(dir + "-sibling", "a.txt")));
        Expect(!policy.InScope(Path.Combine(dir, "..", "outside.txt")));
    });
    Test("Exclusions include descendants without prefix collisions", () =>
    {
        var dir = Folder("exclusions"); var policy = new PathPolicy([dir], [Path.Combine(dir, "skip")]);
        Expect(!policy.InScope(Path.Combine(dir, "skip", "a.txt")));
        Expect(policy.InScope(Path.Combine(dir, "skip-other", "a.txt")));
    });
    Test("Protected system trees override explicitly granted roots", () =>
    {
        var dir = Folder("protected"); var system = Folder("protected/system"); var policy = new PathPolicy([dir, system], [], [system]);
        Expect(!policy.InScope(Path.Combine(system, "file.txt"))); Expect(policy.InScope(Path.Combine(dir, "mine.txt")));
    });
    Test("A changed file is never recycled", () =>
    {
        var dir = Folder("changed"); var path = Make(dir, "file.bin"); var item = Item(path);
        File.AppendAllText(path, "changed"); var trash = new TestTrash(Folder("changed-bin"));
        var receipt = Clean(new([dir], []), trash, item);
        Expect(receipt.Files.Count == 0 && receipt.Errors.Count == 1 && File.Exists(path));
    });
    Test("Directories can never be cleanup candidates", () =>
    {
        var dir = Folder("directory"); var child = Folder("directory/child"); Make(child, "stay.bin");
        var item = new CleanItem { Path = child, Category = FileCategory.Temporary, Stamp = new(0, DateTime.UtcNow, DateTime.UtcNow) };
        var receipt = Clean(new([dir], []), new(Folder("directory-bin")), item);
        Expect(receipt.Files.Count == 0 && Directory.Exists(child));
    });
    Test("Symbolic links are never traversed or recycled", () =>
    {
        var dir = Folder("links"); var outside = Folder("links-outside"); Make(outside, "private.bin");
        var link = Path.Combine(dir, "linked");
        try { Directory.CreateSymbolicLink(link, outside); }
        catch (UnauthorizedAccessException) when (OperatingSystem.IsWindows()) { Console.WriteLine("  Link creation unavailable without Developer Mode; run link tests on macOS/Linux."); return; }
        var policy = new PathPolicy([dir], []);
        Expect(policy.WalkFiles(dir, CancellationToken.None).Count() == 0);
        Expect(!policy.CanReadFile(Path.Combine(link, "private.bin")));
        Expect(File.Exists(Path.Combine(outside, "private.bin")));
    });
    Test("A directory replaced by a link after scanning is rejected", () =>
    {
        var dir = Folder("link-race"); var child = Folder("link-race/child"); var original = Make(child, "file.bin"); var item = Item(original);
        var outside = Folder("link-race-outside"); Make(outside, "file.bin");
        Directory.Move(child, child + "-old");
        try { Directory.CreateSymbolicLink(child, outside); }
        catch (UnauthorizedAccessException) when (OperatingSystem.IsWindows()) { Directory.Move(child + "-old", child); return; }
        var result = Clean(new([dir], []), new(Folder("link-race-bin")), item);
        Expect(result.Files.Count == 0 && File.Exists(Path.Combine(outside, "file.bin")));
    });
    Test("Running app caches are blocked at cleanup time", () =>
    {
        var dir = Folder("running"); var file = Make(dir, "cache.bin");
        var receipt = new Cleaner(new([dir], []), new TestTrash(Folder("running-bin")), _ => true)
            .Clean([Item(file, owners: ["example"])], ScanKind.Smart, _ => { }, null, CancellationToken.None);
        Expect(receipt.Files.Count == 0 && receipt.Errors.Count == 1 && File.Exists(file));
    });
    Test("Recycle and restore preserves contents", () =>
    {
        var dir = Folder("restore"); var file = Make(dir, "file.bin"); var hash = Hash(file);
        var trash = new TestTrash(Folder("restore-bin")); var cleaner = new Cleaner(new([dir], []), trash, _ => false);
        var receipt = cleaner.Clean([Item(file)], ScanKind.Smart, _ => { }, null, CancellationToken.None);
        Expect(receipt.Files.Count == 1 && !File.Exists(file));
        Expect(cleaner.Restore(receipt.Files[0]) && File.Exists(file) && Hash(file) == hash);
        Expect(!cleaner.Restore(receipt.Files[0]));
    });
    Test("Restore does not overwrite a newly created file", () =>
    {
        var dir = Folder("restore-conflict"); var file = Make(dir, "file.bin"); var trash = new TestTrash(Folder("restore-conflict-bin"));
        var cleaner = new Cleaner(new([dir], []), trash, _ => false);
        var receipt = cleaner.Clean([Item(file)], ScanKind.Smart, _ => { }, null, CancellationToken.None);
        File.WriteAllText(file, "new contents");
        Expect(!cleaner.Restore(receipt.Files[0])); Expect(File.ReadAllText(file) == "new contents");
    });
    Test("History must be writable before cleanup starts", () =>
    {
        var dir = Folder("journal"); var file = Make(dir, "file.bin");
        try
        {
            new Cleaner(new([dir], []), new TestTrash(Folder("journal-bin")), _ => false)
                .Clean([Item(file)], ScanKind.Smart, _ => throw new IOException("read only"), null, CancellationToken.None);
            throw new InvalidOperationException("Expected history write failure");
        }
        catch (IOException) { Expect(File.Exists(file)); }
    });
    Test("Cancellation keeps already moved items in the saved receipt", () =>
    {
        var dir = Folder("cancel-clean"); var a = Item(Make(dir, "a.bin")); var b = Item(Make(dir, "b.bin"));
        using var cancel = new CancellationTokenSource(); int saved = 0;
        var receipt = new Cleaner(new([dir], []), new TestTrash(Folder("cancel-clean-bin")), _ => false)
            .Clean([a, b], ScanKind.Smart, r => { saved = r.Files.Count; if (saved == 1) cancel.Cancel(); }, null, cancel.Token);
        Expect(receipt.Files.Count == 1 && saved == 1 && File.Exists(b.Path));
    });
    Test("Installers and old personal downloads start unselected", () =>
    {
        var dir = Folder("downloads"); Make(dir, "installer.exe"); Make(dir, "notes.txt", age: 100);
        var result = new Scanner(new([dir], [])).Smart([new(dir, FileCategory.Installers, false), new(dir, FileCategory.OldDownloads, false, 90)], [], new(), _ => false, null, CancellationToken.None);
        Expect(result.Items.Count == 2 && result.Items.All(x => !x.Selected));
    });
    Test("Recent temporary files are not offered for cleanup", () =>
    {
        var dir = Folder("temp"); Make(dir, "old.tmp", age: 30); Make(dir, "active.tmp", age: 1);
        var result = new Scanner(new([dir], [])).Smart([new(dir, FileCategory.Temporary, true, 7)], [], new(), _ => false, null, CancellationToken.None);
        Expect(result.Items.Count == 1 && result.Items[0].Name == "old.tmp" && result.Items[0].Selected);
    });
    Test("Overlapping scan locations never count a file twice", () =>
    {
        var dir = Folder("overlap"); Make(dir, "file.bin"); var result = new Scanner(new([dir], [])).Smart(
            [new(dir, FileCategory.Temporary, true), new(dir, FileCategory.Logs, true)], [], new(), _ => false, null, CancellationToken.None);
        Expect(result.Items.Count == 1);
    });
    Test("Full hash distinguishes files with identical samples", () =>
    {
        var dir = Folder("duplicates"); var a = Make(dir, "original.bin", 128 * 1024); var b = Make(dir, "copy.bin", 128 * 1024);
        var c = Make(dir, "different.bin", 128 * 1024); var bytes = File.ReadAllBytes(c); bytes[24000] ^= 0xff; File.WriteAllBytes(c, bytes);
        Expect(Scanner.SampleHash(a, bytes.Length, CancellationToken.None) == Scanner.SampleHash(c, bytes.Length, CancellationToken.None));
        var result = new Scanner(new([dir], [])).Duplicates([dir], 1, null, CancellationToken.None);
        Expect(result.Items.Count == 1 && result.Items[0].Path == b && result.Items[0].Keeper == a);
    });
    Test("Missing or changed keeper prevents duplicate cleanup", () =>
    {
        var dir = Folder("keeper"); var keeper = Make(dir, "original.bin"); var copy = Make(dir, "copy.bin"); var item = Item(copy, keeper);
        File.Delete(keeper); var receipt = Clean(new([dir], []), new(Folder("keeper-bin")), item);
        Expect(receipt.Files.Count == 0 && File.Exists(copy));
    });
    Test("Duplicate contents are rehashed immediately before cleanup", () =>
    {
        var dir = Folder("rehash"); var keeper = Make(dir, "original.bin"); var copy = Make(dir, "copy.bin"); var item = Item(copy, keeper);
        var stamp = FileStamp.Read(copy); var bytes = File.ReadAllBytes(copy); bytes[100] ^= 0xff; File.WriteAllBytes(copy, bytes);
        File.SetLastWriteTimeUtc(copy, stamp.LastWriteUtc);
        var receipt = Clean(new([dir], []), new(Folder("rehash-bin")), item);
        Expect(receipt.Files.Count == 0 && File.Exists(copy) && File.Exists(keeper));
    });
    Test("Physical file identity removes hard-link aliases from comparisons", () =>
    {
        var dir = Folder("identity"); Make(dir, "a.bin"); Make(dir, "b.bin");
        var result = new Scanner(new([dir], []), _ => "same-physical-file").Duplicates([dir], 1, null, CancellationToken.None);
        Expect(result.Items.Count == 0);
    });
    Test("Cancelled scans throw and do not return partial results", () =>
    {
        var dir = Folder("cancel-scan"); Make(dir, "file.bin"); using var cancel = new CancellationTokenSource(); cancel.Cancel();
        try { new Scanner(new([dir], [])).Large([dir], 1, null, cancel.Token); throw new InvalidOperationException("Expected cancellation"); }
        catch (OperationCanceledException) { }
    });
    Test("Space analysis groups by immediate child and respects exclusions", () =>
    {
        var dir = Folder("analysis"); Make(dir, Path.Combine("a", "one.bin"), 100); Make(dir, Path.Combine("a", "two.bin"), 200);
        Make(dir, "top.bin", 50); var ignored = Make(dir, "ignored.bin", 500);
        var result = new Scanner(new([dir], [ignored])).Analyze(dir, null, CancellationToken.None);
        Expect(result.Count == 2 && result.Sum(x => x.Bytes) == 350 && result.Sum(x => x.Files) == 3);
    });
    Test("Atomic JSON history round trip and corrupt-file handling", () =>
    {
        var dir = Folder("store"); var store = new JsonStore(dir); var data = new List<CleanupReceipt> { new() { Errors = ["sample"] } };
        store.Write("history", data); var read = store.Read("history", () => new List<CleanupReceipt>());
        Expect(read.Count == 1 && read[0].Errors[0] == "sample");
        File.WriteAllText(Path.Combine(dir, "history.json"), "damaged");
        try { store.Read("history", () => new List<CleanupReceipt>()); throw new InvalidOperationException("Corruption must surface"); }
        catch (System.Text.Json.JsonException) { Expect(File.ReadAllText(Path.Combine(dir, "history.json")) == "damaged"); }
    });
    Test("Shared never-touch cases (Tests/Shared/never-touch.json)", () =>
    {
        var home = Folder("shared-home"); var policy = new PathPolicy([home], []);
        using var file = System.Text.Json.JsonDocument.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "never-touch.json")));
        var checkedCases = 0;
        foreach (var entry in file.RootElement.GetProperty("cases").EnumerateArray())
        {
            if (entry.TryGetProperty("platform", out var platform) && platform.GetString() != "windows") continue;
            var relative = entry.GetProperty("path").GetString()!;
            Expect(relative.StartsWith("~/", StringComparison.Ordinal), relative);
            var path = Path.Combine(home, relative[2..].Replace('/', Path.DirectorySeparatorChar));
            var allowed = entry.GetProperty("expect").GetString() == "allow";
            Expect(policy.InScope(path) == allowed, (allowed ? "should allow " : "should refuse ") + relative);
            checkedCases++;
        }
        Expect(checkedCases > 10, "Shared cases missing");
    });
    Test("Sensitive folders are not walked into", () =>
    {
        var dir = Folder("sensitive-walk"); Make(dir, "keep.bin"); Make(Path.Combine(dir, ".ssh"), "id_ed25519");
        Make(Path.Combine(dir, "Microsoft", "Credentials"), "blob");
        var found = new PathPolicy([dir], []).WalkFiles(dir, CancellationToken.None).Select(x => Path.GetFileName(x)).ToArray();
        Expect(found.Length == 1 && found[0] == "keep.bin", string.Join(", ", found));
    });
    Console.WriteLine($"\n{passed} passed, {failed} failed");
}
finally { Directory.Delete(root, true); }
return failed == 0 ? 0 : 1;

sealed class TestTrash(string directory) : ITrashService
{
    public TrashRecord Recycle(CleanItem item)
    {
        var target = Path.Combine(directory, Guid.NewGuid().ToString("N")); File.Move(item.Path, target);
        return new(item.Path, target, item.Stamp);
    }
    public bool Restore(TrashRecord record)
    {
        if (!File.Exists(record.RecycledPath)) return false;
        Directory.CreateDirectory(Path.GetDirectoryName(record.Original)!); File.Move(record.RecycledPath, record.Original, false); return true;
    }
}
