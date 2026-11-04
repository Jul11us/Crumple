using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using Avalonia.Input;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Threading;
using Crumple.Desktop.Art;
using Crumple.Desktop.Model;
using Crumple.Desktop.Ui;
using static Crumple.Desktop.Model.Strings;
using static Crumple.Desktop.Ui.Ui;

namespace Crumple.Desktop.Views;

internal enum HeroStyle { SmartClean, LargeFiles, Duplicates, Apps, History }

internal static class Common
{
    private static readonly Dictionary<string, Vector> scrollOffsets = [];

    /// A scroll view that keeps its place when the page is rebuilt.
    public static ScrollViewer Scroll(string key, Control content)
    {
        var viewer = new ScrollViewer
        {
            Content = content,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
        };
        if (scrollOffsets.TryGetValue(key, out var saved) && saved != default)
        {
            void Restore(object? sender, EventArgs e)
            {
                if (viewer.Extent.Height <= 0) return;
                viewer.LayoutUpdated -= Restore;
                viewer.Offset = saved;
            }
            viewer.LayoutUpdated += Restore;
        }
        viewer.ScrollChanged += (_, _) => scrollOffsets[key] = viewer.Offset;
        return viewer;
    }

    public static void ForgetScroll(string key) => scrollOffsets.Remove(key);

    /// The paper object sits beside the task, with a single conventional action.
    public static Control Landing(HeroStyle hero, string title, string subtitle, string[] chips, string buttonTitle,
        Action action, string footer)
    {
        var text = V(24,
            V(16, Title(title, 36), Text(subtitle.Replace("\n", " "), 14, brush: Ink.Secondary, wrap: true).With(t => t.LineHeight = 24)),
            chips.Length > 0 ? Text(string.Join("  ·  ", chips), 13, brush: Ink.Tertiary) : null,
            new UiButton(buttonTitle, action, large: true),
            Text(footer, 12, brush: Ink.Tertiary, wrap: true));
        text.VerticalAlignment = VerticalAlignment.Center;
        var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("*,32,360"), VerticalAlignment = VerticalAlignment.Center };
        grid.Children.Add(text);
        var scene = new HeroScene(hero) { Width = 360, Height = 280 };
        Grid.SetColumn(scene, 2);
        grid.Children.Add(scene);
        return new Border { Child = grid, Padding = new Thickness(40, 48) };
    }

    /// Scanning screen for the large-files, duplicates and uninstaller pages.
    public static Control ListScanning(AppModel model, Model.Page page, string title, string detail) => new DockPanel
    {
        Children =
        {
            V(0, new UiButton(L("停止扫描"), () => model.CancelScan(page), ButtonKind.Secondary) { HorizontalAlignment = HorizontalAlignment.Center })
                .Margin(0, 24, 0, 40).With(v => DockPanel.SetDock(v, Dock.Bottom)),
            V(0,
                new ScanRing(0, indeterminate: true, center: new Icon(page.Icon(), 54, Ink.Accent, 1.6)) { Width = 220, Height = 220, HorizontalAlignment = HorizontalAlignment.Center },
                Title(title, 24).Margin(0, 34, 0, 0).With(t => t.HorizontalAlignment = HorizontalAlignment.Center),
                Text(detail, 13, brush: Ink.Secondary).Margin(0, 6, 0, 0).With(t => t.HorizontalAlignment = HorizontalAlignment.Center))
                .With(v => v.VerticalAlignment = VerticalAlignment.Center),
        },
    };

    /// Bottom bar of the list pages: what's selected, the main button, and the running total. Leaves room for the basket.
    public static Control ActionBar(AppModel model, string label, long bytes, string detail, Control button)
    {
        var freed = V(2,
            Text(L("本次已扔掉"), 11, brush: Ink.Secondary).With(t => t.HorizontalAlignment = HorizontalAlignment.Right),
            Text(Format.Bytes(model.SessionFreed), 17, FontWeight.SemiBold, Ink.Accent).With(t => t.HorizontalAlignment = HorizontalAlignment.Right));
        freed.MinWidth = 84;
        freed.VerticalAlignment = VerticalAlignment.Center;
        button.VerticalAlignment = VerticalAlignment.Center;
        var row = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto,22,Auto") };
        row.Children.Add(V(2, Text(label, 12, brush: Ink.Secondary), Title(Format.Bytes(bytes), 28), Text(detail, 12, brush: Ink.Secondary))
            .With(v => v.VerticalAlignment = VerticalAlignment.Center));
        Grid.SetColumn(button, 1);
        row.Children.Add(button);
        Grid.SetColumn(freed, 3);
        row.Children.Add(freed);
        return new Border
        {
            Child = row, Height = 124, Background = Ink.Base,
            Padding = new Thickness(32, 0, BasketGeometry.ReservedTrailing, 0),
            BorderBrush = Ink.Stroke, BorderThickness = new Thickness(0, 1, 0, 0),
        };
    }

    /// Shown on list pages after a cleaning run.
    public static Control SummaryBanner(AppModel model, CleanSummary summary)
    {
        var parts = new List<string>();
        if (summary.Failures.Count > 0) parts.Add(L("%lld 项没扔进去。", summary.Failures.Count));
        parts.Add(summary.TrashEmptied ? L("废纸篓已清倒，空间已释放。") : L("文件在废纸篓里，清倒后才会真正释放空间。"));
        var trailing = H(8);
        if (model.CanRestore(summary))
            trailing.Children.Add(new UiButton(L("撤销"), () => model.Restore(summary), ButtonKind.Secondary, icon: IconData.Undo2).Tip(L("把这次扔掉的文件从废纸篓放回原处")));
        if (!summary.TrashEmptied && summary.Count > 0)
            trailing.Children.Add(new UiButton(L("清倒废纸篓"), model.RequestEmptyTrash, ButtonKind.Secondary));
        trailing.Children.Add(new IconButton(IconData.X, () => { model.Banner = null; model.Notify(); }) { VerticalAlignment = VerticalAlignment.Center });
        return Card(Row(
            H(12, new Icon(summary.Count > 0 ? IconData.CircleCheck : IconData.TriangleAlert, 22, summary.Count > 0 ? Ink.Accent : Ink.Warning, 1.8)
                { VerticalAlignment = VerticalAlignment.Center },
                V(2, Text(L("揉了 %lld 个纸团，共 %@", summary.Count, Format.Bytes(summary.Bytes)), 13, FontWeight.SemiBold),
                    Text(string.Join(" ", parts), 12, brush: Ink.Secondary))),
            trailing), radius: 14, padding: 12);
    }

    public static Control FilterChip(string title, string? icon, int count, bool selected, Action action)
    {
        var content = H(6,
            icon == null ? null : new Icon(icon, 14, selected ? Ink.Accent : Ink.Secondary) { VerticalAlignment = VerticalAlignment.Center },
            Text(title, 12, FontWeight.Medium, selected ? Ink.Accent : Ink.Secondary).With(t => t.VerticalAlignment = VerticalAlignment.Center),
            Text(count.ToString(), 12, FontWeight.Medium, Ink.Tertiary, Ink.Mono).With(t => t.VerticalAlignment = VerticalAlignment.Center));
        return new ChipButton(content, selected, action);
    }
}

