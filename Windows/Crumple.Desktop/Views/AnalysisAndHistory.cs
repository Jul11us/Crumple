using Avalonia;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;
using Crumple.Core;
using Crumple.Desktop.Art;
using Crumple.Desktop.Model;
using Crumple.Desktop.Platform;
using Crumple.Desktop.Ui;
using static Crumple.Desktop.Model.Strings;
using static Crumple.Desktop.Ui.Ui;

namespace Crumple.Desktop.Views;

/// Space analysis: what is taking up room in a folder, drilling down folder by folder.
internal static class AnalysisPage
{
    private static IBrush[] Palette => [.. CategoryInfo.Junk.Select(x => x.ChartBrush()), Ink.Fill(0.12)];

    public static Control Build(AppModel model)
    {
        var analyzer = model.Analyzer;
        if (analyzer.Trail.Count == 0) analyzer.Open(SpaceAnalyzer.Base.Home);
        var top = analyzer.Entries.Where(x => (x.Size ?? 0) > 0).Take(7).ToList();
        var largest = analyzer.Entries.Max(x => x.Size) ?? 0;

        var picker = H(0);
        foreach (var root in Enum.GetValues<SpaceAnalyzer.Base>())
            picker.Children.Add(new ChipButton(Text(analyzer.Title(root), 12, FontWeight.Medium, analyzer.Root == root ? Ink.Accent : Ink.Secondary)
                .With(t => t.VerticalAlignment = VerticalAlignment.Center), analyzer.Root == root, () => analyzer.Open(root)));
        var header = Row(V(6, Title(L("空间分析"), 30), Text(L("看看每个文件夹各占了多少，点进去一层层找。"), 13, brush: Ink.Secondary)),
            H(6, picker, new UiButton(L("重新计算"), analyzer.Rescan, ButtonKind.Ghost, icon: IconData.RefreshCw) { VerticalAlignment = VerticalAlignment.Center })
                .With(h => h.VerticalAlignment = VerticalAlignment.Bottom));

        var crumbs = H(4);
        for (var i = 0; i < analyzer.Trail.Count; i++)
        {
            var index = i;
            var last = i == analyzer.Trail.Count - 1;
            if (i > 0) crumbs.Children.Add(new Icon(IconData.ChevronRight, 11, Ink.Tertiary, 2) { VerticalAlignment = VerticalAlignment.Center });
            crumbs.Children.Add(new UiButton(i == 0 ? analyzer.Title(analyzer.Root) : Path.GetFileName(analyzer.Trail[i]), () => analyzer.GoBack(index), ButtonKind.Ghost));
            if (last && crumbs.Children[^1] is UiButton b) b.Opacity = 1;
        }

        var chart = new Panel
        {
            Width = 220, Height = 220,
            Children =
            {
                new Donut(top.Select(x => (double)(x.Size ?? 0)).ToArray(), Palette),
                V(2, Title(Format.Bytes(analyzer.Total), 24).With(t => t.HorizontalAlignment = HorizontalAlignment.Center),
                    Text(analyzer.Pending > 0 ? L("还在算 %lld 项…", analyzer.Pending) : L("共 %lld 项", analyzer.Entries.Count), 12, brush: Ink.Secondary)
                        .With(t => t.HorizontalAlignment = HorizontalAlignment.Center))
                    .With(v => { v.HorizontalAlignment = HorizontalAlignment.Center; v.VerticalAlignment = VerticalAlignment.Center; }),
            },
        };
        var legend = V(7);
        for (var i = 0; i < Math.Min(5, top.Count); i++)
        {
            var share = analyzer.Total > 0 ? $"{(double)(top[i].Size ?? 0) / analyzer.Total * 100:0}%" : "--";
            legend.Children.Add(Row(H(8, Shapes.Dot(8, Palette[i]).With(d => d.VerticalAlignment = VerticalAlignment.Center), Text(top[i].Name, 12).With(t => t.MaxWidth = 150)),
                Text(share, 12, FontWeight.Medium, Ink.Secondary)));
        }
        var side = Card(V(16, chart, legend), padding: 16);
        side.Width = 252;
        side.VerticalAlignment = VerticalAlignment.Top;

        var rows = V(2);
        foreach (var entry in analyzer.Entries)
        {
            var color = top.IndexOf(entry) is var k and >= 0 ? Palette[k] : null;
            rows.Children.Add(EntryRow(model, entry, largest, color));
        }
        var list = Card(Common.Scroll("analysis-" + analyzer.Current, rows.Margin(6, 6, 6, 6)), padding: 4);

        var body = new Grid { ColumnDefinitions = new ColumnDefinitions("252,16,*") };
        body.Children.Add(side);
        Grid.SetColumn(list, 2);
        body.Children.Add(list);
        var head = V(16, header, crumbs);
        DockPanel.SetDock(head, Dock.Top);
        body.Margin = new Thickness(0, 16, 0, 0);
        return new DockPanel { Margin = new Thickness(32, 48, BasketGeometry.ReservedTrailing, 32), Children = { head, body } };
    }

