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

/// Optimise: quit memory-hungry apps, switch off startup apps, open Windows' own maintenance tools.
internal static class OptimizePage
{
    public static Control Build(AppModel model)
    {
        model.Monitor.Start();
        if (model.StartupItems.Count == 0) model.LoadStartupItems();
        var content = V(22,
            V(6, Title(L("优化"), 30), Text(L("关掉占资源的应用，管住开机自己启动的程序，再做几项常用维护。"), 13, brush: Ink.Secondary)),
            HeavyApps(model), Startup(model), Maintenance(model));
        content.Margin = new Thickness(36, 48, BasketGeometry.ReservedTrailing, 32);
        return Common.Scroll("optimize", content);
    }

    private static Control Section(string title, string detail) => H(10, Text(title, 16, FontWeight.SemiBold),
        Text(detail, 12, brush: Ink.Tertiary).With(t => { t.VerticalAlignment = VerticalAlignment.Bottom; t.Margin = new Thickness(0, 0, 0, 2); }));

    private static Control HeavyApps(AppModel model)
    {
        var rows = V(2);
        foreach (var app in model.Monitor.Apps.Where(x => x.Pid != Environment.ProcessId).Take(5))
            rows.Children.Add(Row(H(12, new Icon(IconData.AppWindow, 24, Ink.Secondary, 1.4) { VerticalAlignment = VerticalAlignment.Center },
                    V(2, Text(app.Name, 13, FontWeight.Medium), Text(L("内存 %@ · CPU %@%%", Format.Bytes(app.Memory), app.Cpu.ToString("0.0")), 12, brush: Ink.Tertiary))),
                new UiButton(L("结束"), () => model.RequestEndProcess(app.Pid, app.Name), ButtonKind.Secondary)).Margin(12, 8, 12, 8));
        return V(10, Section(L("占用最多的应用"), L("内存 %lld%% 已用 · 不用的就先关掉", (int)(model.Monitor.MemoryLoad * 100))), Card(rows, padding: 6));
    }

    private static Control Startup(AppModel model)
    {
        var rows = V(2);
        if (model.StartupItems.Count == 0) rows.Children.Add(Text(L("没有找到启动项"), 13, brush: Ink.Secondary).Margin(16, 16, 16, 16));
        foreach (var item in model.StartupItems)
        {
            Control trailing = item.IsUserLevel
                ? new ToggleSwitch { IsChecked = item.Enabled, OnContent = "", OffContent = "", VerticalAlignment = VerticalAlignment.Center }
                    .With(t => t.IsCheckedChanged += (_, _) => model.SetStartupItem(item, t.IsChecked == true))
                : Text(L("所有用户 · 只读"), 11, brush: Ink.Tertiary).With(t => t.VerticalAlignment = VerticalAlignment.Center);
            var row = Row(H(12, new Icon(item.IsUserLevel ? IconData.AppWindow : IconData.LockOpen, 22, Ink.Secondary, 1.4) { VerticalAlignment = VerticalAlignment.Center },
                    V(2, Text(item.Name, 13, FontWeight.Medium), Text(item.Command, 11, brush: Ink.Tertiary).With(t => { t.MaxWidth = 560; t.TextTrimming = TextTrimming.PrefixCharacterEllipsis; }))),
                trailing).Margin(12, 8, 12, 8);
            row.Opacity = item.Enabled ? 1 : 0.6;
            rows.Children.Add(row);
        }
        return V(10,
            Row(Section(L("开机启动"), L("登录时自己跑起来的程序")),
                new UiButton(L("启动应用设置"), () => model.RunMaintenance(new("startup", "", "", "", "ms-settings:startupapps")), ButtonKind.Ghost, icon: IconData.ArrowUpRight)),
            Card(rows, padding: 6),
            Text(L("关掉的启动项不会被删除，和任务管理器里的“禁用”一样，随时可以再打开。"), 12, brush: Ink.Tertiary));
    }