internal sealed class ChipButton : Pressable
{
    private readonly bool selected;
    public ChipButton(Control content, bool selected, Action action) : base(action)
    {
        this.selected = selected;
        Child = content;
        Height = 32;
        Padding = new Thickness(12, 0);
        CornerRadius = new CornerRadius(8);
        BorderThickness = new Thickness(1);
        Restyle();
    }

    protected override void Restyle()
    {
        Background = selected ? Ink.AccentSurface : Hovering ? Ink.Fill(0.04) : Brushes.Transparent;
        BorderBrush = selected ? Ink.Stroke : Brushes.Transparent;
    }
}

internal sealed class IconButton : Pressable
{
    public IconButton(string icon, Action action, double size = 12) : base(action)
    {
        Child = new Icon(icon, size, Ink.Secondary, 1.8);
        Padding = new Thickness(6);
    }
}

/// Determinate scans show progress; only an indeterminate scan needs a moving arc.
internal sealed class ScanRing : Panel
{
    public ScanRing(double progress, bool indeterminate = false, Control? center = null)
    {
        Children.Add(new RingArc(progress, indeterminate));
        if (center != null)
        {
            center.HorizontalAlignment = HorizontalAlignment.Center;
            center.VerticalAlignment = VerticalAlignment.Center;
            Children.Add(center);
        }
    }
}

internal sealed class RingArc : Control
{
    private readonly double progress;
    private readonly bool indeterminate;

    public RingArc(double progress, bool indeterminate)
    {
        this.progress = progress;
        this.indeterminate = indeterminate;
        if (!indeterminate) return;
        var timer = new DispatcherTimer(TimeSpan.FromMilliseconds(33), DispatcherPriority.Render, (_, _) => InvalidateVisual());
        AttachedToVisualTree += (_, _) => timer.Start();
        DetachedFromVisualTree += (_, _) => timer.Stop();
    }

