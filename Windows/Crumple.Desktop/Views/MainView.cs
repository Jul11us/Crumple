using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Layout;
using Avalonia.Media;
using Crumple.Desktop.Art;
using Crumple.Desktop.Model;
using Crumple.Desktop.Ui;
using static Crumple.Desktop.Model.Strings;
using static Crumple.Desktop.Ui.Ui;

namespace Crumple.Desktop.Views;

/// The window's content: the sidebar, the page, the paper stage over both, and the messages on top.
internal sealed class MainView : Panel
{
    private readonly AppModel model;
    private readonly Border page = new() { ClipToBounds = true };
    private readonly Panel overlays = new();
    public StageView Stage { get; }

    public MainView(AppModel model)
    {
        this.model = model;
        Background = Ink.Base;
        var layout = new DockPanel();
        var sidebar = new Sidebar(model);
        DockPanel.SetDock(sidebar, Dock.Left);
        layout.Children.Add(sidebar);
        var line = new Hairline(vertical: true);
        DockPanel.SetDock(line, Dock.Left);
        layout.Children.Add(line);
        layout.Children.Add(page);
        Children.Add(layout);
        Stage = new StageView(model);
        Children.Add(Stage);
        Children.Add(overlays);
        model.Changed += Refresh;
        Refresh();
    }

    /// Pages are rebuilt from the model whenever it changes.
    private void Refresh()
    {
        // Built-in controls (menus, lists, scroll bars) follow the theme's light or dark.
        if (Application.Current is { } app)
        {
            app.RequestedThemeVariant = Ink.Palette.IsDark ? Avalonia.Styling.ThemeVariant.Dark : Avalonia.Styling.ThemeVariant.Light;
            // Switches, selections and focus rings use the theme's ink, not the Windows accent colour.
            var accent = Ink.C(Ink.Palette.Accent);
            foreach (var key in new[] { "SystemAccentColor", "SystemAccentColorDark1", "SystemAccentColorDark2", "SystemAccentColorLight1", "SystemAccentColorLight2" })
                app.Resources[key] = accent;
        }
        // Never rebuild under a paper in hand: the row being dragged must keep the pointer.
        if (model.Stage.Held != null) return;
        if (model.Page is not (Model.Page.Status or Model.Page.Optimize)) model.Monitor.Stop();
        page.Child = model.Page switch
        {
            Model.Page.Overview => OverviewPage.Build(model),
            Model.Page.Status => StatusPage.Build(model),
            Model.Page.SmartClean => SmartCleanPage.Build(model),
            Model.Page.Analysis => AnalysisPage.Build(model),
            Model.Page.LargeFiles => LargeFilesPage.Build(model),
            Model.Page.Duplicates => DuplicatesPage.Build(model),
            Model.Page.Optimize => OptimizePage.Build(model),
            Model.Page.Uninstaller => UninstallerPage.Build(model),
            _ => HistoryPage.Build(model),
        };
        Stage.InvalidateVisual();
        BuildOverlays();
    }

    private void BuildOverlays()
    {
        overlays.Children.Clear();
        // The basket is the bin: click it to empty it.
        if (model.ShowsBasket && model.TrashSize is > 0 && !model.IsCleaning)
        {
            var target = new Border
            {
                Width = BasketGeometry.Size.Width, Height = BasketGeometry.Size.Height, Background = Brushes.Transparent,
                HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Bottom,
                Margin = new Thickness(0, 0, BasketGeometry.TrailingInset, BasketGeometry.BottomInset),
                Cursor = new Cursor(StandardCursorType.Hand),
            };
            target.PointerReleased += (_, e) => { if (e.InitialPressMouseButton == MouseButton.Left) model.RequestEmptyTrash(); };
            ToolTip.SetTip(target, L("清倒废纸篓 · %@", Format.Bytes(model.TrashSize ?? 0)));
            overlays.Children.Add(target);
        }
        if (model.BasketNote is { } note)
            overlays.Children.Add(new Border
            {
                Child = H(6, new Icon(IconData.Hand, 13, Ink.OnAccent, 1.8) { VerticalAlignment = VerticalAlignment.Center },
                    Text(note, 12, FontWeight.SemiBold, Ink.OnAccent, wrap: true).With(t => t.MaxWidth = 240)),
                Background = Ink.Danger, CornerRadius = new CornerRadius(10), Padding = new Thickness(12, 8),
                HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Bottom,
                Margin = new Thickness(0, 0, 14, BasketGeometry.BottomInset + BasketGeometry.Size.Height + 10),
                IsHitTestVisible = false,
            });
        if (model.Toast is { } toast)
            overlays.Children.Add(new Border
            {
                Child = H(8, new Icon(IconData.CircleCheck, 14, Ink.Accent, 1.8) { VerticalAlignment = VerticalAlignment.Center }, Text(toast, 12, FontWeight.Medium)),
                Background = Ink.Card, BorderBrush = Ink.Stroke, BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(10),
                Padding = new Thickness(16, 9), HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Top,
                Margin = new Thickness(Ink.SidebarWidth, 14, 0, 0), IsHitTestVisible = false,
                BoxShadow = BoxShadows.Parse("0 4 12 0 #10000000"),
            });
        if (model.Confirmation is { } confirmation) overlays.Children.Add(Dialog(confirmation));
    }

    /// A small sheet in the middle of the window, like the Mac version's alerts. Esc cancels, Enter confirms.
    private Control Dialog(Confirmation confirmation)
    {
        var cancel = new UiButton(L("取消"), () => model.AnswerConfirmation(false), ButtonKind.Secondary);
        var accept = new UiButton(confirmation.ActionTitle, () => model.AnswerConfirmation(true));
        var sheet = new Border
        {
            Width = 380, Background = Ink.Card, CornerRadius = new CornerRadius(14), BorderBrush = Ink.Stroke, BorderThickness = new Thickness(1),
            Padding = new Thickness(24, 22), HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center,
            BoxShadow = BoxShadows.Parse("0 12 40 0 #30000000"),
            Child = V(10, Text(confirmation.Title, 16, FontWeight.SemiBold, wrap: true), Text(confirmation.Message, 13, brush: Ink.Secondary, wrap: true).With(t => t.LineHeight = 20),
                H(10, cancel, accept).With(h => { h.HorizontalAlignment = HorizontalAlignment.Right; h.Margin = new Thickness(0, 10, 0, 0); })),
        };
        var scrim = new Border { Background = new SolidColorBrush(Colors.Black, 0.18), Child = sheet, Focusable = true };
        scrim.KeyDown += (_, e) =>
        {
            if (e.Key == Key.Escape) { e.Handled = true; model.AnswerConfirmation(false); }
            if (e.Key == Key.Enter) { e.Handled = true; model.AnswerConfirmation(true); }
        };
        scrim.AttachedToVisualTree += (_, _) => scrim.Focus();
        return scrim;
    }
}