    private static Control EntryRow(AppModel model, SpaceAnalyzer.Entry entry, long largest, IBrush? color)
    {
        var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("Auto,*,84,Auto") };
        grid.Children.Add(entry.IsFolder ? new Icon(IconData.Folder, 24, Ink.Secondary, 1.4) { VerticalAlignment = VerticalAlignment.Center }
            : new FileGlyph(null, 28) { VerticalAlignment = VerticalAlignment.Center });
        var fraction = entry.Size is { } size && largest > 0 ? (double)size / largest : 0;
        var name = V(4, Text(entry.Name, 13, FontWeight.Medium), new Bar(fraction, color ?? Ink.Fill(0.35), 5));
        name.Margin = new Thickness(10, 0, 12, 0);
        Grid.SetColumn(name, 1); grid.Children.Add(name);
        var value = entry.Size is { } s2 ? Text(Format.Bytes(s2), 12, FontWeight.SemiBold) : (Control)new ScanRing(0, true) { Width = 14, Height = 14 };
        value.HorizontalAlignment = HorizontalAlignment.Right; value.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(value, 2); grid.Children.Add(value);
        var chevron = new Icon(IconData.ChevronRight, 12, Ink.Tertiary, 2) { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(8, 0, 0, 0), Opacity = entry.IsFolder ? 1 : 0 };
        Grid.SetColumn(chevron, 3); grid.Children.Add(chevron);
        var row = new HoverRow(grid, () => model.Analyzer.Open(entry), entry.IsFolder, 0) { Padding = new Thickness(12, 8), CornerRadius = new CornerRadius(10) };
        var reveal = new MenuItem { Header = L("在资源管理器中显示") };
        reveal.Click += (_, _) => { if (OperatingSystem.IsWindows()) Native.Reveal(entry.Path); };
        row.ContextMenu = new ContextMenu { Items = { reveal } };
        ToolTip.SetTip(row, model.Places.Display(entry.Path));
        return row;
    }
}

/// A ring chart with small gaps between its pieces.
internal sealed class Donut(double[] values, IBrush[] palette) : Control
{
    public override void Render(DrawingContext g)
    {
        const double line = 34;
        var rect = new Rect(Bounds.Size).Deflate(line / 2);
        var total = values.Sum();
        if (total <= 0) { g.DrawEllipse(null, new Pen(Ink.Fill(0.07), line), rect); return; }
        var r = rect.Width / 2;
        var c = rect.Center;
        var angle = -Math.PI / 2;
        const double gap = 0.03;
        for (var i = 0; i < values.Length; i++)
        {
            var sweep = values[i] / total * 2 * Math.PI;
            if (sweep > gap * 1.5)
            {
                var a0 = angle + gap / 2; var a1 = angle + sweep - gap / 2;
                var arc = new StreamGeometry();
                using (var ctx = arc.Open())
                {
                    ctx.BeginFigure(new Point(c.X + r * Math.Cos(a0), c.Y + r * Math.Sin(a0)), false);
                    ctx.ArcTo(new Point(c.X + r * Math.Cos(a1), c.Y + r * Math.Sin(a1)), new Size(r, r), 0, a1 - a0 > Math.PI, SweepDirection.Clockwise);
                    ctx.EndFigure(false);
                }
                g.DrawGeometry(null, new Pen(palette[i % palette.Length], line), arc);
            }
            angle += sweep;
        }
    }
}