    public override void Render(DrawingContext context)
    {
        var line = Math.Min(14, Bounds.Width / 8);
        var rect = new Rect(Bounds.Size).Deflate(line / 2);
        context.DrawEllipse(null, new Pen(Ink.Fill(0.07), line), rect);
        double start, sweep;
        if (indeterminate)
        {
            start = M.Now % 2.4 / 2.4 * 2 * Math.PI;
            sweep = 0.28 * 2 * Math.PI;
        }
        else
        {
            start = -Math.PI / 2;
            sweep = Math.Max(0.001, progress) * 2 * Math.PI;
        }
        if (sweep >= 2 * Math.PI - 0.001) { context.DrawEllipse(null, new Pen(Ink.Accent, line), rect); return; }
        var r = rect.Width / 2;
        var c = rect.Center;
        var a = new Point(c.X + r * Math.Cos(start), c.Y + r * Math.Sin(start));
        var b = new Point(c.X + r * Math.Cos(start + sweep), c.Y + r * Math.Sin(start + sweep));
        var arc = new StreamGeometry();
        using (var g = arc.Open())
        {
            g.BeginFigure(a, false);
            g.ArcTo(b, new Size(r, r), 0, sweep > Math.PI, SweepDirection.Clockwise);
            g.EndFigure(false);
        }
        context.DrawGeometry(null, new Pen(Ink.Accent, line, lineCap: PenLineCap.Round), arc);
    }
}

/// A still life of files and the paper basket, beside the landing text.
internal sealed class HeroScene(HeroStyle style) : Control
{
    public override void Render(DrawingContext g)
    {
        var scale = Math.Min(Bounds.Width / 520, Bounds.Height / 260);
        using var _ = g.PushTransform(Matrix.CreateScale(scale, scale) *
            Matrix.CreateTranslation((Bounds.Width - 520 * scale) / 2, (Bounds.Height - 260 * scale) / 2));
        Draw(g, new Size(520, 260), style);
    }

    public static void Draw(DrawingContext g, Size size, HeroStyle style)
    {
        var cx = size.Width / 2;
        var (basketWidth, basketX, pile) = style switch
        {
            HeroStyle.SmartClean => (150.0, cx, 6),
            HeroStyle.LargeFiles => (112.0, cx + 105, 4),
            HeroStyle.Duplicates => (112.0, cx + 120, 3),
            HeroStyle.Apps => (118.0, cx, 4),
            _ => (150.0, cx, 14),
        };
        var basketHeight = basketWidth * BasketGeometry.Size.Height / BasketGeometry.Size.Width;
        var basket = new BasketGeometry(new Rect(basketX - basketWidth / 2, size.Height - basketHeight - 16, basketWidth, basketHeight));
        BasketArt.DrawBack(g, basket, BasketStyle.App);
        BasketArt.DrawPile(g, basket, pile, 1);
        BasketArt.DrawFront(g, basket, BasketStyle.App);

        switch (style)
        {
            case HeroStyle.SmartClean:
                Point[] spots = [new(cx - 112, 82), new(cx, 46), new(cx + 112, 82)];
                for (var i = 0; i < spots.Length; i++)
                    PaperArt.Draw(g, new PaperPose(spots[i], i, 1.3, 1, 1, 1, PaperPhase.Flying), (ulong)(50 + i), face: false);
                PaperArt.Draw(g, new PaperPose(new Point(cx - 172, 156), -0.32, 1, 0.35, 1, 1, PaperPhase.Crumpling), 61);
                break;
            case HeroStyle.LargeFiles:
                for (var i = 0; i < 3; i++)
                {
                    var offset = i - 1.0;
                    PaperArt.Draw(g, new PaperPose(new Point(cx - 80 + offset * 58, 118 + Math.Abs(offset) * 14), offset * 0.26, 1, 0, 1.6, 1,
                        PaperPhase.Crumpling), (ulong)(70 + i));
                }
                PaperArt.Draw(g, new PaperPose(new Point(basketX - 6, basket.Mouth.Y - 34), 0, 1.1, 1, 1, 1, PaperPhase.Flying), 77, face: false);
                break;
            case HeroStyle.Duplicates:
                PaperArt.Draw(g, new PaperPose(new Point(cx - 150, 122), -0.12, 1, 0, 1.6, 1, PaperPhase.Crumpling), 81);
                g.DrawRectangle(Ink.B(Ink.Palette.Secondary, 0.8), null, new Rect(cx - 104, 112, 22, 5), 2.5, 2.5);
                g.DrawRectangle(Ink.B(Ink.Palette.Secondary, 0.8), null, new Rect(cx - 104, 124, 22, 5), 2.5, 2.5);
                PaperArt.Draw(g, new PaperPose(new Point(cx - 34, 116), 0.16, 1, 0.22, 1.6, 1, PaperPhase.Crumpling), 81);
                PaperArt.Draw(g, new PaperPose(new Point(basketX - 4, basket.Mouth.Y - 34), 0, 1.1, 1, 1, 1, PaperPhase.Flying), 83, face: false);
                break;
            case HeroStyle.Apps:
                // App tiles in a gentle arc above the basket.
                const int count = 5;
                for (var i = 0; i < count; i++)
                {
                    var fraction = (double)i / (count - 1);
                    var spread = (fraction - 0.5) * 2;
                    var center = new Point(cx + spread * 150, 62 + spread * spread * 40);
                    var side = i == count / 2 ? 74.0 : 58.0;
                    using (g.PushTransform(Matrix.CreateRotation((fraction - 0.5) * 0.3) * Matrix.CreateTranslation(center.X, center.Y)))
                    {
                        var tile = new Rect(-side / 2, -side / 2, side, side);
                        g.DrawRectangle(new SolidColorBrush(Color.FromArgb(40, 0, 0, 0)), null, tile.Translate(new Vector(0, 4)).Inflate(2), side * 0.24, side * 0.24);
                        g.DrawRectangle(Ink.Card, new Pen(Ink.Stroke, 1), tile, side * 0.22, side * 0.22);
                        var glyph = side * 0.5;
                        using (g.PushTransform(Matrix.CreateScale(glyph / 24, glyph / 24) * Matrix.CreateTranslation(-glyph / 2, -glyph / 2)))
                            g.DrawGeometry(null, new Pen(Ink.Secondary, 1.5, lineCap: PenLineCap.Round, lineJoin: PenLineJoin.Round),
                                Geometry.Parse(i % 2 == 0 ? IconData.AppWindow : IconData.LayoutGrid));
                    }
                }
                break;
        }
    }
}

