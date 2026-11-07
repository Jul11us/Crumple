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

internal static class OverviewPage
{
    public static Control Build(AppModel model)
    {
        var content = V(24,
            V(8, Title(L("概览"), 30), Text(SystemInfo.Summary(model.Demo), 12, brush: Ink.Secondary)),
            StorageAndJunk(model),
            model.History.Count > 0 ? Recent(model) : null);
        content.Margin = new Thickness(32, 48, BasketGeometry.ReservedTrailing, 32);
        content.MaxWidth = 1440;
        content.HorizontalAlignment = HorizontalAlignment.Stretch;
        return Scroll(content);
    }

    public static ScrollViewer Scroll(Control content) => new()
    {
        Content = content,
        VerticalScrollBarVisibility = Avalonia.Controls.Primitives.ScrollBarVisibility.Auto,
        HorizontalScrollBarVisibility = Avalonia.Controls.Primitives.ScrollBarVisibility.Disabled,
    };

    private static Control StorageAndJunk(AppModel model)
    {
        var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("*,16,264") };
        grid.Children.Add(Storage(model));
        var junk = Junk(model);
        Grid.SetColumn(junk, 2);
        grid.Children.Add(junk);
        return grid;
    }

    private static Control Storage(AppModel model)
    {
        if (model.Disk is not { } disk) return Card(Text(L("读不到磁盘信息"), brush: Ink.Secondary), padding: 24);
        var scanned = model.LastSmartScan != null;
        var big = Title(Format.Bytes(disk.Available), 40);
        var caption = Text(L("可用 · 共 %@", Format.Bytes(disk.Total)), 13, brush: Ink.Secondary);
        caption.VerticalAlignment = VerticalAlignment.Bottom;
        caption.Margin = new Thickness(0, 0, 0, 9);
        return Card(V(20,
            Text(disk.Name, 13, FontWeight.Medium, Ink.Secondary),
            H(10, big, caption),
            new DiskRuler(disk, scanned ? model.JunkFound : 0),
            V(10,
                new LeaderRow(L("已使用"), Format.Bytes(disk.Used)),
                new LeaderRow(L("可以清理的垃圾"), scanned ? Format.Bytes(model.JunkFound) : L("尚未扫描")),
                new LeaderRow(L("可用空间"), Format.Bytes(disk.Available)))), padding: 24);
    }

    private static Control Junk(AppModel model)
    {
        Control body;
        if (model.LastSmartScan is { } last)
        {
            body = new DockPanel
            {
                Children =
                {
                    V(12, Text(L("智能清理"), 13, FontWeight.Medium, Ink.Secondary),
                        Title(Format.Bytes(model.JunkFound), 32),
                        Text(L("可以清理 · %@扫描", Format.Ago(last)), 12, brush: Ink.Secondary)).With(v => DockPanel.SetDock(v, Dock.Top)),
                    new UiButton(L("查看并清理"), model.ShowSmartResults) { VerticalAlignment = VerticalAlignment.Bottom },
                },
            };
        }
        else
        {
            body = new DockPanel
            {
                Children =
                {
                    V(12, Text(L("智能清理"), 13, FontWeight.Medium, Ink.Secondary),
                        Title(L("看看能腾出多少空间"), 22).With(t => t.TextWrapping = TextWrapping.Wrap),
                        Text(L("检查缓存、日志和安装包，清理前由你确认"), 12, brush: Ink.Secondary, wrap: true)).With(v => DockPanel.SetDock(v, Dock.Top)),
                    new UiButton(L("开始扫描"), model.StartSmartScan) { VerticalAlignment = VerticalAlignment.Bottom, Margin = new Thickness(0, 12, 0, 0) },
                },
            };
        }
        return Card(body, padding: 24, fill: Ink.AccentSurface);
    }

    private static Control Recent(AppModel model)
    {
        var rows = V(0);
        foreach (var receipt in model.History.Take(3)) rows.Children.Add(new HistoryRow(model, receipt));
        return V(12,
            Row(Text(L("最近清理"), 13, FontWeight.Medium, Ink.Secondary),
                new UiButton(L("全部记录"), () => model.Go(Model.Page.History), ButtonKind.Ghost)),
            Card(rows, padding: 8));
    }
}

