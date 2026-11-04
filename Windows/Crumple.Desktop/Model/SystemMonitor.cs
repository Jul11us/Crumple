using System.Diagnostics;
using System.Net.NetworkInformation;
using System.Runtime.InteropServices;
using Avalonia.Threading;
using Crumple.Desktop.Platform;
using static Crumple.Desktop.Model.Strings;

namespace Crumple.Desktop.Model;

/// The same scoring as the Mac version: each part out of 100 on a smooth curve, weighted,
/// and the weakest part holds the total down to its own score plus 35.
internal static class HealthScore
{
    public sealed record Factor(string Title, int Score, double Weight, string Note);

    public static double Combine(IReadOnlyList<Factor> factors)
    {
        if (factors.Count == 0) return 100;
        var mean = factors.Sum(x => x.Score * x.Weight) / factors.Sum(x => x.Weight);
        return Math.Min(mean, factors.Min(x => x.Score) + 35);
    }

    public static string Label(int score) => score >= 90 ? L("很好") : score >= 75 ? L("良好") : score >= 55 ? L("一般") : L("需要关注");

    /// Straight lines between the given (input, score) points.
    public static double Curve(double x, (double X, double Y)[] points)
    {
        if (x <= points[0].X) return points[0].Y;
        if (x >= points[^1].X) return points[^1].Y;
        for (var i = 1; i < points.Length; i++)
            if (x <= points[i].X)
                return points[i - 1].Y + (points[i].Y - points[i - 1].Y) * (x - points[i - 1].X) / (points[i].X - points[i - 1].X);
        return points[^1].Y;
    }

    /// Windows reports how much memory is committed; past about 85% it starts paging and slows down.
    public static Factor Memory(double load, long pageFileUsed)
    {
        var score = Curve(load, [(0.75, 100), (0.85, 70), (0.92, 40), (0.98, 15)]);
        score -= Math.Min(20, Math.Max(0, pageFileUsed / 1e9 - 2) * 4);
        return new(L("内存"), (int)Math.Round(Math.Max(5, score)), 0.30, load >= 0.92 ? L("内存压力很大") : L("内存压力偏高"));
    }

    /// The last half minute, not this instant: a short spike is normal, staying busy is not.
    public static Factor Cpu(IReadOnlyList<double> history)
    {
        var recent = history.TakeLast(20).ToList();
        var average = recent.Count == 0 ? 0 : recent.Average();
        return new("CPU", (int)Math.Round(Math.Max(5, Curve(average, [(0.5, 100), (0.8, 70), (1.0, 40)]))), 0.20, L("CPU 一直很忙"));
    }

    public static Factor Disk(long available, long total)
    {
        if (total <= 0) return new(L("磁盘"), 100, 0.25, "");
        var score = Curve((double)available / total, [(0, 0), (0.02, 15), (0.05, 40), (0.10, 70), (0.20, 100)]);
        // A big disk can be 10% free and still have plenty; a small one can't afford that.
        if (available < 5_000_000_000) score = Math.Min(score, 35); else if (available < 10_000_000_000) score = Math.Min(score, 60);
        return new(L("磁盘"), (int)Math.Round(score), 0.25, score < 60 ? L("磁盘快满了") : L("磁盘空间偏少"));
    }

    public static Factor Battery(int health)
    {
        var score = Curve(health, [(50, 20), (70, 60), (80, 85), (90, 100)]);
        return new(L("电池"), (int)Math.Round(score), 0.10, L("电池已经老化"));
    }
}

/// Live readings of the machine, sampled every 1.5 seconds while the status page is open.
internal sealed class SystemMonitor(AppModel model)
{
    public const double Interval = 1.5;

    public sealed record AppUsage(string Name, int Pid, long Memory, double Cpu);
    public sealed record BatteryInfo(int Percent, bool PluggedIn, bool Charging, int? MinutesLeft);

    public bool HasSample { get; private set; }
    public double Cpu { get; private set; }
    public List<double> CpuHistory { get; } = [];
    public double MemoryLoad { get; private set; }
    public long MemoryUsed { get; private set; }
    public long MemoryTotal { get; private set; }
    public long PageFileUsed { get; private set; }
    public List<double> MemoryHistory { get; } = [];
    public double Download { get; private set; }
    public double Upload { get; private set; }
    public List<double> DownloadHistory { get; } = [];
    public BatteryInfo? Battery { get; private set; }
    public List<AppUsage> Apps { get; private set; } = [];
    public int ProcessCount { get; private set; }
    public TimeSpan Uptime => TimeSpan.FromMilliseconds(Environment.TickCount64);
    public int Cores => Environment.ProcessorCount;
    private double? smoothed;
    private DispatcherTimer? timer;
    private long lastReceived, lastSent;
    private DateTime lastNetwork;
    private readonly Dictionary<int, TimeSpan> lastCpuTimes = [];
    private DateTime lastProcessSample;
    private int demoTick;

    public void Start()
    {
        if (timer != null) return;
        timer = new DispatcherTimer(TimeSpan.FromSeconds(Interval), DispatcherPriority.Background, (_, _) => Sample());
        timer.Start();
        Sample();
    }

    public void Stop() { timer?.Stop(); timer = null; }

    public IReadOnlyList<HealthScore.Factor> Factors
    {
        get
        {
            var list = new List<HealthScore.Factor> { HealthScore.Memory(MemoryLoad, PageFileUsed), HealthScore.Cpu(CpuHistory) };
            if (model.Disk is { } disk) list.Add(HealthScore.Disk(disk.Available, disk.Total));
            return list;
        }
    }

