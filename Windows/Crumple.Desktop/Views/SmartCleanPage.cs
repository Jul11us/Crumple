using Avalonia;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Media.Imaging;
using Avalonia.Platform;
using Crumple.Desktop.Art;
using Crumple.Desktop.Model;
using Crumple.Desktop.Ui;
using static Crumple.Desktop.Model.Strings;
using static Crumple.Desktop.Ui.Ui;

namespace Crumple.Desktop.Views;

/// Smart clean walks through: landing → scanning → results → (review) → cleaning → done.
internal static class SmartCleanPage
{
    public static Control Build(AppModel model) => model.SmartPhase switch
    {
        SmartPhase.Landing => Common.Landing(HeroStyle.SmartClean, L("智能清理"),
            L("找出临时文件、浏览器缓存、日志和多余的安装包，\n把它们揉成纸团，扔进纸篓。"),
            [L("临时文件"), L("浏览器缓存"), L("日志"), L("开发缓存"), L("安装包")], L("扫描"), model.StartSmartScan,
            model.LastSmartScan is { } last ? L("上次扫描：%@，发现 %@", Format.Ago(last), Format.Bytes(model.JunkFound)) : L("只会读取，不会动任何文件，放心扫描")),
        SmartPhase.Scanning => Scanning(model),
        SmartPhase.Results => Results(model),
        SmartPhase.Review => Review(model),
        SmartPhase.Cleaning => Cleaning(model),
        _ => Done(model),
    };

