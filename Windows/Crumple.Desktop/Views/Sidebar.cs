using Avalonia;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Media.Imaging;
using Avalonia.Platform;
using Crumple.Desktop.Model;
using Crumple.Desktop.Ui;
using static Crumple.Desktop.Model.Strings;

namespace Crumple.Desktop.Views;

internal sealed class Sidebar : Border
{
    private readonly AppModel model;

    public Sidebar(AppModel model)
    {
        this.model = model;
        Width = Ink.SidebarWidth;
        Background = Ink.Sidebar;
        Rebuild();
        model.Changed += Rebuild;
        // Short windows get a tighter sidebar, so the disk card never covers the last page.
        SizeChanged += (_, _) => { if (Compact != builtCompact) Rebuild(); };
    }

    private bool builtCompact;

    private bool Compact => Bounds.Height is > 0 and < 760;

    private void Rebuild()
    {
        builtCompact = Compact;
        var root = new DockPanel();

        var brand = Ui.Ui.H(12,
            new Image { Source = new Bitmap(AssetLoader.Open(new Uri("avares://Crumple/Assets/icon-256.png"))), Width = 36, Height = 36 },
            Ui.Ui.V(4,
                Ui.Ui.Text("Crumple", 18, FontWeight.SemiBold),
                Ui.Ui.Text(model.Demo ? L("演示模式 · 使用假文件") : L("把垃圾揉成纸团"), 11, brush: Ink.Secondary)))
            .Margin(20, Compact ? 36 : 48, 20, Compact ? 20 : 28);
        DockPanel.SetDock(brand, Dock.Top);
        root.Children.Add(brand);

        // Bottom: the disk, a divider, settings and emptying the bin.
        var bottom = Ui.Ui.V(0);
        if (model.Disk is { } disk)
        {
            bottom.Children.Add(Ui.Ui.V(8,
                Ui.Ui.Row(Ui.Ui.Text(disk.Name, 12, FontWeight.Medium),
                    Ui.Ui.Text($"{(int)(disk.UsedFraction * 100)}%", 11, brush: Ink.Secondary)),
                new Bar(disk.UsedFraction, disk.UsedFraction > 0.9 ? Ink.Danger : Ink.Tertiary),
                Ui.Ui.Text(L("可用 %@ · 共 %@", Format.Bytes(disk.Available), Format.Bytes(disk.Total)), 11, brush: Ink.Secondary))
                .Margin(24, 0, 24, 20));
        }
        bottom.Children.Add(new Hairline().Margin(20, 0, 20, 0));
        var trashTitle = model.TrashSize switch
        {
            0 => L("废纸篓是空的"),
            { } size => L("清倒 %@", Format.Bytes(size)),
            null => L("清倒废纸篓"),
        };
        bottom.Children.Add(Ui.Ui.V(0,
            FooterLink(IconData.Settings, L("设置"), model.OpenSettings),
            FooterLink(IconData.Trash, trashTitle, model.RequestEmptyTrash, disabled: model.IsCleaning || model.TrashSize == 0))
            .Margin(24, 12, 24, 12));
        DockPanel.SetDock(bottom, Dock.Bottom);
        root.Children.Add(bottom);

        var nav = new StackPanel { Spacing = 4, Margin = new Thickness(12, 0) };
        foreach (var page in Enum.GetValues<Page>())
        {
            if (page.Section() is { } section)
                nav.Children.Add(Ui.Ui.Text(section, 11, FontWeight.Medium, Ink.Tertiary).Margin(12, Compact ? 12 : 20, 0, 4));
            nav.Children.Add(NavItem(page));
        }
        root.Children.Add(nav);
        Child = root;
    }

    private Control FooterLink(string icon, string title, Action action, bool disabled = false)
    {
        var row = new GhostRow(icon, title, action) { Height = 32, Enabled = !disabled, Opacity = disabled ? 0.45 : 1 };
        return row;
    }

    private Control NavItem(Page page)
    {
        var selected = model.Page == page;
        var badge = Badge(page);
        var label = Ui.Ui.Row(
            Ui.Ui.H(12,
                new Icon(page.Icon(), 18, selected ? Ink.Accent : Ink.Secondary) { VerticalAlignment = VerticalAlignment.Center },
                Ui.Ui.Text(page.Title(), 13, selected ? FontWeight.Medium : FontWeight.Normal, selected ? Ink.Primary : Ink.Secondary)
                    .With(t => t.VerticalAlignment = VerticalAlignment.Center)),
            badge == null ? null : Ui.Ui.Text(badge, 11, brush: Ink.Tertiary, font: Ink.Mono).With(t => t.VerticalAlignment = VerticalAlignment.Center));
        var item = new NavButton(label, selected, () => model.Go(page)) { Enabled = !model.IsCleaning || selected };
        if (!selected) return item;
        // The selected page gets a short ink mark at its left edge.
        var mark = new Border { Width = 2, Height = 16, CornerRadius = new CornerRadius(1), Background = Ink.Accent,
            HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Center };
        return new Panel { Children = { item, mark } };
    }

    private string? Badge(Page page) => page switch
    {
        Page.SmartClean => model.LastSmartScan != null ? Format.Bytes(model.JunkFound) : null,
        Page.LargeFiles => model.FilesPhase == ListPhase.Results ? model.LargeFiles.LiveCount.ToString() : null,
        Page.Duplicates => model.DupPhase == ListPhase.Results ? model.Duplicates.LiveCount.ToString() : null,
        Page.Uninstaller => model.AppsPhase == ListPhase.Results ? model.Apps.Count.ToString() : null,
        _ => null,
    };
}

/// A sidebar row: card-coloured when selected, a faint wash on hover.
internal sealed class NavButton : Pressable
{
    private readonly bool selected;
    public NavButton(Control label, bool selected, Action action) : base(action)
    {
        this.selected = selected;
        Child = label;
        Height = 36;
        Padding = new Thickness(12, 0);
        CornerRadius = new CornerRadius(8);
        BorderThickness = new Thickness(1);
        Restyle();
    }

    protected override void Restyle()
    {
        Background = selected ? Ink.Card : Hovering ? Ink.Fill(0.04) : Brushes.Transparent;
        BorderBrush = selected ? Ink.Stroke : Brushes.Transparent;
    }
}

/// Icon and text in the secondary ink, like the Mac version's ghost buttons.
internal sealed class GhostRow : Pressable
{
    public GhostRow(string icon, string title, Action action) : base(action)
    {
        Child = Ui.Ui.H(12,
            new Icon(icon, 16, Ink.Secondary) { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(2, 0) },
            Ui.Ui.Text(title, 13, FontWeight.Medium, Ink.Secondary).With(t => t.VerticalAlignment = VerticalAlignment.Center));
    }
}
