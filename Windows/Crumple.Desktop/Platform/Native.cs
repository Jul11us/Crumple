using Crumple.Core;
using Microsoft.Win32;
using Microsoft.Win32.SafeHandles;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;

namespace Crumple.Desktop.Platform;

internal static class Native
{
    [DllImport("shell32.dll", PreserveSig = true)]
    private static extern int SHGetKnownFolderPath(in Guid id, uint flags, nint token, out nint path);
    public static string KnownFolder(Guid id, string fallback)
    {
        var result = SHGetKnownFolderPath(id, 0, 0, out var pointer);
        if (result < 0) return fallback;
        try { return Marshal.PtrToStringUni(pointer) ?? fallback; }
        finally { Marshal.FreeCoTaskMem(pointer); }
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct FileInformation
    {
        public uint Attributes;
        public FILETIME Creation, Access, Write;
        public uint Volume, SizeHigh, SizeLow, Links, IndexHigh, IndexLow;
    }
    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetFileInformationByHandle(SafeFileHandle file, out FileInformation info);
    public static string? FileIdentity(string path)
    {
        try
        {
            using var handle = File.OpenHandle(path, FileMode.Open, FileAccess.Read, FileShare.Read);
            if (!GetFileInformationByHandle(handle, out var info) || info.Links > 1) return null;
            return $"{info.Volume:X8}:{info.IndexHigh:X8}{info.IndexLow:X8}";
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { return null; }
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    internal struct MemoryStatus
    {
        public uint Length, Load;
        public ulong TotalPhysical, AvailablePhysical, TotalPage, AvailablePage, TotalVirtual, AvailableVirtual, Extended;
    }
    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GlobalMemoryStatusEx(ref MemoryStatus status);
    public static (long Total, long Free) Memory()
    {
        var value = new MemoryStatus { Length = (uint)Marshal.SizeOf<MemoryStatus>() };
        return GlobalMemoryStatusEx(ref value) ? ((long)value.TotalPhysical, (long)value.AvailablePhysical) : (0, 0);
    }

    /// Physical memory, and how much is committed (in RAM plus the page file).
    public static (long Total, long Free, long CommitUsed) MemoryStatusEx()
    {
        var value = new MemoryStatus { Length = (uint)Marshal.SizeOf<MemoryStatus>() };
        if (!GlobalMemoryStatusEx(ref value)) return (0, 0, 0);
        return ((long)value.TotalPhysical, (long)value.AvailablePhysical, (long)(value.TotalPage - value.AvailablePage));
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct PowerStatus { public byte AcLine, Flags, Percent, Saver; public int LifeTime, FullLifeTime; }
    [DllImport("kernel32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetSystemPowerStatus(out PowerStatus status);

    /// The battery, or null on a desktop without one.
    public static (int Percent, bool PluggedIn, bool Charging, int? MinutesLeft)? Battery()
    {
        if (!GetSystemPowerStatus(out var s) || (s.Flags & 128) != 0 || s.Flags == 255 || s.Percent > 100) return null;
        return (s.Percent, s.AcLine == 1, (s.Flags & 8) != 0, s.LifeTime > 0 ? s.LifeTime / 60 : null);
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetSystemTimes(out FILETIME idle, out FILETIME kernel, out FILETIME user);
    private static long lastIdle, lastTotal;
    private static long Ticks(FILETIME value) => ((long)value.dwHighDateTime << 32) | (uint)value.dwLowDateTime;
    public static double? Cpu()
    {
        if (!GetSystemTimes(out var idle, out var kernel, out var user)) return null;
        var i = Ticks(idle);
        var total = Ticks(kernel) + Ticks(user);
        var delta = total - lastTotal;
        var answer = lastTotal == 0 || delta <= 0 ? (double?)null : Math.Clamp(100.0 * (delta - (i - lastIdle)) / delta, 0, 100);
        lastTotal = total;
        lastIdle = i;
        return answer;
    }

    [StructLayout(LayoutKind.Sequential, Pack = 4)]
    private struct RecycleBinInfo { public int Size; public long Bytes; public long Items; }
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern int SHQueryRecycleBin(string? root, ref RecycleBinInfo info);
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern int SHEmptyRecycleBin(nint window, string? root, uint flags);

    /// What the Recycle Bin holds across all drives, or null when Windows won't say.
    public static long? RecycleBinBytes()
    {
        var info = new RecycleBinInfo { Size = Marshal.SizeOf<RecycleBinInfo>() };
        return SHQueryRecycleBin(null, ref info) == 0 ? info.Bytes : null;
    }

    /// Empties it without Explorer's own dialog (Crumple has already asked) or its sound.
    public static bool EmptyRecycleBin()
    {
        const uint noConfirmation = 0x1, noProgress = 0x2, noSound = 0x4;
        var result = SHEmptyRecycleBin(0, null, noConfirmation | noProgress | noSound);
        return result == 0 || result == unchecked((int)0x8000FFFF); // E_UNEXPECTED: it was already empty
    }

    public static string ProcessorName()
    {
        using var key = Registry.LocalMachine.OpenSubKey(@"HARDWARE\DESCRIPTION\System\CentralProcessor\0");
        return (Convert.ToString(key?.GetValue("ProcessorNameString")) ?? "").Trim();
    }

    /// "Windows 11 24H2"
    public static string WindowsVersion()
    {
        using var key = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion");
        var release = Convert.ToString(key?.GetValue("DisplayVersion")) ?? "";
        var name = Environment.OSVersion.Version.Build >= 22000 ? "Windows 11" : "Windows 10";
        return (name + " " + release).Trim();
    }

    public static void Open(string target, string? arguments = null)
    {
        var start = new ProcessStartInfo(target) { UseShellExecute = true };
        if (arguments != null) start.Arguments = arguments;
        Process.Start(start)?.Dispose();
    }
    public static void Reveal(string path) => Open("explorer.exe", "/select,\"" + path + "\"");

    public static List<InstalledApp> InstalledApps()
    {
        var results = new Dictionary<string, InstalledApp>(StringComparer.OrdinalIgnoreCase);
        foreach (var hive in new[] { RegistryHive.CurrentUser, RegistryHive.LocalMachine })
        foreach (var view in new[] { RegistryView.Registry64, RegistryView.Registry32 })
        {
            using var root = RegistryKey.OpenBaseKey(hive, view);
            using var uninstall = root.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Uninstall");
            if (uninstall == null) continue;
            foreach (var key in uninstall.GetSubKeyNames())
            {
                try
                {
                    using var app = uninstall.OpenSubKey(key);
                    if (app?.GetValue("DisplayName") is not string name || string.IsNullOrWhiteSpace(name)
                        || Convert.ToString(app.GetValue("SystemComponent")) == "1" || app.GetValue("ParentKeyName") != null) continue;
                    // The interactive uninstaller, never the quiet one: the app's own wizard asks before removing anything.
                    var command = Convert.ToString(app.GetValue("UninstallString")) ?? "";
                    if (command.Length == 0) continue;
                    var version = Convert.ToString(app.GetValue("DisplayVersion")) ?? "";
                    var publisher = Convert.ToString(app.GetValue("Publisher")) ?? "";
                    long.TryParse(Convert.ToString(app.GetValue("EstimatedSize")), out var kb);
                    var location = Convert.ToString(app.GetValue("InstallLocation")) ?? "";
                    DateTime? installed = DateTime.TryParseExact(Convert.ToString(app.GetValue("InstallDate")), "yyyyMMdd",
                        System.Globalization.CultureInfo.InvariantCulture, System.Globalization.DateTimeStyles.None, out var date) ? date : null;
                    results.TryAdd(name + "|" + version, new(name, version, publisher, Math.Max(0, kb) * 1024, command, location, installed,
                        hive == RegistryHive.CurrentUser));
                }
                catch (Exception e) when (e is System.Security.SecurityException or UnauthorizedAccessException or IOException) { }
            }
        }
        return results.Values.OrderByDescending(x => x.Bytes).ToList();
    }

    /// Runs an app's own uninstaller, the way Settings › Apps does. Windows asks for permission if it needs it.
    public static void RunUninstaller(string command)
    {
        var start = command.StartsWith('"') ? command.IndexOf('"', 1) : -1;
        var (file, arguments) = start > 0 ? (command[1..start], command[(start + 1)..].Trim())
            : command.StartsWith("MsiExec", StringComparison.OrdinalIgnoreCase) ? ("msiexec.exe", command[command.IndexOf(' ')..].Trim().Replace("/I", "/X", StringComparison.OrdinalIgnoreCase))
            : command.IndexOf(".exe ", StringComparison.OrdinalIgnoreCase) is var exe and > 0 ? (command[..(exe + 4)], command[(exe + 5)..]) : (command, "");
        Process.Start(new ProcessStartInfo(file, arguments) { UseShellExecute = true })?.Dispose();
    }

    // Startup apps: HKCU\…\Run, switched on and off the way Task Manager does it (StartupApproved).
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ApprovedKey = @"Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run";

    public static List<StartupItem> StartupItems()
    {
        var items = new List<StartupItem>();
        foreach (var (hive, user) in new[] { (Registry.CurrentUser, true), (Registry.LocalMachine, false) })
        {
            using var run = hive.OpenSubKey(RunKey);
            using var approved = hive.OpenSubKey(ApprovedKey);
            if (run == null) continue;
            foreach (var name in run.GetValueNames())
            {
                var enabled = approved?.GetValue(name) is not byte[] state || state.Length == 0 || (state[0] & 1) == 0;
                items.Add(new(name, Convert.ToString(run.GetValue(name)) ?? "", user, enabled));
            }
        }
        return items;
    }

    public static void SetStartupItem(StartupItem item, bool enabled)
    {
        if (!item.IsUserLevel) return;
        using var approved = Registry.CurrentUser.CreateSubKey(ApprovedKey);
        var state = new byte[12];
        state[0] = (byte)(enabled ? 2 : 3);
        if (!enabled) BitConverter.GetBytes(DateTime.UtcNow.ToFileTimeUtc()).CopyTo(state, 4);
        approved.SetValue(item.Name, state, RegistryValueKind.Binary);
    }
}

internal sealed record StartupItem(string Name, string Command, bool IsUserLevel, bool Enabled);

internal sealed record InstalledApp(string Name, string Version, string Publisher, long Bytes, string UninstallCommand,
    string Location, DateTime? Installed, bool PerUser);

/// Uses the Shell's recycle operation and captures the resulting item for history.
/// No permanent-delete path exists in the Windows build.
public sealed class WindowsTrash : ITrashService
{
    public TrashRecord Recycle(CleanItem item)
    {
        var drive = new DriveInfo(Path.GetPathRoot(item.Path)!);
        if (drive.DriveType != DriveType.Fixed) throw new IOException("Only local fixed disks with a Recycle Bin are supported.");
        var op = (IFileOperation)Activator.CreateInstance(Type.GetTypeFromCLSID(new("3AD05575-8857-4850-9277-11B85BDB8E09"))!)!;
        IShellItem? shellItem = null;
        try
        {
            var iid = typeof(IShellItem).GUID;
            Marshal.ThrowExceptionForHR(SHCreateItemFromParsingName(item.Path, 0, in iid, out shellItem));
            var sink = new RecycleSink();
            // RECYCLEONDELETE, ADDUNDORECORD, EARLYFAILURE, NOERRORUI, SILENT, NO_CONNECTED_ELEMENTS.
            // No NOCONFIRMATION: Windows retains its warning if it cannot recycle an item.
            op.SetOperationFlags(0x00080000 | 0x20000000 | 0x00100000 | 0x0400 | 0x0004 | 0x2000 | 0x4000);
            op.DeleteItem(shellItem, sink);
            op.PerformOperations();
            op.GetAnyOperationsAborted(out var aborted);
            if (sink.Error < 0) Marshal.ThrowExceptionForHR(sink.Error);
            if (aborted || string.IsNullOrEmpty(sink.RecycledPath) || File.Exists(item.Path))
                throw new IOException("Windows could not move this file to the Recycle Bin.");
            return new(item.Path, sink.RecycledPath, item.Stamp);
        }
        finally
        {
            if (shellItem != null) Marshal.FinalReleaseComObject(shellItem);
            Marshal.FinalReleaseComObject(op);
        }
    }

    public bool Restore(TrashRecord record)
    {
        // Match the exact item captured by the Shell; let Explorer remove its own recycle metadata.
        if (!File.Exists(record.RecycledPath) || !record.Stamp.Matches(record.RecycledPath)) return false;
        dynamic shell = Activator.CreateInstance(Type.GetTypeFromProgID("Shell.Application")!)!;
        object? folderObject = null, itemsObject = null;
        try
        {
            folderObject = shell.NameSpace(10);
            if (folderObject == null) return false;
            dynamic folder = folderObject;
            itemsObject = folder.Items();
            dynamic items = itemsObject;
            for (int i = 0; i < (int)items.Count; i++)
            {
                object entryObject = items.Item(i);
                try
                {
                    dynamic entry = entryObject;
                    if (!PathPolicy.Comparer.Equals((string)entry.Path, record.RecycledPath)) continue;
                    string? deletedFrom = entry.ExtendedProperty("System.Recycle.DeletedFrom") as string;
                    string? originalName = entry.ExtendedProperty("System.FileName") as string;
                    if (string.IsNullOrEmpty(deletedFrom) || string.IsNullOrEmpty(originalName)
                        || !PathPolicy.Comparer.Equals(PathPolicy.Normalize(Path.Combine(deletedFrom, originalName)), PathPolicy.Normalize(record.Original))) return false;
                    if (File.Exists(record.Original) || Directory.Exists(record.Original) || PathPolicy.HasUnsafeAncestor(record.Original)) return false;
                    entry.InvokeVerb("undelete");
                    var timer = Stopwatch.StartNew();
                    while (timer.ElapsedMilliseconds < 5000)
                    {
                        if (File.Exists(record.Original) && !File.Exists(record.RecycledPath)) return true;
                        Thread.Sleep(50);
                    }
                    return false;
                }
                finally { Marshal.FinalReleaseComObject(entryObject); }
            }
            return false;
        }
        finally
        {
            if (itemsObject != null) Marshal.FinalReleaseComObject(itemsObject);
            if (folderObject != null) Marshal.FinalReleaseComObject(folderObject);
            Marshal.FinalReleaseComObject(shell);
        }
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = true)]
    private static extern int SHCreateItemFromParsingName(string path, nint binding, in Guid iid, out IShellItem item);

    [ComImport, Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IShellItem
    {
        void BindToHandler(nint pbc, in Guid handler, in Guid iid, out nint result);
        void GetParent(out IShellItem parent);
        void GetDisplayName(uint type, out nint name);
        void GetAttributes(uint mask, out uint attributes);
        void Compare(IShellItem other, uint hint, out int order);
    }

    [ComImport, Guid("947AAB5F-0A5C-4C13-B4D6-4BF7836FC9F8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IFileOperation
    {
        void Advise(IFileOperationProgressSink sink, out uint cookie);
        void Unadvise(uint cookie);
        void SetOperationFlags(uint flags);
        void SetProgressMessage([MarshalAs(UnmanagedType.LPWStr)] string message);
        void SetProgressDialog(nint dialog);
        void SetProperties(nint properties);
        void SetOwnerWindow(nint owner);
        void ApplyPropertiesToItem(IShellItem item);
        void ApplyPropertiesToItems(nint items);
        void RenameItem(IShellItem item, [MarshalAs(UnmanagedType.LPWStr)] string name, IFileOperationProgressSink? sink);
        void RenameItems(nint items, [MarshalAs(UnmanagedType.LPWStr)] string name);
        void MoveItem(IShellItem item, IShellItem destination, [MarshalAs(UnmanagedType.LPWStr)] string? name, IFileOperationProgressSink? sink);
        void MoveItems(nint items, IShellItem destination);
        void CopyItem(IShellItem item, IShellItem destination, [MarshalAs(UnmanagedType.LPWStr)] string? name, IFileOperationProgressSink? sink);
        void CopyItems(nint items, IShellItem destination);
        void DeleteItem(IShellItem item, IFileOperationProgressSink sink);
        void DeleteItems(nint items);
        void NewItem(IShellItem destination, uint attributes, [MarshalAs(UnmanagedType.LPWStr)] string name,
            [MarshalAs(UnmanagedType.LPWStr)] string? template, IFileOperationProgressSink? sink);
        void PerformOperations();
        void GetAnyOperationsAborted([MarshalAs(UnmanagedType.Bool)] out bool aborted);
    }

    [ComVisible(true), Guid("04B0F1A7-9490-44BC-96E1-4296A31252E2"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IFileOperationProgressSink
    {
        [PreserveSig] int StartOperations();
        [PreserveSig] int FinishOperations(int result);
        [PreserveSig] int PreRenameItem(uint flags, IShellItem item, [MarshalAs(UnmanagedType.LPWStr)] string name);
        [PreserveSig] int PostRenameItem(uint flags, IShellItem item, [MarshalAs(UnmanagedType.LPWStr)] string name, int result, IShellItem? created);
        [PreserveSig] int PreMoveItem(uint flags, IShellItem item, IShellItem destination, [MarshalAs(UnmanagedType.LPWStr)] string? name);
        [PreserveSig] int PostMoveItem(uint flags, IShellItem item, IShellItem destination, [MarshalAs(UnmanagedType.LPWStr)] string? name, int result, IShellItem? created);
        [PreserveSig] int PreCopyItem(uint flags, IShellItem item, IShellItem destination, [MarshalAs(UnmanagedType.LPWStr)] string? name);
        [PreserveSig] int PostCopyItem(uint flags, IShellItem item, IShellItem destination, [MarshalAs(UnmanagedType.LPWStr)] string? name, int result, IShellItem? created);
        [PreserveSig] int PreDeleteItem(uint flags, IShellItem item);
        [PreserveSig] int PostDeleteItem(uint flags, IShellItem item, int result, IShellItem? created);
        [PreserveSig] int PreNewItem(uint flags, IShellItem destination, [MarshalAs(UnmanagedType.LPWStr)] string name);
        [PreserveSig] int PostNewItem(uint flags, IShellItem destination, [MarshalAs(UnmanagedType.LPWStr)] string name,
            [MarshalAs(UnmanagedType.LPWStr)] string? template, uint attributes, int result, IShellItem? created);
        [PreserveSig] int UpdateProgress(uint total, uint soFar);
        [PreserveSig] int ResetTimer();
        [PreserveSig] int PauseTimer();
        [PreserveSig] int ResumeTimer();
    }

    [ComVisible(true), ClassInterface(ClassInterfaceType.None)]
    public sealed class RecycleSink : IFileOperationProgressSink
    {
        public string? RecycledPath { get; private set; }
        public int Error { get; private set; }
        public int StartOperations() => 0;
        public int FinishOperations(int result) { if (result < 0) Error = result; return 0; }
        public int PreRenameItem(uint f, IShellItem i, string n) => 0;
        public int PostRenameItem(uint f, IShellItem i, string n, int r, IShellItem? c) => 0;
        public int PreMoveItem(uint f, IShellItem i, IShellItem d, string? n) => 0;
        public int PostMoveItem(uint f, IShellItem i, IShellItem d, string? n, int r, IShellItem? c) => 0;
        public int PreCopyItem(uint f, IShellItem i, IShellItem d, string? n) => 0;
        public int PostCopyItem(uint f, IShellItem i, IShellItem d, string? n, int r, IShellItem? c) => 0;
        public int PreDeleteItem(uint flags, IShellItem item) => (flags & 0x80) != 0 ? 0 : unchecked((int)0x80004004); // refuse non-recycle deletes
        public int PostDeleteItem(uint f, IShellItem i, int result, IShellItem? created)
        {
            Error = result;
            if (result >= 0 && created != null)
            {
                try
                {
                    created.GetDisplayName(0x80058000, out var pointer); // SIGDN_FILESYSPATH
                    try { RecycledPath = Marshal.PtrToStringUni(pointer); }
                    finally { Marshal.FreeCoTaskMem(pointer); }
                }
                catch (COMException e) { Error = e.HResult; }
            }
            return 0;
        }
        public int PreNewItem(uint f, IShellItem d, string n) => 0;
        public int PostNewItem(uint f, IShellItem d, string n, string? t, uint a, int r, IShellItem? c) => 0;
        public int UpdateProgress(uint t, uint s) => 0;
        public int ResetTimer() => 0;
        public int PauseTimer() => 0;
        public int ResumeTimer() => 0;
    }
}