    public (int Score, string Label, string Note) Health
    {
        get
        {
            var score = (int)Math.Round(smoothed ?? HealthScore.Combine(Factors));
            var weakest = Factors.MinBy(x => x.Score);
            var note = weakest is { Score: < 85 } ? weakest.Note : L("一切正常");
            return (score, HealthScore.Label(score), note);
        }
    }

    private static void Push(List<double> history, double value)
    {
        history.Add(value);
        if (history.Count > 40) history.RemoveAt(0);
    }

    private void Sample()
    {
        if (OperatingSystem.IsWindows() && !model.Demo) SampleWindows(); else SampleDemo();
        var target = HealthScore.Combine(Factors);
        smoothed = smoothed is { } s ? s + 0.3 * (target - s) : target;
        HasSample = true;
        model.Notify();
    }

    private void SampleWindows()
    {
        Cpu = (Native.Cpu() ?? 0) / 100;
        Push(CpuHistory, Cpu);
        var memory = Native.MemoryStatusEx();
        MemoryTotal = memory.Total;
        MemoryUsed = memory.Total - memory.Free;
        MemoryLoad = memory.Total > 0 ? (double)MemoryUsed / memory.Total : 0;
        PageFileUsed = Math.Max(0, memory.CommitUsed - MemoryUsed);
        Push(MemoryHistory, MemoryLoad);
        Battery = Native.Battery() is { } b ? new BatteryInfo(b.Percent, b.PluggedIn, b.Charging, b.MinutesLeft) : null;
        SampleNetwork();
        SampleProcesses();
    }

    private void SampleNetwork()
    {
        long received = 0, sent = 0;
        try
        {
            foreach (var nic in NetworkInterface.GetAllNetworkInterfaces())
            {
                if (nic.OperationalStatus != OperationalStatus.Up || nic.NetworkInterfaceType == NetworkInterfaceType.Loopback) continue;
                var stats = nic.GetIPStatistics();
                received += stats.BytesReceived;
                sent += stats.BytesSent;
            }
        }
        catch (NetworkInformationException) { }
        var now = DateTime.UtcNow;
        if (lastNetwork != default)
        {
            var seconds = Math.Max(0.1, (now - lastNetwork).TotalSeconds);
            Download = Math.Max(0, (received - lastReceived) / seconds);
            Upload = Math.Max(0, (sent - lastSent) / seconds);
        }
        Push(DownloadHistory, Download);
        (lastReceived, lastSent, lastNetwork) = (received, sent, now);
    }

    /// Apps by name: their processes' memory added up, and their share of the CPU since the last sample.
    private void SampleProcesses()
    {
        var now = DateTime.UtcNow;
        var elapsed = Math.Max(0.1, (now - lastProcessSample).TotalSeconds);
        var usages = new Dictionary<string, (int Pid, long Memory, double Cpu)>(StringComparer.OrdinalIgnoreCase);
        var processes = Process.GetProcesses();
        ProcessCount = processes.Length;
        var seen = new HashSet<int>();
        foreach (var p in processes)
        {
            try
            {
                seen.Add(p.Id);
                var cpuTime = p.TotalProcessorTime;
                var cpu = lastCpuTimes.TryGetValue(p.Id, out var before) && lastProcessSample != default
                    ? (cpuTime - before).TotalSeconds / elapsed / Cores * 100 : 0;
                lastCpuTimes[p.Id] = cpuTime;
                var name = p.ProcessName;
                usages.TryGetValue(name, out var u);
                usages[name] = (u.Pid == 0 ? p.Id : u.Pid, u.Memory + p.WorkingSet64, u.Cpu + cpu);
            }
            catch (Exception e) when (e is InvalidOperationException or System.ComponentModel.Win32Exception or NotSupportedException) { }
            finally { p.Dispose(); }
        }
        foreach (var gone in lastCpuTimes.Keys.Where(x => !seen.Contains(x)).ToList()) lastCpuTimes.Remove(gone);
        lastProcessSample = now;
        Apps = usages.Where(x => x.Key is not ("Idle" or "System" or "Registry" or "Memory Compression"))
            .Select(x => new AppUsage(x.Key, x.Value.Pid, x.Value.Memory, Math.Min(100, x.Value.Cpu)))
            .OrderByDescending(x => x.Memory).Take(12).ToList();
    }

    /// Believable readings for the demo and for previews made on a Mac.
    private void SampleDemo()
    {
        var t = demoTick++;
        Cpu = 0.18 + 0.12 * Math.Sin(t * 0.7) + 0.05 * Math.Sin(t * 2.3);
        Push(CpuHistory, Cpu);
        MemoryTotal = 16L << 30;
        MemoryLoad = 0.62 + 0.03 * Math.Sin(t * 0.3);
        MemoryUsed = (long)(MemoryTotal * MemoryLoad);
        PageFileUsed = 900L << 20;
        Push(MemoryHistory, MemoryLoad);
        Download = 120_000 + 90_000 * Math.Abs(Math.Sin(t * 0.9));
        Upload = 18_000;
        Push(DownloadHistory, Download);
        Battery = new BatteryInfo(76, false, false, 214);
        ProcessCount = 214;
        Apps = [new("msedge", 8120, 1_420_000_000, 6.2), new("Code", 10432, 980_000_000, 3.1), new("WeChat", 6640, 610_000_000, 0.8),
            new("explorer", 4410, 240_000_000, 0.4), new("Crumple", Environment.ProcessId, 160_000_000, 1.2), new("Spotify", 9204, 320_000_000, 0.6)];
    }
}
