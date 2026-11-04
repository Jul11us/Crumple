using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.VisualTree;
using Crumple.Desktop.Model;
using Crumple.Desktop.Platform;
using Crumple.Desktop.Ui;
using static Crumple.Desktop.Model.Strings;
using static Crumple.Desktop.Ui.Ui;

namespace Crumple.Desktop.Views;

/// A scrolling list of rows on a card. Rows can be ticked, or dragged and thrown at the basket.
internal sealed class ItemList : Border
{
    public ItemList(AppModel model, Category category)
    {
        var rows = model.VisibleRows(category);
        var cleaningHere = model.CleaningKind == category.Kind;
        CornerRadius = new CornerRadius(18);
        Background = Ink.Card;
        BorderBrush = Ink.Stroke;
        BorderThickness = new Thickness(1);
        ClipToBounds = true;
        if (rows.Count == 0)
        {
            Child = Placeholder(category.Scanning, cleaningHere);
        }
        else
        {
            var stack = new StackPanel { Spacing = 2, Margin = new Thickness(8) };
            foreach (var row in rows) stack.Children.Add(new ItemRow(model, row, category));
            // A fresh scroll position when cleaning starts, so the queue starts at the top.
            var key = $"list-{category.Kind}-{cleaningHere}";
            Child = Common.Scroll(key, stack);
            IsHitTestVisible = !model.IsCleaning;
        }
        LayoutUpdated += (_, _) =>
        {
            if (this.FindAncestorOfType<MainView>() is { } stage && this.TranslatePoint(default, stage) is { } origin)
                model.ListViewport = new Rect(origin, Bounds.Size);
        };
    }

    private static Control Placeholder(bool scanning, bool cleaning) => V(10,
        scanning ? Text(L("正在扫描…"), brush: Ink.Secondary) : new Icon(IconData.Sparkles, 38, Ink.Accent, 1.4) { HorizontalAlignment = HorizontalAlignment.Center },
        scanning ? null : Text(cleaning ? L("这一类清完了") : L("这里很干净"), 15, FontWeight.SemiBold).With(t => t.HorizontalAlignment = HorizontalAlignment.Center),
        scanning ? null : Text(cleaning ? L("接着清理下一类…") : L("没有发现可以清理的文件"), 12, brush: Ink.Secondary).With(t => t.HorizontalAlignment = HorizontalAlignment.Center))
        .With(v => { v.HorizontalAlignment = HorizontalAlignment.Center; v.VerticalAlignment = VerticalAlignment.Center; v.Margin = new Thickness(0, 0, 0, 20); });
}

internal sealed class ItemRow : Border
{
    private readonly AppModel model;
    private readonly CleanRow row;
    private readonly Category category;
    private readonly Control icon;
    private Point? pressedAt;
    private bool dragging;
    private readonly List<(double Time, Point Point)> samples = [];