/// The disk as a ruler: used space in ink, the junk found hatched at its end, tick marks every tenth.
internal sealed class DiskRuler(DiskInfo disk, long junk) : Control
{
    protected override Size MeasureOverride(Size availableSize) => new(0, 20);

    public override void Render(DrawingContext context)
    {
        const double barHeight = 10;
        var width = Bounds.Width;
        context.FillRectangle(Ink.Raised, new Rect(0, 0, width, barHeight));
        var used = width * disk.UsedFraction;
        context.FillRectangle(Ink.Primary, new Rect(0, 0, used, barHeight));
        var junkWidth = Math.Min(used, width * junk / Math.Max(disk.Total, 1.0));
        if (junkWidth > 1)
        {
            var rect = new Rect(used - junkWidth, 0, junkWidth, barHeight);
            context.FillRectangle(Ink.Base, rect);
            using (context.PushClip(rect))
            {
                var pen = new Pen(Ink.Primary, 1);
                for (var x = rect.X - barHeight; x <= rect.Right; x += 4)
                    context.DrawLine(pen, new Point(x, barHeight), new Point(x + barHeight, 0));
            }
        }
        var tick = new Pen(Ink.Tertiary, 1);
        for (var i = 0; i <= 10; i++)
        {
            var x = Math.Min(width - 0.5, Math.Max(0.5, width * i / 10));
            context.DrawLine(tick, new Point(x, barHeight + 3), new Point(x, barHeight + (i % 5 == 0 ? 9 : 6)));
        }
    }
}

internal sealed class HistoryRow : Border
{
    public HistoryRow(AppModel model, CleanupReceipt receipt)
    {
        var restored = receipt.Files.Count > 0 && receipt.Files.All(x => x.Restored);
        var parts = new List<string> { Format.Time(receipt.Date), L("%lld 个纸团", receipt.Files.Count) };
        if (receipt.Errors.Count > 0) parts.Add(L("%lld 项没扔进去", receipt.Errors.Count));
        parts.Add(L("扔进纸篓"));
        var title = H(6, Text(model.SourceTitle(receipt.Source), 13, FontWeight.Medium));
        if (restored) title.Children.Add(new Pill(L("已撤销"), Ink.Secondary));
        var size = Text(Format.Bytes(receipt.Bytes), 14, FontWeight.SemiBold, restored ? Ink.Tertiary : Ink.Primary);
        if (restored) size.TextDecorations = TextDecorations.Strikethrough;
        size.VerticalAlignment = VerticalAlignment.Center;
        var trailing = H(12, size);
        if (model.CanRestore(receipt))
            trailing.Children.Insert(0, new UiButton(L("放回"), () => model.Restore(receipt), ButtonKind.Ghost, icon: IconData.Undo2)
                { VerticalAlignment = VerticalAlignment.Center }.Tip(L("把这次扔掉的文件从废纸篓放回原处")));
        Child = Row(
            H(12, new Icon(model.SourceIcon(receipt.Source), 20) { Margin = new Thickness(5, 0), VerticalAlignment = VerticalAlignment.Center },
                V(2, title, Text(string.Join(" · ", parts), 12, brush: Ink.Tertiary))),
            trailing);
        Padding = new Thickness(10, 8);
    }
}

/// A small coloured capsule label.
internal sealed class Pill : Border
{
    public Pill(string text, IBrush color)
    {
        var solid = (color as ISolidColorBrush)?.Color ?? Colors.Gray;
        Child = Text(text, 10, FontWeight.SemiBold, color);
        Padding = new Thickness(6, 2);
        CornerRadius = new CornerRadius(20);
        Background = new SolidColorBrush(solid, 0.16);
        VerticalAlignment = VerticalAlignment.Center;
    }
}
