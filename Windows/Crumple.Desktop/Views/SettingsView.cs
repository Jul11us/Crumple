using Avalonia;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;
using Crumple.Desktop.Art;
using Crumple.Desktop.Model;
using Crumple.Desktop.Ui;
using static Crumple.Desktop.Model.Strings;
using static Crumple.Desktop.Ui.Ui;

namespace Crumple.Desktop.Views;

/// Settings in grouped cards, like the Mac version's settings window. Changes apply right away.
internal sealed class SettingsView : Border
{
    private readonly AppModel model;

    public SettingsView(AppModel model)
    {
        this.model = model;
        Background = Ink.Base;
        Rebuild();
        model.Changed += Rebuild;
        DetachedFromVisualTree += (_, _) => model.Changed -= Rebuild;
    }

    private void Rebuild()
    {
        var prefs = model.Preferences;
        var content = V(20,
            Section(L("外观"), null,
                Line(L("外观"), Choice([L("跟随系统"), L("雾灰"), L("牛皮纸"), L("深色")], ["system", "light", "kraft", "dark"], prefs.Appearance, v =>
                {
                    prefs.Appearance = v;
                    Ink.Palette = AppModel.PaletteFor(v);
                })),
                Line(L("语言"), Choice([L("跟随系统"), "简体中文", "English"], ["system", "zh-Hans", "en"], prefs.Language, v =>
                {
                    prefs.Language = v;
                    Strings.Load(v);
                })),
                Line(L("声音"), Switch(prefs.PlaysSounds, v => { prefs.PlaysSounds = v; Sounds.Enabled = v; }))),
            Section(L("扫描"), null,
                Line(L("大文件下限"), Choice(["50 MB", "100 MB", "500 MB", "1 GB"], ["50", "100", "500", "1000"], prefs.LargeFileMegabytes.ToString(), v => prefs.LargeFileMegabytes = int.Parse(v))),
                Line(L("“旧下载”是指多久没动过"), Choice([L("%lld 天", 30), L("%lld 天", 90), L("%lld 天", 180), L("%lld 天", 365)], ["30", "90", "180", "365"],
                    prefs.OldDownloadDays.ToString(), v => prefs.OldDownloadDays = int.Parse(v)))),
            Section(L("忽略列表"), L("这里的文件和文件夹（包括里面的一切）不会出现在任何扫描结果里。"), IgnoreRows()),
            Section(L("记录"), L("只会删除记录，不影响任何文件。"),
                Line(L("清理记录"), new UiButton(L("清空记录"), model.ClearHistory, ButtonKind.Secondary).Disabled(model.History.Count == 0))),
            Section(L("关于"), null,
                Line("Crumple", Text(L("版本 %@", typeof(SettingsView).Assembly.GetName().Version?.ToString(3) ?? "1.1.1"), 13, brush: Ink.Secondary))));
        content.Margin = new Thickness(28, 24);
        Child = Common.Scroll("settings", content);
    }

    private Control[] IgnoreRows()
    {
        var ignored = model.Preferences.IgnoredPaths;
        if (ignored.Count == 0) return [Text(L("还没有忽略任何东西。在列表里右键一项，选“忽略”。"), 13, brush: Ink.Secondary, wrap: true)];
        return ignored.Select(path => (Control)Line(model.Places.Display(path), new UiButton(L("恢复"), () =>
        {
            ignored.Remove(path);
            Save();
        }, ButtonKind.Ghost))).ToArray();
    }

    private void Save() { model.SaveSettings(); model.Notify(); }

    private static Control Section(string title, string? footer, params Control[] lines)
    {
        var rows = V(0);
        for (var i = 0; i < lines.Length; i++)
        {
            if (i > 0) rows.Children.Add(new Hairline());
            rows.Children.Add(lines[i]);
        }
        return V(8, Text(title, 13, FontWeight.SemiBold, Ink.Secondary).Margin(4, 0, 0, 0), Card(rows, radius: 12, padding: 4),
            footer == null ? null : Text(footer, 12, brush: Ink.Tertiary, wrap: true).Margin(4, 0, 0, 0));
    }

    private static Control Line(string label, Control control)
    {
        control.VerticalAlignment = VerticalAlignment.Center;
        return Row(Text(label, 13).With(t => { t.VerticalAlignment = VerticalAlignment.Center; t.MaxWidth = 300; }), control).With(r => { r.MinHeight = 44; r.Margin = new Thickness(12, 0); });
    }

    private Control Choice(string[] titles, string[] values, string current, Action<string> set)
    {
        var box = new ComboBox
        {
            ItemsSource = titles, SelectedIndex = Math.Max(0, Array.IndexOf(values, current)), MinWidth = 140, FontSize = 13,
            Background = Ink.Card, BorderBrush = Ink.Stroke, CornerRadius = new CornerRadius(8),
        };
        box.SelectionChanged += (_, _) =>
        {
            if (box.SelectedIndex < 0 || values[box.SelectedIndex] == current) return;
            set(values[box.SelectedIndex]);
            Save();
        };
        return box;
    }

    private Control Switch(bool value, Action<bool> set)
    {
        var toggle = new ToggleSwitch { IsChecked = value, OnContent = "", OffContent = "" };
        toggle.IsCheckedChanged += (_, _) => { set(toggle.IsChecked == true); Save(); };
        return toggle;
    }
}
