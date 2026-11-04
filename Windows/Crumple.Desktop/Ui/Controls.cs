using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Shapes;
using Avalonia.Input;
using Avalonia.Layout;
using Avalonia.Media;
using Crumple.Desktop.Model;

namespace Crumple.Desktop.Ui;

/// Small builders that mirror the Mac version's SwiftUI pieces, so pages read much like their Swift originals.
internal static class Ui
{
    public static TextBlock Text(string text, double size = 13, FontWeight weight = FontWeight.Normal,
        IBrush? brush = null, FontFamily? font = null, bool wrap = false) => new()
    {
        Text = text,
        FontSize = size,
        FontWeight = weight,
        Foreground = brush ?? Ink.Primary,
        FontFamily = font ?? Ink.Sans,
        TextWrapping = wrap ? TextWrapping.Wrap : TextWrapping.NoWrap,
        TextTrimming = wrap ? TextTrimming.None : TextTrimming.CharacterEllipsis,
    };

    public static TextBlock Title(string text, double size) =>
        Text(text, size, FontWeight.SemiBold, font: Ink.Serif);

    public static TextBlock Figures(string text, double size, FontWeight weight = FontWeight.Medium) =>
        Text(text, size, weight, font: Ink.Mono);

    public static StackPanel V(double spacing, params Control?[] children) => Stack(Orientation.Vertical, spacing, children);
    public static StackPanel H(double spacing, params Control?[] children) => Stack(Orientation.Horizontal, spacing, children);

    private static StackPanel Stack(Orientation orientation, double spacing, Control?[] children)
    {
        var panel = new StackPanel { Orientation = orientation, Spacing = spacing };
        foreach (var child in children) if (child != null) panel.Children.Add(child);
        return panel;
    }

    /// A row whose middle stretches, like an HStack with a Spacer.
    public static Grid Row(Control? leading, Control? trailing, double spacing = 8, Control? middle = null)
    {
        var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("Auto,*,Auto") };
        if (leading != null) grid.Children.Add(leading);
        if (middle != null) { Grid.SetColumn(middle, 1); middle.Margin = new Thickness(spacing, 0); grid.Children.Add(middle); }
        if (trailing != null) { Grid.SetColumn(trailing, 2); grid.Children.Add(trailing); }
        return grid;
    }

    /// The paper surface most content sits on.
    public static Border Card(Control child, double radius = 16, double padding = 20, IBrush? fill = null) => new()
    {
        Child = child,
        Padding = new Thickness(padding),
        CornerRadius = new CornerRadius(radius),
        Background = fill ?? Ink.Card,
        BorderBrush = Ink.Stroke,
        BorderThickness = new Thickness(1),
    };

    public static Control Gap(double height = 0, double width = 0) => new Control { Height = height, Width = width };

    public static T With<T>(this T control, Action<T> setup) where T : Control { setup(control); return control; }
    public static T Margin<T>(this T control, double l, double t, double r, double b) where T : Control
    { control.Margin = new Thickness(l, t, r, b); return control; }
    public static T Tip<T>(this T control, string tip) where T : Control { ToolTip.SetTip(control, tip); return control; }
}

/// A stroked line icon.
internal sealed class Icon : Control
{
    private readonly Geometry geometry;
    private readonly IBrush brush;
    private readonly double weight;

    public Icon(string data, double size = 18, IBrush? brush = null, double weight = 1.5)
    {
        geometry = Geometry.Parse(data);
        this.brush = brush ?? Ink.Secondary;
        this.weight = weight;
        Width = Height = size;
        IsHitTestVisible = false;
    }

    public override void Render(DrawingContext context)
    {
        var scale = Bounds.Width / 24;
        using (context.PushTransform(Matrix.CreateScale(scale, scale)))
            context.DrawGeometry(null, new Pen(brush, weight / scale * 1.2, lineCap: PenLineCap.Round, lineJoin: PenLineJoin.Round), geometry);
    }
}

/// A clickable surface with the Mac version's press feedback (a 2% shrink) and keyboard activation.
internal class Pressable : Border
{
    private readonly Action action;
    private bool pressed;
    protected bool Hovering { get; private set; }
    public bool Enabled { get; set; } = true;

    public Pressable(Action action)
    {
        this.action = action;
        Cursor = new Cursor(StandardCursorType.Hand);
        Focusable = true;
        RenderTransformOrigin = RelativePoint.Center;
        Background ??= Brushes.Transparent;
    }

    protected virtual void Restyle() { }

    protected override void OnPointerEntered(PointerEventArgs e) { Hovering = true; Restyle(); base.OnPointerEntered(e); }
    protected override void OnPointerExited(PointerEventArgs e) { Hovering = false; SetPressed(false); Restyle(); base.OnPointerExited(e); }

    protected override void OnPointerPressed(PointerPressedEventArgs e)
    {
        if (Enabled && e.GetCurrentPoint(this).Properties.IsLeftButtonPressed) { SetPressed(true); e.Handled = true; }
        base.OnPointerPressed(e);
    }

    protected override void OnPointerReleased(PointerReleasedEventArgs e)
    {
        var wasPressed = pressed;
        SetPressed(false);
        if (wasPressed && Enabled && new Rect(Bounds.Size).Contains(e.GetPosition(this))) { e.Handled = true; action(); }
        base.OnPointerReleased(e);
    }

    protected override void OnKeyDown(KeyEventArgs e)
    {
        if (Enabled && e.Key is Key.Enter or Key.Space) { e.Handled = true; action(); }
        base.OnKeyDown(e);
    }

    private void SetPressed(bool value)
    {
        pressed = value;
        RenderTransform = value ? new ScaleTransform(0.98, 0.98) : null;
        Restyle();
    }

    protected bool IsPressed => pressed;
}

