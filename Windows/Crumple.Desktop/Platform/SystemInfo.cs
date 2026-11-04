namespace Crumple.Desktop.Platform;

/// The system drive.
internal sealed record DiskInfo(string Name, long Total, long Available)
{
    public long Used => Math.Max(0, Total - Available);
    public double UsedFraction => Total > 0 ? (double)Used / Total : 0;

    public static DiskInfo? Current(bool demo)
    {
        try
        {
            var root = OperatingSystem.IsWindows() ? Path.GetPathRoot(Environment.SystemDirectory) ?? "C:\\" : "/";
            var drive = new DriveInfo(root);
            var letter = root.TrimEnd('\\', '/');
            var label = OperatingSystem.IsWindows() && !string.IsNullOrWhiteSpace(drive.VolumeLabel) ? drive.VolumeLabel : Model.Strings.L("本地磁盘");
            var name = demo || !OperatingSystem.IsWindows() ? Model.Strings.L("本地磁盘") + " (C:)" : $"{label} ({letter})";
            return new(name, drive.TotalSize, drive.AvailableFreeSpace);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or ArgumentException) { return null; }
    }
}

/// "DESKTOP-4F2 · Intel Core i7-1260P · 16 GB 内存 · Windows 11 24H2"
internal static class SystemInfo
{
    public static string Summary(bool demo)
    {
        if (demo || !OperatingSystem.IsWindows())
            return string.Join(" · ", "DESKTOP-CRUMPLE", "Intel Core i7-1360P", Model.Strings.L("%@ 内存", "16 GB"), "Windows 11 24H2");
        var memory = Native.Memory().Total;
        var parts = new[] { Environment.MachineName, Native.ProcessorName(),
            memory > 0 ? Model.Strings.L("%@ 内存", Model.Format.Bytes(memory)) : "", Native.WindowsVersion() };
        return string.Join(" · ", parts.Where(x => !string.IsNullOrWhiteSpace(x)));
    }
}