    private static Control Scanning(AppModel model)
    {
        var current = CategoryInfo.Junk.FirstOrDefault(x => !model.Revealed.Contains(x), (CategoryKind)(-1));
        var chips = new WrapPanel { HorizontalAlignment = HorizontalAlignment.Center, MaxWidth = 3 * 244 };
        foreach (var kind in CategoryInfo.Junk) chips.Children.Add(ScanChip(model, kind));
        return new DockPanel
        {
            Children =
            {
                new UiButton(L("停止扫描"), model.CancelSmartScan, ButtonKind.Secondary) { HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 24, 0, 40) }
                    .With(b => DockPanel.SetDock(b, Dock.Bottom)),
                V(0,
                    new ScanRing(model.ScanProgress, center: V(4,
                        Title(Format.Bytes(model.RevealedBytes), 34).With(t => t.HorizontalAlignment = HorizontalAlignment.Center),
                        Text(L("已发现"), 13, brush: Ink.Secondary).With(t => t.HorizontalAlignment = HorizontalAlignment.Center)))
                        { Width = 250, Height = 250, HorizontalAlignment = HorizontalAlignment.Center },
                    Title(L("正在扫描…"), 24).Margin(0, 34, 0, 0).With(t => t.HorizontalAlignment = HorizontalAlignment.Center),
                    Text((int)current >= 0 ? L("正在查看「%@」", current.Title()) : L("马上就好"), 13, brush: Ink.Secondary)
                        .Margin(0, 6, 0, 0).With(t => t.HorizontalAlignment = HorizontalAlignment.Center),
                    chips.Margin(0, 30, 0, 0)).With(v => v.VerticalAlignment = VerticalAlignment.Center),
            },
        };
    }

    private static Control ScanChip(AppModel model, CategoryKind kind)
    {
        var done = model.Revealed.Contains(kind);
        var trailing = done
            ? H(6, Text(Format.Bytes(model.CategoryFor(kind).TotalBytes), 12, FontWeight.SemiBold, Ink.Secondary).With(t => t.VerticalAlignment = VerticalAlignment.Center),
                new Icon(IconData.CircleCheck, 16, Ink.Accent, 1.8) { VerticalAlignment = VerticalAlignment.Center })
            : (Control)new ScanRing(0, indeterminate: true) { Width = 14, Height = 14, RenderTransform = new ScaleTransform(0.3, 0.3) };
        var card = Card(Row(H(10, new Icon(kind.Icon(), 22, Ink.Secondary) { VerticalAlignment = VerticalAlignment.Center },
            Text(kind.Title(), 13, FontWeight.Medium).With(t => t.VerticalAlignment = VerticalAlignment.Center)), trailing), radius: 12, padding: 10);
        card.Width = 232;
        card.Margin = new Thickness(6);
        card.Opacity = done ? 1 : 0.7;
        return card;
    }

    private static Control Results(AppModel model)
    {
        var selected = model.JunkSelectedBytes;
        var lines = V(0);
        foreach (var category in model.Junk) lines.Children.Add(ResultLine(model, category));
        lines.Children.Add(new DashedRule().Margin(0, 10, 0, 10));
        var total = new LeaderRow(L("合计"), Format.Bytes(selected), size: 16, weight: FontWeight.SemiBold) { Margin = new Thickness(12, 0) };
        ((TextBlock)total.Children[0]).FontSize = 14;
        ((TextBlock)total.Children[0]).FontWeight = FontWeight.SemiBold;
        ((TextBlock)total.Children[0]).Foreground = Ink.Primary;
        lines.Children.Add(total);

        var big = new CountUp(model.JunkFound, model.ResultsShownAt) { FontFamily = Ink.Serif, FontSize = 58, FontWeight = FontWeight.SemiBold, Foreground = Ink.Primary };
        var head = V(8,
            Text(L("扫描完成"), 13, FontWeight.Medium, Ink.Secondary),
            H(12, big, Text(L("可以清理"), 20, FontWeight.Medium, Ink.Secondary).With(t => { t.VerticalAlignment = VerticalAlignment.Bottom; t.Margin = new Thickness(0, 0, 0, 14); })),
            Text(L("已为你勾选 %@ 可以放心清理的内容。正在运行的应用和你自己的文件默认不动。", Format.Bytes(selected)), 13, brush: Ink.Secondary, wrap: true));

        var buttons = Row(
            new UiButton(L("重新扫描"), model.StartSmartScan, ButtonKind.Ghost, icon: IconData.RefreshCw) { VerticalAlignment = VerticalAlignment.Center },
            H(12, new UiButton(L("查看详情"), () => model.OpenReview(), ButtonKind.Secondary, large: true),
                new UiButton(L("清理 %@", Format.Bytes(selected)), model.RequestSmartClean, large: true, icon: IconData.Trash2).Disabled(model.JunkSelectedCount == 0)));
        buttons.Margin = new Thickness(0, 0, BasketGeometry.ReservedTrailing - 40, 0);
        DockPanel.SetDock(buttons, Dock.Bottom);
        DockPanel.SetDock(head, Dock.Top);
        var card = Card(lines, padding: 16).Margin(0, 28, 0, 16);
        DockPanel.SetDock(card, Dock.Top);
        return new DockPanel { Margin = new Thickness(40, 48, 40, 34), Children = { head, card, buttons, new Control() } };
    }

    private static Control ResultLine(AppModel model, Category category)
    {
        var empty = !category.Live.Any();
        var info = Text(empty ? L("很干净") : L("%lld 项 · 已选 %@", category.LiveCount, Format.Bytes(category.SelectedBytes)), 12, brush: Ink.Tertiary);
        var leader = new Grid { ColumnDefinitions = new ColumnDefinitions("Auto,Auto,*,Auto") };
        leader.Children.Add(Text(category.Kind.Title(), 14));
        info.Margin = new Thickness(6, 0, 0, 0); info.VerticalAlignment = VerticalAlignment.Bottom;
        Grid.SetColumn(info, 1); leader.Children.Add(info);
        var dots = new DottedLeader { VerticalAlignment = VerticalAlignment.Bottom, Margin = new Thickness(6, 0, 6, 4) };
        Grid.SetColumn(dots, 2); leader.Children.Add(dots);
        var size = Figures(Format.Bytes(category.TotalBytes), 14);
        Grid.SetColumn(size, 3); leader.Children.Add(size);
        var row = new Grid { ColumnDefinitions = new ColumnDefinitions("Auto,*,Auto") };
        var check = new CheckMark(category.Selection, () => { category.ToggleAll(); model.Notify(); })
            { VerticalAlignment = VerticalAlignment.Center, IsEnabled = !empty };
        row.Children.Add(check);
        leader.Margin = new Thickness(12, 0); leader.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(leader, 1); row.Children.Add(leader);
        var chevron = new Icon(IconData.ChevronRight, 12, Ink.Tertiary, 1.8) { VerticalAlignment = VerticalAlignment.Center, Opacity = empty ? 0 : 1 };
        Grid.SetColumn(chevron, 2); row.Children.Add(chevron);
        var line = new HoverRow(row, () => { if (!empty) model.OpenReview(category.Kind); }, !empty) { Height = 44, Opacity = empty ? 0.5 : 1 };
        return line;
    }

    private static Control Review(AppModel model)
    {
        var current = model.CategoryFor(model.ReviewKind);
        var side = V(3);
        foreach (var category in model.Junk) side.Children.Add(ReviewCategoryRow(model, category));
        var sideCard = Card(side, padding: 8);
        sideCard.Width = 236;
        sideCard.VerticalAlignment = VerticalAlignment.Stretch;

        var header = new Grid { ColumnDefinitions = new ColumnDefinitions("Auto,*,Auto") };
        header.Children.Add(new Icon(current.Kind.Icon(), 34, Ink.Secondary, 1.4) { VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(4) });
        var titleLine = H(10, Title(current.Kind.Title(), 22), Text(Format.Bytes(current.TotalBytes), 14, FontWeight.Medium, Ink.Secondary)
            .With(t => { t.VerticalAlignment = VerticalAlignment.Bottom; t.Margin = new Thickness(0, 0, 0, 4); }));
        var about = V(4, titleLine, Text(current.Kind.Summary(), 12, brush: Ink.Secondary, wrap: true),
            H(6, new Icon(IconData.Hand, 14, Ink.Accent, 1.6) { VerticalAlignment = VerticalAlignment.Center },
                Text(L("拖起任意一行，亲手甩进右下角的纸篓"), 12, FontWeight.Medium, Ink.Accent)).Margin(0, 2, 0, 0));
        about.Margin = new Thickness(16, 0);
        Grid.SetColumn(about, 1); header.Children.Add(about);
        var all = new UiButton(current.Selection == Model.CheckState.On ? L("全不选") : L("全选"), () => { current.ToggleAll(); model.Notify(); }, ButtonKind.Ghost)
            .Disabled(!current.Live.Any());
        Grid.SetColumn(all, 2); header.Children.Add(all);

        var list = new DockPanel { Children = { header.With(h => { DockPanel.SetDock(h, Dock.Top); h.Margin = new Thickness(0, 0, 0, 16); }), new ItemList(model, current) } };
        var body = new Grid { ColumnDefinitions = new ColumnDefinitions("236,16,*"), Margin = new Thickness(32, 16) };
        body.Children.Add(sideCard);
        Grid.SetColumn(list, 2); body.Children.Add(list);

        var top = Row(new UiButton(L("返回结果"), model.BackToResults, ButtonKind.Ghost, icon: IconData.ChevronLeft), null).Margin(32, 40, 32, 0);
        var bar = Common.ActionBar(model, L("已选择"), model.JunkSelectedBytes,
            L("%lld 项 · 来自 %lld 个类别", model.JunkSelectedCount, model.Junk.Count(x => x.SelectedRows.Any())),
            new UiButton(L("开始清理"), model.RequestSmartClean, large: true, icon: IconData.Trash2).Disabled(model.JunkSelectedCount == 0));
        DockPanel.SetDock(top, Dock.Top);
        DockPanel.SetDock(bar, Dock.Bottom);
        return new DockPanel { Children = { top, bar, body } };
    }

    private static Control ReviewCategoryRow(AppModel model, Category category)
    {
        var active = model.ReviewKind == category.Kind;
        var empty = !category.Live.Any();
        var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("Auto,Auto,*,Auto") };
        grid.Children.Add(new CheckMark(category.Selection, () => { category.ToggleAll(); model.Notify(); })
            { VerticalAlignment = VerticalAlignment.Center, IsEnabled = !empty });
        var icon = new Icon(category.Kind.Icon(), 20, Ink.Secondary) { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(10, 0, 0, 0) };
        Grid.SetColumn(icon, 1); grid.Children.Add(icon);
        var text = V(1, Text(category.Kind.Title(), 13, FontWeight.SemiBold),
            Text(empty ? L("很干净") : L("%lld/%lld 项已选", category.SelectedRows.Count(), category.LiveCount), 11, brush: Ink.Tertiary));
        text.Margin = new Thickness(10, 0, 4, 0);
        Grid.SetColumn(text, 2); grid.Children.Add(text);
        var size = Text(Format.Bytes(category.TotalBytes), 12, FontWeight.Medium, Ink.Secondary).With(t => t.VerticalAlignment = VerticalAlignment.Center);
        Grid.SetColumn(size, 3); grid.Children.Add(size);
        return new HoverRow(grid, () => { model.ReviewKind = category.Kind; model.Notify(); }, true, active ? 0.1 : 0)
            { Padding = new Thickness(10, 8), CornerRadius = new CornerRadius(11) };
    }

    private static Control Cleaning(AppModel model)
    {
        var current = model.CategoryFor(model.ReviewKind);
        var progress = model.CleanTotal > 0 ? (double)model.CleanDone / model.CleanTotal : 0;
        var head = V(12,
            Row(Title(L("正在揉纸团…"), 28), Text($"{model.CleanDone} / {model.CleanTotal}", 15, FontWeight.SemiBold, Ink.Secondary, Ink.Mono)
                .With(t => t.VerticalAlignment = VerticalAlignment.Bottom)),
            new Bar(progress, Ink.Accent),
            H(8, new Icon(current.Kind.Icon(), 18, Ink.Secondary) { VerticalAlignment = VerticalAlignment.Center },
                Text(L("正在清理「%@」", current.Kind.Title()), 13, brush: Ink.Secondary)));
        head.Margin = new Thickness(36, 48, 36, 0);
        var bar = Common.ActionBar(model, L("待清理"), model.JunkSelectedBytes, L("%lld 项", model.CleanTotal - model.CleanDone),
            H(6, new Icon(IconData.Sparkles, 16, Ink.Secondary) { VerticalAlignment = VerticalAlignment.Center }, Text(L("清理中"), 14, FontWeight.SemiBold, Ink.Secondary)));
        DockPanel.SetDock(head, Dock.Top);
        DockPanel.SetDock(bar, Dock.Bottom);
        return new DockPanel { Children = { head, bar, new ItemList(model, current) { Margin = new Thickness(32, 18) } } };
    }

    /// The finish screen: the freed space counts up, and a paper receipt prints out with the breakdown.
    private static Control Done(AppModel model)
    {
        var summary = model.LastSummary ?? new CleanSummary { Source = Crumple.Core.ScanKind.Smart };
        var canEmpty = summary.Count > 0 && !summary.TrashEmptied;
        var buttons = H(10, new UiButton(L("完成"), model.FinishSmartClean, large: true));
        if (canEmpty) buttons.Children.Add(new UiButton(L("清倒废纸篓"), model.RequestEmptyTrash, ButtonKind.Secondary, large: true));
        if (model.CanRestore(summary))
            buttons.Children.Add(new UiButton(L("撤销"), () => model.Restore(summary), ButtonKind.Secondary, large: true, icon: IconData.Undo2)
                .Tip(L("撤销：把这次扔掉的文件全部放回原处")));
        var left = V(0,
            new Border
            {
                Width = 112, Height = 112, CornerRadius = new CornerRadius(27), ClipToBounds = true, HorizontalAlignment = HorizontalAlignment.Left,
                Child = new Image { Source = new Bitmap(AssetLoader.Open(new Uri("avares://Crumple/Assets/icon-256.png"))), Width = 140, Height = 140, Stretch = Stretch.UniformToFill },
            },
            Text(summary.Count > 0 ? L("清理完成") : L("这次没有扔掉任何东西"), 15, FontWeight.SemiBold, Ink.Accent).Margin(0, 28, 0, 0),
            new CountUp(summary.Bytes, model.DoneAt, 1.2) { FontFamily = Ink.Serif, FontSize = 64, FontWeight = FontWeight.SemiBold, Foreground = Ink.Primary, Margin = new Thickness(0, 2, 0, 0) },
            Text(L("已扔进废纸篓"), 16, brush: Ink.Secondary),
            canEmpty ? Text(L("清倒废纸篓之后，这些空间才会真正腾出来。"), 12, brush: Ink.Tertiary).Margin(0, 12, 0, 0) : null,
            buttons.Margin(0, 32, 0, 0));
        left.Width = 330;
        left.VerticalAlignment = VerticalAlignment.Center;
        var receipt = new Receipt(model, summary) { Width = 350, VerticalAlignment = VerticalAlignment.Center };
        return H(64, left, receipt).With(h => { h.HorizontalAlignment = HorizontalAlignment.Center; h.VerticalAlignment = VerticalAlignment.Center; h.Margin = new Thickness(40, 0); });
    }
}