    public ItemRow(AppModel model, CleanRow row, Category category)
    {
        this.model = model;
        this.row = row;
        this.category = category;
        // Files look like sheets of paper; a folder of cache shows its group's icon.
        var isFile = row.Files.Count == 1 && row.Files[0].Path == row.Path;
        icon = isFile
            ? new FileGlyph(CategoryInfo.TagOf(row.Path) is var tag && tag != FileTag.Other ? tag.Icon() : row.Name.EndsWith(".jpg", StringComparison.OrdinalIgnoreCase)
                || row.Name.EndsWith(".png", StringComparison.OrdinalIgnoreCase) ? IconData.Image : null, 32) { VerticalAlignment = VerticalAlignment.Center }
            : new Icon(category.Kind.Icon(), 26, Ink.Secondary, 1.4) { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(3) };

        var title = H(6, Text(row.Name, 13, FontWeight.Medium).With(t => t.MaxWidth = 460));
        if (row.Badge != null) title.Children.Add(new Pill(row.Badge, Ink.Accent));
        if (row.Status == RowStatus.Failed) title.Children.Add(new Pill(L("没扔进去"), Ink.Danger));
        var text = V(3, title, Text(row.Detail, 11, brush: Ink.Tertiary).With(t => t.TextTrimming = TextTrimming.PrefixCharacterEllipsis));
        text.VerticalAlignment = VerticalAlignment.Center;
        var size = Text(Format.Bytes(row.Size), 13, FontWeight.SemiBold, Ink.B(Ink.Palette.Primary, 0.85));
        size.VerticalAlignment = VerticalAlignment.Center;

        var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("Auto,Auto,*,Auto") };
        var check = new CheckMark(row.Selected ? CheckState.On : CheckState.Off, () => { row.Selected = !row.Selected; model.Notify(); })
            { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 12, 0) };
        grid.Children.Add(check);
        Grid.SetColumn(icon, 1); grid.Children.Add(icon);
        text.Margin = new Thickness(12, 0);
        Grid.SetColumn(text, 2); grid.Children.Add(text);
        Grid.SetColumn(size, 3); grid.Children.Add(size);
        Child = grid;
        Padding = new Thickness(12, 8);
        CornerRadius = new CornerRadius(11);
        Background = Brushes.Transparent;
        // Hidden (not removed) while its paper is in the air.
        Opacity = row.Status == RowStatus.Tossed ? 0 : 1;
        Cursor = new Cursor(StandardCursorType.Hand);
        PointerEntered += (_, _) => Background = Ink.Fill(0.06);
        PointerExited += (_, _) => Background = Brushes.Transparent;
        ToolTip.SetTip(this, row.Badge == L("运行中") ? L("这个应用正在运行，它的缓存投不进纸篓，先退出它再试") : model.Places.Display(row.Path));
        ContextMenu = Menu();
        LayoutUpdated += (_, _) =>
        {
            if (this.FindAncestorOfType<MainView>() is { } stage && icon.TranslatePoint(default, stage) is { } p)
                model.IconFrames[row.Id] = new Rect(p, icon.Bounds.Size);
        };
    }

    private ContextMenu Menu()
    {
        var items = new List<MenuItem>
        {
            Item(L("扔进纸篓"), () => model.ThrowAway(row, category), !model.IsCleaning),
            Item(L("在资源管理器中显示"), () => Reveal(row.Path)),
        };
        if (row.Keeper is { } keeper) items.Add(Item(L("显示保留的那一份"), () => Reveal(keeper)));
        items.Add(Item(L("忽略，以后不再列出"), () => model.Ignore(row, category)));
        var menu = new ContextMenu();
        foreach (var item in items) menu.Items.Add(item);
        return menu;
    }

    private static MenuItem Item(string title, Action action, bool enabled = true)
    {
        var item = new MenuItem { Header = title, IsEnabled = enabled };
        item.Click += (_, _) => action();
        return item;
    }

    private static void Reveal(string path)
    {
        if (OperatingSystem.IsWindows()) Native.Reveal(path);
    }

    private MainView? Stage => this.FindAncestorOfType<MainView>();

    protected override void OnPointerPressed(PointerPressedEventArgs e)
    {
        base.OnPointerPressed(e);
        if (!e.GetCurrentPoint(this).Properties.IsLeftButtonPressed || e.Handled) return;
        pressedAt = e.GetPosition(Stage);
        samples.Clear();
        e.Pointer.Capture(this);
    }

    protected override void OnPointerMoved(PointerEventArgs e)
    {
        base.OnPointerMoved(e);
        if (pressedAt is not { } start || Stage is not { } stage) return;
        var location = e.GetPosition(stage);
        samples.Add((Art.M.Now, location));
        if (samples.Count > 8) samples.RemoveAt(0);
        if (!dragging)
        {
            if (Math.Abs(location.X - start.X) + Math.Abs(location.Y - start.Y) < 4) return;
            dragging = true;
            var origin = model.IconFrames.TryGetValue(row.Id, out var frame) ? frame.Center : location;
            model.BeginToss(row, category, origin, location);
            Opacity = 0;
        }
        model.MoveToss(location);
    }

    protected override void OnPointerReleased(PointerReleasedEventArgs e)
    {
        base.OnPointerReleased(e);
        var wasDragging = dragging;
        dragging = false;
        pressedAt = null;
        e.Pointer.Capture(null);
        if (wasDragging) { model.EndToss(Velocity()); return; }
        if (e.InitialPressMouseButton == MouseButton.Left && new Rect(Bounds.Size).Contains(e.GetPosition(this)))
        {
            row.Selected = !row.Selected;
            model.Notify();
        }
    }

    protected override void OnPointerCaptureLost(PointerCaptureLostEventArgs e)
    {
        base.OnPointerCaptureLost(e);
        if (dragging) { dragging = false; pressedAt = null; model.EndToss(default); }
    }

    /// How fast the pointer was moving when it let go, in points per second.
    private Vector Velocity()
    {
        if (samples.Count < 2) return default;
        var last = samples[^1];
        var first = samples.LastOrDefault(s => last.Time - s.Time >= 0.03, samples[0]);
        var dt = Math.Max(0.008, last.Time - first.Time);
        return new Vector(last.Point.X - first.Point.X, last.Point.Y - first.Point.Y) / dt;
    }
}