    private static Control Maintenance(AppModel model)
    {
        var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("*,16,*") };
        var tasks = AppModel.Maintenance;
        for (var i = 0; i < tasks.Length; i++)
        {
            var task = tasks[i];
            if (i % 2 == 0) grid.RowDefinitions.Add(new RowDefinition(GridLength.Auto));
            var state = model.TaskStates.GetValueOrDefault(task.Id);
            var title = H(6, Text(task.Title, 14, FontWeight.SemiBold));
            if (task.NeedsAdmin) title.Children.Add(new Icon(IconData.LockOpen, 11, Ink.Tertiary, 2) { VerticalAlignment = VerticalAlignment.Center });
            var card = Card(Row(H(12, new Icon(task.Icon, 26, Ink.Secondary, 1.4) { VerticalAlignment = VerticalAlignment.Top },
                    V(4, title, Text(task.Detail, 12, brush: Ink.Secondary, wrap: true).With(t => t.MaxWidth = 260))),
                new UiButton(state == "done" ? L("已打开") : L("打开"), () => model.RunMaintenance(task), ButtonKind.Secondary) { VerticalAlignment = VerticalAlignment.Center }),
                padding: 16);
            card.Margin = new Thickness(0, 0, 0, 16);
            Grid.SetColumn(card, i % 2 * 2);
            Grid.SetRow(card, i / 2);
            grid.Children.Add(card);
        }
        return V(10, Section(L("维护"), L("打开 Windows 自带的工具；带锁的需要管理员同意")), grid);
    }
}

internal static class UninstallerPage
{
    public static Control Build(AppModel model) => model.AppsPhase switch
    {
        ListPhase.Landing => Common.Landing(HeroStyle.Apps, L("应用卸载"),
            L("看看装了哪些应用、各占多少空间，\n用它们自己的卸载程序干干净净地卸掉。"),
            [L("大小"), L("安装日期"), L("发布者")], L("扫描"), model.ScanApps,
            L("只读取 Windows 的应用列表；卸载交给应用自己的卸载程序，和“设置 › 应用”一样")),
        ListPhase.Scanning => Common.ListScanning(model, Model.Page.Uninstaller, L("正在读取应用…"), L("从 Windows 的应用列表里读取")),
        _ => Results(model),
    };

    private static Control Results(AppModel model)
    {
        var apps = model.FilteredApps.ToList();
        var header = Row(V(6, Title(L("应用卸载"), 30), Text(L("%lld 个应用，共 %@", model.Apps.Count, Format.Bytes(model.Apps.Sum(x => x.Bytes))), 13, brush: Ink.Secondary)),
            new UiButton(L("重新扫描"), model.ScanApps, ButtonKind.Ghost, icon: IconData.RefreshCw) { VerticalAlignment = VerticalAlignment.Bottom, Margin = new Thickness(0, 0, 0, 8) });
        var chips = H(8);
        foreach (var (filter, title) in new[] { (AppFilter.All, L("全部")), (AppFilter.Large, L("大于 500 MB")), (AppFilter.PerUser, L("只装给我")) })
        {
            var count = filter switch { AppFilter.Large => model.Apps.Count(x => x.Bytes >= 500_000_000), AppFilter.PerUser => model.Apps.Count(x => x.PerUser), _ => model.Apps.Count };
            chips.Children.Add(Common.FilterChip(title, null, count, model.AppFilter == filter, () => { model.AppFilter = filter; model.Notify(); }));
        }
        var top = V(16, header, chips);
        top.Margin = new Thickness(32, 44, 32, 0);

        var rows = V(2);
        foreach (var app in apps) rows.Children.Add(AppRow(model, app));
        var list = new Border
        {
            CornerRadius = new CornerRadius(18), Background = Ink.Card, BorderBrush = Ink.Stroke, BorderThickness = new Thickness(1), ClipToBounds = true,
            Child = Common.Scroll("apps", rows.Margin(8, 8, 8, 8)),
        };
        var focused = model.Apps.FirstOrDefault(x => AppModel.Key(x) == model.FocusedApp);
        var detail = Detail(model, focused);
        var body = new Grid { ColumnDefinitions = new ColumnDefinitions("*,16,310"), Margin = new Thickness(32, 16, BasketGeometry.ReservedTrailing - 16, BasketGeometry.Clearance) };
        body.Children.Add(list);
        Grid.SetColumn(detail, 2);
        body.Children.Add(detail);
        DockPanel.SetDock(top, Dock.Top);
        return new DockPanel { Children = { top, body } };
    }

