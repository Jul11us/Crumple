using System.Diagnostics;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;
using Crumple.Desktop.Art;
using Crumple.Desktop.Model;
using Crumple.Desktop.Platform;
using Crumple.Desktop.Ui;
using static Crumple.Desktop.Model.Strings;
using static Crumple.Desktop.Ui.Ui;

namespace Crumple.Desktop.Views;

/// Live view of the machine: health, CPU, memory, battery, disk, network, and the apps using the most memory.
internal static class StatusPage
{
    public static Control Build(AppModel model)
    {
        var monitor = model.Monitor;
        monitor.Start();
        var content = V(24,
            H(10, Title(L("状态"), 30), Text(L("每 %@ 秒刷新", SystemMonitor.Interval.ToString("0.0")), 12, brush: Ink.Tertiary)
                .With(t => { t.VerticalAlignment = VerticalAlignment.Bottom; t.Margin = new Thickness(0, 0, 0, 8); })),
            HealthLine(model, monitor),
            Readings(model, monitor),
            Processes(model, monitor));
        content.Margin = new Thickness(32, 48, BasketGeometry.ReservedTrailing, 32);
        return Common.Scroll("status", content);
    }

    /// The score as one printed line, with the machine's particulars underneath.
    private static Control HealthLine(AppModel model, SystemMonitor monitor)
    {
        var health = monitor.Health;
        var factors = monitor.Factors;
        var weakest = factors.MinBy(x => x.Score);
        var parts = H(14);
        foreach (var factor in factors)
            parts.Children.Add(H(5, Text(factor.Title, 12, brush: Ink.Secondary),
                Figures(factor.Score.ToString(), 12, factor == weakest && factor.Score < 85 ? FontWeight.SemiBold : FontWeight.Normal)
                    .With(t => t.Foreground = factor.Score < 55 ? Ink.Danger : factor.Score < 75 ? Ink.Warning : Ink.Primary)));
        ToolTip.SetTip(parts, L("内存占 30%、磁盘 25%、CPU 20%；最弱的一项会把总分压在它的分数加 35 以内。"));
        var color = health.Score >= 75 ? Ink.Primary : health.Score >= 55 ? Ink.Warning : Ink.Danger;
        return V(6,
            H(12, Title(monitor.HasSample ? health.Score.ToString() : "--", 44),
                Text($"{health.Label} · {health.Note}", 15, FontWeight.Medium, color).With(t => { t.VerticalAlignment = VerticalAlignment.Bottom; t.Margin = new Thickness(0, 0, 0, 12); })),
            parts.Margin(0, 2, 0, 0),
            Text(SystemInfo.Summary(model.Demo) + " · " + L("已运行 %@", Duration(monitor.Uptime)), 12, brush: Ink.Secondary));
    }

    private static string Duration(TimeSpan span) => span.TotalDays >= 1 ? L("%lld 天 %lld 小时", (int)span.TotalDays, span.Hours)
        : span.TotalHours >= 1 ? L("%lld 小时 %lld 分钟", (int)span.TotalHours, span.Minutes) : L("%lld 分钟", (int)span.TotalMinutes);

    private static string Level(double usage) => usage < 0.3 ? L("低负载") : usage < 0.7 ? L("中等负载") : L("高负载");
    private static string Rate(double bytesPerSecond) => Format.Bytes((long)bytesPerSecond) + "/s";

    /// Every reading on one sheet: name, figure, a thin trace of the last few seconds, and a note.
    private static Control Readings(AppModel model, SystemMonitor m)
    {
        var rows = V(0);
        void Add(Control row) { if (rows.Children.Count > 0) rows.Children.Add(new Hairline()); rows.Children.Add(row); }
        Add(ReadingRow("CPU", $"{(int)(m.Cpu * 100)}", "%", $"{Level(m.Cpu)} · {L("%lld 核", m.Cores)}", new Trace(m.CpuHistory, 1)));
        var pressured = m.MemoryLoad >= 0.85;
        Add(ReadingRow(L("内存"), $"{(int)(m.MemoryLoad * 100)}", "%",
            string.Join(" · ", new[] { pressured ? L("压力偏高") : null, Format.Bytes(m.MemoryUsed), L("页面文件 %@", Format.Bytes(m.PageFileUsed)) }.OfType<string>()),
            new Trace(m.MemoryHistory, 1), pressured));
        if (m.Battery is { } b)
        {
            var status = b.Charging ? L("正在充电") : b.PluggedIn ? b.Percent >= 99 ? L("已充满") : L("已接电源")
                : b.MinutesLeft is { } minutes ? L("约剩 %@", Duration(TimeSpan.FromMinutes(minutes))) : L("使用电池");
            Add(ReadingRow(L("电池"), $"{b.Percent}", "%", status, new Gauge(b.Percent / 100.0), b.Percent <= 20 && !b.PluggedIn));
        }
        else Add(ReadingRow(L("电源"), L("外接"), "", L("这台电脑没有电池"), new Control()));
        var free = Format.Bytes(model.Disk?.Available ?? 0).Split(' ');
        Add(ReadingRow(L("可用空间"), free[0], free.Length > 1 ? free[1] : "", model.Disk?.Name ?? "", new Gauge(model.Disk?.UsedFraction ?? 0)));
        var down = Rate(m.Download).Split(' ');
        Add(ReadingRow(L("网络"), down[0], down.Length > 1 ? down[1] : "", L("下载 · 上传 %@", Rate(m.Upload)), new Trace(m.DownloadHistory, null)));
        return Card(rows, padding: 8);
    }