internal enum ButtonKind { Primary, Secondary, Ghost }

/// The three button styles of the Mac version: ink-filled primary, card secondary, plain ghost.
internal sealed class UiButton : Pressable
{
    private readonly ButtonKind kind;
    private readonly string title;
    private readonly string? icon;
    private readonly bool large;

    public UiButton(string title, Action action, ButtonKind kind = ButtonKind.Primary, bool large = false, string? icon = null)
        : base(action)
    {
        this.kind = kind;
        this.title = title;
        this.icon = icon;
        this.large = large;
        if (kind != ButtonKind.Ghost)
        {
            Height = large ? 44 : 36;
            Padding = new Thickness(large ? 24 : 16, 0);
            CornerRadius = new CornerRadius(8);
            BorderThickness = new Thickness(kind == ButtonKind.Secondary ? 1 : 0);
        }
        HorizontalAlignment = HorizontalAlignment.Left;
        Restyle();
    }

    protected override void Restyle()
    {
        Opacity = Enabled ? (IsPressed && kind == ButtonKind.Primary ? 0.85 : 1) : 0.45;
        Cursor = Enabled ? new Cursor(StandardCursorType.Hand) : Cursor.Default;
        IBrush ink;
        switch (kind)
        {
            case ButtonKind.Primary:
                // In dark mode the button is light ink on the dark page, like the Mac version.
                Background = Ink.Palette.IsDark ? Ink.Primary : Ink.Accent;
                ink = Ink.Palette.IsDark ? Ink.Base : Brushes.White;
                break;
            case ButtonKind.Secondary:
                Background = IsPressed || Hovering ? Ink.Raised : Ink.Card;
                BorderBrush = Ink.Stroke;
                ink = Ink.Primary;
                break;
            default:
                Background = Brushes.Transparent;
                ink = IsPressed ? Ink.Tertiary : Hovering ? Ink.Primary : Ink.Secondary;
                break;
        }
        var label = Ui.Text(title, large ? 14 : 13, FontWeight.Medium, ink);
        label.VerticalAlignment = VerticalAlignment.Center;
        Child = icon == null ? label
            : Ui.H(6, new Icon(icon, 14, ink, 1.6) { VerticalAlignment = VerticalAlignment.Center }, label);
    }

    public UiButton Disabled(bool disabled) { Enabled = !disabled; Restyle(); return this; }
}

internal sealed class CheckMark : Pressable
{
    public CheckMark(CheckState state, Action toggle) : base(toggle)
    {
        Width = Height = 17;
        CornerRadius = new CornerRadius(5);
        BorderThickness = new Thickness(1.3);
        Background = state == CheckState.Off ? Ink.Fill(0.04) : Ink.Accent;
        BorderBrush = state == CheckState.Off ? Ink.Fill(0.3) : Ink.Accent;
        if (state != CheckState.Off)
            Child = new Icon(state == CheckState.On ? IconData.Check : IconData.Minus, 12, Ink.OnAccent, 2.6)
                { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
    }
}

/// "Title ........ value", like a line on a receipt.
internal sealed class LeaderRow : Grid
{
    public LeaderRow(string title, string value, IBrush? valueBrush = null, double size = 13, FontWeight weight = FontWeight.Medium)
    {
        ColumnDefinitions = new ColumnDefinitions("Auto,*,Auto");
        var left = Ui.Text(title, size, brush: Ink.Secondary);
        var right = Ui.Figures(value, size, weight);
        if (valueBrush != null) right.Foreground = valueBrush;
        var dots = new DottedLeader { VerticalAlignment = VerticalAlignment.Bottom, Margin = new Thickness(6, 0, 6, 4) };
        Children.Add(left);
        SetColumn(dots, 1); Children.Add(dots);
        SetColumn(right, 2); Children.Add(right);
    }
}

internal sealed class DottedLeader : Control
{
    public DottedLeader() { Height = 4; }
    public override void Render(DrawingContext context)
    {
        var pen = new Pen(Ink.B(Ink.Palette.Tertiary, 0.7), 1, new DashStyle([1, 3], 0));
        context.DrawLine(pen, new Point(0, Bounds.Height - 1), new Point(Bounds.Width, Bounds.Height - 1));
    }
}

/// A thin capsule bar.
internal sealed class Bar : Control
{
    private readonly double value;
    private readonly IBrush fill;
    public Bar(double value, IBrush? fill = null, double height = 6) { this.value = Math.Clamp(value, 0, 1); this.fill = fill ?? Ink.Accent; Height = height; }
    public override void Render(DrawingContext context)
    {
        var r = Bounds.Height / 2;
        context.DrawRectangle(Ink.Fill(0.08), null, new Rect(Bounds.Size), r, r);
        if (value > 0) context.DrawRectangle(fill, null, new Rect(0, 0, Math.Max(Bounds.Height, Bounds.Width * value), Bounds.Height), r, r);
    }
}

/// A hairline divider.
internal sealed class Hairline : Border
{
    public Hairline(bool vertical = false)
    {
        Background = Ink.Stroke;
        if (vertical) Width = 1; else Height = 1;
    }
}

/// Watches the pointer so a view can show a hover state.
internal sealed class HoverSurface : Border
{
    private readonly Func<bool, IBrush> fill;
    public HoverSurface(Control child, Func<bool, IBrush> fill, double radius)
    {
        this.fill = fill;
        Child = child;
        CornerRadius = new CornerRadius(radius);
        Background = fill(false);
        PointerEntered += (_, _) => Background = this.fill(true);
        PointerExited += (_, _) => Background = this.fill(false);
    }
}

internal static class Shapes
{
    public static Ellipse Dot(double size, IBrush brush) => new() { Width = size, Height = size, Fill = brush };
}
