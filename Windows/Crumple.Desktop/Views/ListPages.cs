using Avalonia;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;
using Crumple.Desktop.Model;
using Crumple.Desktop.Ui;
using static Crumple.Desktop.Model.Strings;
using static Crumple.Desktop.Ui.Ui;

namespace Crumple.Desktop.Views;

internal static class LargeFilesPage
{
    public static Control Build(AppModel model)
    {
        var threshold = model.Preferences.LargeFileMegabytes >= 1000 ? "1 GB" : $"{model.Preferences.LargeFileMegabytes} MB";
        return model.FilesPhase switch
        {
            ListPhase.Landing => Common.Landing(HeroStyle.LargeFiles, L("大文件"),
                L("在桌面、文档、下载、视频、音乐和图片里，\n找出超过 %@ 的文件，看看是谁占了地方。", threshold),
                [L("视频"), L("压缩包"), L("磁盘镜像"), L("文档")], L("扫描"), model.ScanLargeFiles,
                L("只会列出来，默认一个都不勾选；系统文件夹和程序文件夹会被跳过")),
            ListPhase.Scanning => Common.ListScanning(model, Model.Page.LargeFiles, L("正在寻找大文件…"),
                L("已检查 %@ 个文件", model.FilesChecked.ToString("N0"))),
            _ => Results(model),
        };
    }

    private static Control Results(AppModel model)
    {
        var files = model.LargeFiles;
        var live = files.Live.ToList();
        var sort = new ComboBox { ItemsSource = new[] { L("按大小"), L("最久没打开") }, SelectedIndex = (int)model.FileSort, MinWidth = 120, VerticalAlignment = VerticalAlignment.Bottom,
            Background = Ink.Card, BorderBrush = Ink.Stroke, BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(8), FontSize = 13, Foreground = Ink.Primary };
        sort.SelectionChanged += (_, _) => { model.FileSort = (FileSort)sort.SelectedIndex; model.Notify(); };
        var header = Row(
            V(6, Title(L("大文件"), 30), Text(live.Count == 0 ? L("没有找到大文件，空间用得很节省") : L("找到 %lld 个大文件，共 %@", live.Count, Format.Bytes(files.TotalBytes)), 13, brush: Ink.Secondary)),
            H(8, sort, new UiButton(L("重新扫描"), model.ScanLargeFiles, ButtonKind.Ghost, icon: IconData.RefreshCw) { VerticalAlignment = VerticalAlignment.Bottom, Margin = new Thickness(0, 0, 0, 8) }));
        var chips = H(8, Common.FilterChip(L("全部"), null, live.Count, model.FileFilter == null, () => { model.FileFilter = null; model.Notify(); }));
        foreach (var tag in Enum.GetValues<FileTag>())
        {
            var count = live.Count(x => x.Tag == tag);
            if (count > 0) chips.Children.Add(Common.FilterChip(tag.Title(), tag.Icon(), count, model.FileFilter == tag, () => { model.FileFilter = tag; model.Notify(); }));
        }
        var top = V(16, header, chips, model.Banner is { Source: Crumple.Core.ScanKind.Large } banner ? Common.SummaryBanner(model, banner) : null);
        top.Margin = new Thickness(32, 44, 32, 0);
        var button = new UiButton(model.IsCleaning ? L("揉纸团中 %lld/%lld", model.CleanDone, model.CleanTotal) : L("清理选中"), model.RequestLargeFileClean,
            large: true, icon: IconData.Trash2).Disabled(model.IsCleaning || !files.SelectedRows.Any());
        var bar = Common.ActionBar(model, model.IsCleaning ? L("待清理") : L("已选择"), files.SelectedBytes,
            L("%lld 个文件 · %@", files.SelectedRows.Count(), L("扔进纸篓")), button);
        DockPanel.SetDock(top, Dock.Top);
        DockPanel.SetDock(bar, Dock.Bottom);
        return new DockPanel { Children = { top, bar, new ItemList(model, files) { Margin = new Thickness(32, 16) } } };
    }
}

internal static class DuplicatesPage
{
    public static Control Build(AppModel model) => model.DupPhase switch
    {
        ListPhase.Landing => Common.Landing(HeroStyle.Duplicates, L("重复文件"),
            L("在桌面、文档、下载、视频、音乐和图片里，\n找出内容一模一样的文件，每组只留一份。"),
            [L("照片"), L("视频"), L("文档"), L("压缩包")], L("扫描"), model.ScanDuplicates,
            L("逐字节比对，名字不同也能认出来；只有内容完全相同才算重复")),
        ListPhase.Scanning => Common.ListScanning(model, Model.Page.Duplicates, L("正在比对文件…"), model.DupProgress),
        _ => Results(model),
    };

    private static Control Results(AppModel model)
    {
        var files = model.Duplicates;
        var live = files.Live.ToList();
        var subtitle = live.Count == 0
            ? model.Banner?.Source == Crumple.Core.ScanKind.Duplicates ? L("副本都扔掉了，每份文件只留下一份") : L("没有找到重复的文件，每份都是独一无二的")
            : L("%lld 组文件有重复，多出来的副本占了 %@", model.DuplicateGroups, Format.Bytes(files.TotalBytes));
        var header = Row(V(6, Title(L("重复文件"), 30), Text(subtitle, 13, brush: Ink.Secondary)),
            new UiButton(L("重新扫描"), model.ScanDuplicates, ButtonKind.Ghost, icon: IconData.RefreshCw) { VerticalAlignment = VerticalAlignment.Bottom, Margin = new Thickness(0, 0, 0, 8) });
        var top = V(16, header,
            live.Count > 0 ? H(8, new Icon(IconData.Files, 14, Ink.Accent) { VerticalAlignment = VerticalAlignment.Center },
                Text(L("每组都会留下一份（见每行的“和…一样”），列出来的是多出来的副本。"), 12, brush: Ink.Secondary)) : null,
            model.Banner is { Source: Crumple.Core.ScanKind.Duplicates } banner ? Common.SummaryBanner(model, banner) : null);
        top.Margin = new Thickness(32, 44, 32, 0);
        var button = new UiButton(model.IsCleaning ? L("揉纸团中 %lld/%lld", model.CleanDone, model.CleanTotal) : L("清理副本"), model.RequestDuplicateClean,
            large: true, icon: IconData.Trash2).Disabled(model.IsCleaning || !files.SelectedRows.Any());
        var bar = Common.ActionBar(model, model.IsCleaning ? L("待清理") : L("已选择"), files.SelectedBytes,
            L("%lld 个副本 · %@", files.SelectedRows.Count(), L("扔进纸篓")), button);
        DockPanel.SetDock(top, Dock.Top);
        DockPanel.SetDock(bar, Dock.Bottom);
        return new DockPanel { Children = { top, bar, new ItemList(model, files) { Margin = new Thickness(32, 16) } } };
    }
}