internal static class HistoryPage
{
    public static Control Build(AppModel model)
    {
        if (model.History.Count == 0)
            return Common.Landing(HeroStyle.History, L("还没有清理记录"), L("每次清理都会记在这里：\n扔了多少、什么时候、用的是哪种方式。"),
                [], L("去清理"), model.StartSmartScan, "");

        var live = model.History.Where(x => !x.Files.All(f => f.Restored) || x.Files.Count == 0).ToList();
        var header = Row(V(6, Title(L("清理记录"), 30), Text(L("从第一次清理到现在，一共扔掉了这么多"), 13, brush: Ink.Secondary)),
            new UiButton(L("清空记录"), model.ClearHistory, ButtonKind.Ghost) { VerticalAlignment = VerticalAlignment.Bottom });
        var stats = new Grid { ColumnDefinitions = new ColumnDefinitions("*,16,*,16,*") };
        (string Label, string Value)[] cells = [(L("累计扔掉"), Format.Bytes(live.Sum(x => x.Bytes))),
            (L("清理次数"), L("%lld 次", model.History.Count)), (L("揉过的纸团"), L("%lld 个", live.Sum(x => x.Files.Count)))];
        for (var i = 0; i < cells.Length; i++)
        {
            var card = Card(V(12, Text(cells[i].Label, 12, brush: Ink.Secondary), Title(cells[i].Value, 28)), padding: 16);
            Grid.SetColumn(card, i * 2);
            stats.Children.Add(card);
        }

        var today = DateTime.Today;
        var days = Enumerable.Range(0, 14).Reverse().Select(offset => today.AddDays(-offset))
            .Select(day => (day, model.History.Where(x => x.Date.LocalDateTime.Date == day).Sum(x => x.Bytes))).ToArray();
        var chart = Card(V(12, Text(L("最近 14 天"), 13, FontWeight.SemiBold, Ink.Secondary), new DayBars(days) { Height = 170 }), radius: 20, padding: 20);

        var content = V(20, header, stats, chart);
        foreach (var group in model.History.GroupBy(x => x.Date.LocalDateTime.Date).OrderByDescending(x => x.Key))
        {
            var title = group.Key == today ? L("今天") : group.Key == today.AddDays(-1) ? L("昨天") : group.Key.ToString("M") + " " + group.Key.ToString("dddd");
            var rows = V(0);
            foreach (var receipt in group.OrderByDescending(x => x.Date)) rows.Children.Add(new HistoryRow(model, receipt));
            content.Children.Add(V(8, Text(title, 12, FontWeight.SemiBold, Ink.Tertiary).Margin(4, 0, 0, 0), Card(rows, padding: 6)));
        }
        content.Margin = new Thickness(40, 48, BasketGeometry.ReservedTrailing, 32);
        return Common.Scroll("history", content);
    }
}

/// Bars for the last two weeks; today in ink, the rest pale.
internal sealed class DayBars((DateTime Day, long Bytes)[] days) : Control
{
    public override void Render(DrawingContext g)
    {
        var max = days.Max(x => x.Bytes);
        var gb = max >= 1_000_000_000;
        var unit = gb ? 1_000_000_000.0 : 1_000_000.0;
        var top = Math.Max(1, Math.Ceiling(max / unit / 2) * 2);
        const double axis = 44, bottom = 20;
        var plot = new Rect(axis, 6, Bounds.Width - axis, Bounds.Height - bottom - 6);
        var grid = new Pen(Ink.Fill(0.07), 1);
        foreach (var fraction in new[] { 0.0, 0.5, 1.0 })
        {
            var y = plot.Bottom - plot.Height * fraction;
            g.DrawLine(grid, new Point(plot.X, y), new Point(plot.Right, y));
            var label = new FormattedText($"{top * fraction:0} {(gb ? "GB" : "MB")}", System.Globalization.CultureInfo.CurrentCulture,
                FlowDirection.LeftToRight, new Typeface(Ink.Sans), 10, Ink.Tertiary);
            g.DrawText(label, new Point(0, y - label.Height / 2));
        }
        var slot = plot.Width / days.Length;
        for (var i = 0; i < days.Length; i++)
        {
            var h = days[i].Bytes / unit / top * plot.Height;
            var x = plot.X + slot * i + slot * 0.2;
            if (h > 0.5) g.DrawRectangle(days[i].Day == DateTime.Today ? Ink.Accent : Ink.Fill(0.18), null, new Rect(x, plot.Bottom - h, slot * 0.6, h), 3, 3);
            if (i % 2 == 1)
            {
                var label = new FormattedText(days[i].Day.ToString("M/d"), System.Globalization.CultureInfo.CurrentCulture,
                    FlowDirection.LeftToRight, new Typeface(Ink.Sans), 10, Ink.Tertiary);
                g.DrawText(label, new Point(x + slot * 0.3 - label.Width / 2, plot.Bottom + 4));
            }
        }
    }
}