    private static Control AppRow(AppModel model, InstalledApp app)
    {
        var key = AppModel.Key(app);
        var focused = model.FocusedApp == key;
        var title = H(6, Text(app.Name, 13, FontWeight.Medium).With(t => t.MaxWidth = 360));
        if (model.Uninstalling.Contains(key)) title.Children.Add(new Pill(L("正在卸载"), Ink.Accent));
        var detail = string.Join(" · ", new[] { app.Version.Length > 0 ? L("版本 %@", app.Version) : null, app.Publisher.Length > 0 ? app.Publisher : null }.OfType<string>());
        var row = Row(H(12, new AppTile(app.Name, 32) { VerticalAlignment = VerticalAlignment.Center },
                V(3, title, Text(detail, 11, brush: Ink.Tertiary))),
            Text(app.Bytes > 0 ? Format.Bytes(app.Bytes) : "--", 13, FontWeight.SemiBold, Ink.B(Ink.Palette.Primary, 0.85)).With(t => t.VerticalAlignment = VerticalAlignment.Center));
        return new HoverRow(row, () => { model.FocusedApp = key; model.Notify(); }, true, focused ? 0.1 : 0)
            { Padding = new Thickness(12, 8), CornerRadius = new CornerRadius(11) };
    }

    private static Control Detail(AppModel model, InstalledApp? app)
    {
        if (app == null) return Card(Text(L("选择一个应用查看详情"), 13, brush: Ink.Secondary).With(t => { t.HorizontalAlignment = HorizontalAlignment.Center; t.VerticalAlignment = VerticalAlignment.Center; }), padding: 16);
        Control Mini(string label, string value) => new Border
        {
            Background = Ink.Fill(0.05), CornerRadius = new CornerRadius(10), Padding = new Thickness(10),
            Child = V(3, Text(label, 11, brush: Ink.Tertiary), Text(value, 15, FontWeight.SemiBold)),
        };
        var stats = new Grid { ColumnDefinitions = new ColumnDefinitions("*,10,*") };
        stats.Children.Add(Mini(L("总大小"), app.Bytes > 0 ? Format.Bytes(app.Bytes) : L("没有记录")));
        var installed = Mini(L("安装于"), app.Installed is { } d ? Format.Ago(d) : L("没有记录"));
        Grid.SetColumn(installed, 2);
        stats.Children.Add(installed);
        var top = V(16,
            H(16, new AppTile(app.Name, 64), V(3, Text(app.Name, 18, FontWeight.SemiBold).With(t => t.MaxWidth = 200),
                Text(app.Version.Length > 0 ? L("版本 %@", app.Version) : L("未知版本"), 12, brush: Ink.Secondary),
                Text(app.Publisher, 11, brush: Ink.Tertiary).With(t => t.MaxWidth = 200)).With(v => v.VerticalAlignment = VerticalAlignment.Center)),
            stats,
            V(4, Text(L("安装位置"), 12, FontWeight.SemiBold, Ink.Secondary),
                Text(app.Location.Length > 0 ? app.Location : L("没有记录"), 12, brush: Ink.Tertiary, wrap: true)),
            Text(L("卸载由应用自己的卸载程序完成，它可能会问你几个问题。"), 12, brush: Ink.Tertiary, wrap: true));
        var button = new UiButton(L("卸载 %@", app.Name), () => model.RequestUninstall(app), icon: IconData.Trash2)
            { HorizontalAlignment = HorizontalAlignment.Stretch }.Disabled(model.IsCleaning);
        if (button.Child is Control c) c.HorizontalAlignment = HorizontalAlignment.Center;
        DockPanel.SetDock(button, Dock.Bottom);
        DockPanel.SetDock(top, Dock.Top);
        return Card(new DockPanel { Children = { button, top, new Control() } }, padding: 16);
    }
}

/// A rounded tile with an app's initial, standing in for its icon.
internal sealed class AppTile : Border
{
    public AppTile(string name, double size)
    {
        Width = Height = size;
        CornerRadius = new CornerRadius(size * 0.22);
        Background = Ink.Raised;
        Child = Text(name.Length > 0 ? char.ToUpperInvariant(name[0]).ToString() : "?", size * 0.42, FontWeight.SemiBold, Ink.Secondary, Ink.Serif)
            .With(t => { t.HorizontalAlignment = HorizontalAlignment.Center; t.VerticalAlignment = VerticalAlignment.Center; });
    }
}