/// A dashed rule, like the tear line on a receipt.
internal sealed class DashedRule : Control
{
    private readonly IBrush? brush;
    public DashedRule(IBrush? brush = null) { this.brush = brush; Height = 2; Opacity = 0.35; }
    public override void Render(DrawingContext context) =>
        context.DrawLine(new Pen(brush ?? Ink.Primary, 1.2, new DashStyle([4 / 1.2, 4 / 1.2], 0)), new Point(0, 1), new Point(Bounds.Width, 1));
}

/// A number that counts up from zero, then stops redrawing.
internal sealed class CountUp : TextBlock
{
    public CountUp(long bytes, DateTimeOffset start, double duration = 1.1)
    {
        Text = Format.Bytes((long)(bytes * M.EaseOutCubic(M.Clamp01((DateTimeOffset.Now - start).TotalSeconds / duration))));
        var timer = new DispatcherTimer(DispatcherPriority.Render) { Interval = TimeSpan.FromMilliseconds(33) };
        timer.Tick += (_, _) =>
        {
            var t = M.Clamp01((DateTimeOffset.Now - start).TotalSeconds / duration);
            Text = Format.Bytes((long)(bytes * M.EaseOutCubic(t)));
            if (t >= 1) timer.Stop();
        };
        AttachedToVisualTree += (_, _) => timer.Start();
        DetachedFromVisualTree += (_, _) => timer.Stop();
    }
}

/// A document icon in the paper style: a white sheet with a folded corner and a small glyph for its kind.
internal sealed class FileGlyph : Control
{
    private readonly Geometry? glyph;
    public FileGlyph(string? glyph, double size = 32)
    {
        this.glyph = glyph == null ? null : Geometry.Parse(glyph);
        Width = Height = size;
        IsHitTestVisible = false;
    }

    public override void Render(DrawingContext g)
    {
        var s = Bounds.Height / 32;
        var w = 24 * s; var h = 30 * s; var f = 7 * s;
        var x = (Bounds.Width - w) / 2; var y = 1 * s;
        var sheet = PaperArt.Polygon([new(x, y), new(x + w - f, y), new(x + w, y + f), new(x + w, y + h), new(x, y + h)]);
        using (g.PushTransform(Matrix.CreateTranslation(0, 0.8 * s)))
            g.DrawGeometry(new SolidColorBrush(Color.FromArgb(28, 0, 0, 0)), null, sheet);
        g.DrawGeometry(new SolidColorBrush(Color.FromRgb(0xFB, 0xFB, 0xFA)), new Pen(new SolidColorBrush(Color.FromArgb(40, 0, 0, 0)), 0.8), sheet);
        g.DrawGeometry(new SolidColorBrush(Color.FromRgb(0xE4, 0xE4, 0xE1)), null,
            PaperArt.Polygon([new(x + w - f, y), new(x + w - f, y + f), new(x + w, y + f)]));
        if (glyph == null) return;
        var side = 12 * s;
        using (g.PushTransform(Matrix.CreateScale(side / 24, side / 24) * Matrix.CreateTranslation(x + (w - side) / 2, y + h * 0.42)))
            g.DrawGeometry(null, new Pen(new SolidColorBrush(Color.FromRgb(0x9A, 0x9C, 0xA0)), 2.2, lineCap: PenLineCap.Round, lineJoin: PenLineJoin.Round), glyph);
    }
}
