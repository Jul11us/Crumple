using Avalonia;
using Avalonia.Media;

namespace Crumple.Desktop.Ui;

/// Every colour of one theme, the same values as the Mac version's `Palette`.
internal sealed record Palette(
    uint Base, uint Sidebar, uint Card, uint Raised,
    uint Primary, uint Secondary, uint Tertiary,
    uint Accent, uint OnAccent, uint AccentSurface,
    uint Warning, uint Danger,
    uint BasketRim, uint BasketSlat, uint BasketWall, uint BasketInside,
    bool IsDark = false)
{
    /// Cool grey with a slate-blue button: quiet, a little like stationery from a museum shop.
    public static readonly Palette Mist = new(
        0xF1F1EE, 0xE7E7E3, 0xF8F8F6, 0xDCDCD8,
        0x2B2D30, 0x5F6267, 0x7D8085,
        0x3E5568, 0xF4F4F1, 0xE3E6E9,
        0x94661C, 0xA5403A,
        0x2B2D30, 0x3B3E42, 0x4B4F54, 0x1C1D1F);

    /// Kraft paper with dark brown ink: warmer, more hand-made.
    public static readonly Palette Kraft = new(
        0xE9E3D9, 0xDFD7CA, 0xF0EBE3, 0xD3C9BA,
        0x33291F, 0x66594C, 0x85776A,
        0x33291F, 0xEFE9E0, 0xDDD3C4,
        0x8A5A18, 0x9C3A2B,
        0x3A2F25, 0x4A3D31, 0x5A4B3D, 0x231C15);

    /// Close to the system's own dark mode, with almost no colour of its own.
    public static readonly Palette Dark = new(
        0x1C1C1E, 0x161618, 0x242426, 0x333336,
        0xF2F2F2, 0xAEAEB2, 0x8E8E93,
        0xF2F2F2, 0x1C1C1E, 0x2A2A2D,
        0xE0B060, 0xF08A7E,
        0xD9D9DC, 0xBDBDC1, 0xA3A3A8, 0x0E0E0F, IsDark: true);
}

/// Design tokens. The interface is rebuilt when the theme changes, so these are read when drawn.
internal static class Ink
{
    public static Palette Palette { get; set; } = Palette.Mist;

    public static Color C(uint rgb, double opacity = 1) =>
        Color.FromArgb((byte)Math.Round(opacity * 255), (byte)(rgb >> 16), (byte)(rgb >> 8), (byte)rgb);
    public static IBrush B(uint rgb, double opacity = 1) => new SolidColorBrush(C(rgb, opacity));

    public static IBrush Base => B(Palette.Base);
    public static IBrush Sidebar => B(Palette.Sidebar);
    public static IBrush Card => B(Palette.Card);
    public static IBrush Raised => B(Palette.Raised);
    public static IBrush Primary => B(Palette.Primary);
    public static IBrush Secondary => B(Palette.Secondary);
    public static IBrush Tertiary => B(Palette.Tertiary);
    public static IBrush Accent => B(Palette.Accent);
    public static IBrush OnAccent => B(Palette.OnAccent);
    public static IBrush AccentSurface => B(Palette.AccentSurface);
    public static IBrush Warning => B(Palette.Warning);
    public static IBrush Danger => B(Palette.Danger);
    public static IBrush Stroke => B(Palette.Primary, 0.09);
    public static IBrush Fill(double opacity) => B(Palette.Primary, opacity);

    public const double SidebarWidth = 240;

    // Titles are set in a serif, like a printed page; everything else stays in the system font.
    public static readonly FontFamily Serif = new("avares://Crumple/Assets/Fonts#Noto Serif SC");
    public static readonly FontFamily Sans = new("Segoe UI, Microsoft YaHei UI, PingFang SC, Helvetica Neue");
    /// Sizes and counts read like a receipt.
    public static readonly FontFamily Mono = new("Cascadia Mono, Consolas, SF Mono, Menlo");

    public static Thickness T(double left, double top, double right, double bottom) => new(left, top, right, bottom);
}