    private static Control ReadingRow(string title, string value, string unit, string note, Control trace, bool warning = false)
    {
        var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("84,20,150,20,180,20,*"), Height = 52, Margin = new Thickness(12, 0) };
        grid.Children.Add(Text(title, 13, brush: Ink.Secondary).With(t => t.VerticalAlignment = VerticalAlignment.Center));
        var figure = H(4, Figures(value, 22), Text(unit, 12, brush: Ink.Secondary).With(t => { t.VerticalAlignment = VerticalAlignment.Bottom; t.Margin = new Thickness(0, 0, 0, 4); }));
        figure.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(figure, 2); grid.Children.Add(figure);
        trace.Height = 22; trace.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(trace, 4); grid.Children.Add(trace);
        var text = Text(note, 12, brush: warning ? Ink.Warning : Ink.Secondary).With(t => { t.HorizontalAlignment = HorizontalAlignment.Right; t.VerticalAlignment = VerticalAlignment.Center; });
        Grid.SetColumn(text, 6); grid.Children.Add(text);
        return grid;
    }

    private static Control Processes(AppModel model, SystemMonitor m)
    {
        Grid Columns() => new() { ColumnDefinitions = new ColumnDefinitions("*,90,150,70,34") };
        TextBlock Head(string text, int column)
        {
            var t = Text(text, 12, FontWeight.SemiBold, Ink.Tertiary);
            if (column > 0) t.HorizontalAlignment = HorizontalAlignment.Right;
            Grid.SetColumn(t, column);
            return t;
        }
        var header = Columns();
        header.Children.Add(Head(L("名称（%lld 个进程）", m.ProcessCount), 0));
        header.Children.Add(Head(L("内存"), 1));
        header.Children.Add(Head("% CPU", 2));
        header.Children.Add(Head("PID", 3));
        header.Margin = new Thickness(12, 8);
        var rows = V(0, header, new Hairline());
        foreach (var app in m.Apps)
        {
            var row = Columns();
            row.Children.Add(H(10, new Icon(IconData.AppWindow, 20, Ink.Tertiary) { VerticalAlignment = VerticalAlignment.Center },
                Text(app.Name, 13, FontWeight.Medium).With(t => t.VerticalAlignment = VerticalAlignment.Center)));
            var memory = Text(Format.Bytes(app.Memory), 12).With(t => { t.HorizontalAlignment = HorizontalAlignment.Right; t.VerticalAlignment = VerticalAlignment.Center; });
            Grid.SetColumn(memory, 1); row.Children.Add(memory);
            var busy = app.Cpu > 80;
            var cpu = H(8, new Bar(app.Cpu / 100, busy ? Ink.Danger : Ink.Secondary, 5) { Width = 64, VerticalAlignment = VerticalAlignment.Center },
                Text(app.Cpu.ToString("0.0"), 12, brush: busy ? Ink.Danger : Ink.Primary).With(t => { t.Width = 48; t.TextAlignment = TextAlignment.Right; }));
            cpu.HorizontalAlignment = HorizontalAlignment.Right; cpu.VerticalAlignment = VerticalAlignment.Center;
            Grid.SetColumn(cpu, 2); row.Children.Add(cpu);
            var pid = Figures(app.Pid.ToString(), 12, FontWeight.Normal).With(t => { t.Foreground = Ink.Secondary; t.HorizontalAlignment = HorizontalAlignment.Right; t.VerticalAlignment = VerticalAlignment.Center; });
            Grid.SetColumn(pid, 3); row.Children.Add(pid);
            if (app.Pid != Environment.ProcessId)
            {
                var more = new IconButton(IconData.X, () => model.RequestEndProcess(app.Pid, app.Name), 11) { HorizontalAlignment = HorizontalAlignment.Right };
                ToolTip.SetTip(more, L("结束 %@", app.Name));
                Grid.SetColumn(more, 4); row.Children.Add(more);
            }
            rows.Children.Add(new HoverSurface(row.Margin(12, 7, 12, 7), hovering => Ink.Fill(hovering ? 0.05 : 0), 8));
        }
        return Card(rows, padding: 8);
    }
}

/// A thin ink line of the recent values, newest on the right.
internal sealed class Trace(IReadOnlyList<double> values, double? ceiling) : Control
{
    public override void Render(DrawingContext g)
    {
        var size = Bounds.Size;
        g.DrawLine(new Pen(Ink.Stroke, 1), new Point(0, size.Height - 0.5), new Point(size.Width, size.Height - 0.5));
        if (values.Count < 2) return;
        var top = ceiling ?? Math.Max(values.Max(), 1);
        var step = size.Width / (values.Count - 1);
        var points = values.Select((v, i) => new Point(i * step, size.Height - 1 - (size.Height - 3) * Math.Min(1, v / top))).ToList();
        g.DrawGeometry(null, new Pen(Ink.Primary, 1.4, lineJoin: PenLineJoin.Round), PaperArt.Polygon(points, false));
    }
}

/// How full something is, as a flat ink bar.
internal sealed class Gauge(double fraction) : Control
{
    public override void Render(DrawingContext g)
    {
        var bar = new Rect(0, (Bounds.Height - 6) / 2, Bounds.Width, 6);
        g.FillRectangle(Ink.Raised, bar);
        g.FillRectangle(Ink.Primary, bar.WithWidth(bar.Width * Math.Clamp(fraction, 0, 1)));
    }
}