/// A row with a faint wash on hover that does something when clicked.
internal sealed class HoverRow : Pressable
{
    private readonly bool interactive;
    private readonly double active;
    public HoverRow(Control content, Action action, bool interactive, double active = 0) : base(action)
    {
        this.interactive = interactive;
        this.active = active;
        Child = content;
        Padding = new Thickness(12, 0);
        CornerRadius = new CornerRadius(8);
        Enabled = interactive;
        if (!interactive) Cursor = Avalonia.Input.Cursor.Default;
        Restyle();
    }

    protected override void Restyle() =>
        Background = Ink.Fill(Math.Max(active, Hovering && interactive ? 0.04 : 0));
}

/// A paper till receipt with the breakdown, slightly askew, with a torn bottom edge.
internal sealed class Receipt : Panel
{
    private static readonly IBrush InkBrush = new SolidColorBrush(Color.Parse("#2E2C29"));

    public Receipt(AppModel model, CleanSummary summary)
    {
        TextBlock T(string text, double size, FontWeight weight = FontWeight.Normal, double opacity = 1, FontFamily? font = null) =>
            Text(text, size, weight, InkBrush, font).With(t => t.Opacity = opacity);
        var lines = V(12,
            Row(T("Crumple", 15, FontWeight.SemiBold), T(summary.Finished.ToLocalTime().ToString("g"), 11, opacity: 0.6, font: Ink.Mono)),
            T(L("清理小票 · %@", model.SourceTitle(summary.Source)), 11, opacity: 0.55),
            new DashedRule(InkBrush));
        if (summary.Lines.Count == 0) lines.Children.Add(T(L("这次没有清理任何东西"), 13, opacity: 0.6));
        foreach (var (kind, (count, bytes)) in summary.Lines)
            lines.Children.Add(Row(H(8, T(kind.Title(), 13, FontWeight.Medium), T($"×{count}", 12, opacity: 0.45, font: Ink.Mono)),
                T(Format.Bytes(bytes), 13, FontWeight.Medium)));
        lines.Children.Add(new DashedRule(InkBrush));
        var figures = new Grid { ColumnDefinitions = new ColumnDefinitions("*,*,*") };
        (string, string)[] cells = [(L("纸团"), L("%lld 个", summary.Count)), (L("用时"), L("%@ 秒", Math.Round(summary.Seconds).ToString("0"))),
            (L("没扔进去"), L("%lld 项", summary.Failures.Count))];
        for (var i = 0; i < cells.Length; i++)
        {
            var cell = V(2, T(cells[i].Item1, 11, opacity: 0.55), T(cells[i].Item2, 14, FontWeight.SemiBold));
            Grid.SetColumn(cell, i);
            figures.Children.Add(cell);
        }
        lines.Children.Add(figures);
        foreach (var (name, reason) in summary.Failures.Take(3))
            lines.Children.Add(T($"· {name}：{reason}", 11, opacity: 0.6));
        if (summary.Failures.Count > 3) lines.Children.Add(T(L("· 还有 %lld 项", summary.Failures.Count - 3), 11, opacity: 0.6));
        lines.Children.Add(new DashedRule(InkBrush));
        lines.Children.Add(Row(T(L("合计"), 15, FontWeight.SemiBold), T(Format.Bytes(summary.Bytes), 28, FontWeight.SemiBold)));
        lines.Children.Add(T(L("已移到废纸篓"), 11, opacity: 0.55).With(t => t.HorizontalAlignment = HorizontalAlignment.Right));
        lines.Children.Add(new Barcode(unchecked((ulong)summary.Bytes + (ulong)summary.Count)) { Height = 36, Margin = new Thickness(0, 4, 0, 0) });
        lines.Children.Add(T(L("谢谢光临 · 把垃圾揉成纸团"), 11, opacity: 0.55).With(t => t.HorizontalAlignment = HorizontalAlignment.Center));
        lines.Margin = new Thickness(24, 24, 24, 34);
        Children.Add(new TornPaper());
        Children.Add(lines);
        RenderTransform = new RotateTransform(1.2);
    }
}

/// A receipt's outline: straight top, a torn zigzag bottom, and a soft shadow.
internal sealed class TornPaper : Control
{
    private static readonly IBrush Paper = new SolidColorBrush(Color.Parse("#F6F0E4"));

    public override void Render(DrawingContext context)
    {
        // Straight top, a torn zigzag bottom, and a soft shadow.
        var rect = new Rect(Bounds.Size);
        const double tooth = 8;
        var count = Math.Max(1, (int)(rect.Width / (tooth * 2)));
        var step = rect.Width / count;
        var points = new List<Point> { new(0, 0), new(rect.Width, 0), new(rect.Width, rect.Height - tooth) };
        for (var i = 0; i < count; i++)
        {
            var x = rect.Width - i * step;
            points.Add(new(x - step / 2, rect.Height));
            points.Add(new(x - step, rect.Height - tooth));
        }
        var shape = PaperArt.Polygon(points);
        for (var i = 3; i >= 1; i--)
            using (context.PushTransform(Matrix.CreateTranslation(0, 2 * i)))
                context.DrawGeometry(new SolidColorBrush(Color.FromArgb(7, 0, 0, 0)), new Pen(new SolidColorBrush(Color.FromArgb(7, 0, 0, 0)), i * 3), shape);
        context.DrawGeometry(Paper, null, shape);
    }
}

internal sealed class Barcode(ulong seed) : Control
{
    public override void Render(DrawingContext context)
    {
        var rng = new SeededRandom(seed | 1);
        var brush = new SolidColorBrush(Color.Parse("#2E2C29"));
        var x = 0.0;
        while (x < Bounds.Width)
        {
            var bar = Math.Round(rng.Range(1, 4));
            context.FillRectangle(brush, new Rect(x, 0, bar, Bounds.Height));
            x += bar + Math.Round(rng.Range(1.5, 4));
        }
    }
}
