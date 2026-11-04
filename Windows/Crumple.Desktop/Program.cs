using Avalonia;
using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Media;
using Avalonia.Threading;
using Crumple.Desktop.Model;
using Crumple.Desktop.Views;
using static Crumple.Desktop.Model.Strings;

namespace Crumple.Desktop;

internal static class Program
{
    [STAThread]
    public static int Main(string[] args)
    {
        string? Arg(string name) => Array.IndexOf(args, name) is var i and >= 0 && i + 1 < args.Length ? args[i + 1] : null;
        var demo = args.Contains("--demo") || Arg("--render") != null
            ? Arg("--demo-home") ?? DefaultDemoHome() : null;

        if (Arg("--render") is { } output)
        {
            AppBuilder.Configure<App>().UseSkia()
                .UseHeadless(new AvaloniaHeadlessPlatformOptions { UseHeadlessDrawing = false })
                .SetupWithoutStarting();
            Render.Interface(output, demo!, args.Contains("--states"));
            return 0;
        }
        App.DemoHome = demo;
        return AppBuilder.Configure<App>().UsePlatformDetect().StartWithClassicDesktopLifetime(args);
    }

    /// The safety rules never follow links, so the demo needs a folder with none above it
    /// (on a Mac /tmp and /var are links).
    private static string DefaultDemoHome() => OperatingSystem.IsWindows()
        ? Path.Combine(Path.GetTempPath(), "Crumple-Demo")
        : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Crumple-Demo");
}

internal sealed class App : Application
{
    public static string? DemoHome;

    public override void Initialize()
    {
        Styles.Add(new Avalonia.Themes.Fluent.FluentTheme());
    }

    public override void OnFrameworkInitializationCompleted()
    {
        if (ApplicationLifetime is Avalonia.Controls.ApplicationLifetimes.IClassicDesktopStyleApplicationLifetime desktop)
        {
            var model = new AppModel(DemoHome);
            Art.Sounds.Enabled = model.Preferences.PlaysSounds;
            var icon = new WindowIcon(Avalonia.Platform.AssetLoader.Open(new Uri("avares://Crumple/Assets/Crumple.ico")));
            var window = new Window
            {
                Title = "Crumple" + (model.Demo ? " · Demo" : ""),
                Width = 1180, Height = 780, MinWidth = 1100, MinHeight = 720,
                Content = new MainView(model),
                WindowStartupLocation = WindowStartupLocation.CenterScreen,
                Icon = icon,
            };
            Window? settings = null;
            model.OpenSettings = () =>
            {
                if (settings != null) { settings.Activate(); return; }
                settings = new Window { Title = L("设置"), Width = 560, Height = 640, Content = new SettingsView(model), Icon = icon,
                    WindowStartupLocation = WindowStartupLocation.CenterOwner };
                settings.Closed += (_, _) => settings = null;
                settings.Show(window);
            };
            // Back from an app's uninstaller, or from Explorer: read things again.
            window.Activated += (_, _) => { model.RefreshAfterUninstall(); model.RefreshDisk(); };
            window.KeyDown += (_, e) => Keys.Handle(model, e);
            desktop.MainWindow = window;
        }
        base.OnFrameworkInitializationCompleted();
    }
}

/// `--render <dir> [--states]`: draws pages offscreen in each theme, named like the Mac version's previews so the two can be compared.
internal static class Render
{
    public static void Interface(string output, string demoHome, bool states)
    {
        Directory.CreateDirectory(output);
        var model = new AppModel(demoHome);
        var variants = new[] { ("mist", Ui.Palette.Mist, 1180.0, 780.0), ("kraft", Ui.Palette.Kraft, 1180.0, 780.0), ("dark-compact", Ui.Palette.Dark, 1100.0, 720.0) };
        var window = new Window();
        void Shoot(string name, Ui.Palette palette, double width, double height)
        {
            Ui.Ink.Palette = palette;
            window.Width = width;
            window.Height = height;
            window.Content = new MainView(model);
            window.Show();
            Pump(0.8);
            window.CaptureRenderedFrame()?.Save(Path.Combine(output, name + ".png"));
        }
        string Name(Page page) => char.ToLowerInvariant(page.ToString()[0]) + page.ToString()[1..];

        foreach (var (name, palette, width, height) in variants)
            foreach (var page in new[] { Page.Overview, Page.Status, Page.SmartClean, Page.Analysis, Page.LargeFiles, Page.Duplicates, Page.Optimize, Page.Uninstaller, Page.History })
            {
                model.Go(page);
                Shoot($"{Name(page)}-{name}", palette, width, height);
            }
        if (states)
        {
            foreach (var (name, palette, width, height) in variants)
            {
                model.StartSmartScan();
                Pump(0.9);
                Shoot($"smartClean-scanning-{name}", palette, width, height);
                Wait(() => model.SmartPhase == SmartPhase.Results);
                Pump(1.4);
                Shoot($"smartClean-results-{name}", palette, width, height);
                model.OpenReview();
                Shoot($"smartClean-review-{name}", palette, width, height);
                model.Go(Page.LargeFiles);
                model.ScanLargeFiles();
                Wait(() => model.FilesPhase == ListPhase.Results);
                Shoot($"largeFiles-results-{name}", palette, width, height);
                model.Go(Page.Duplicates);
                model.ScanDuplicates();
                Wait(() => model.DupPhase == ListPhase.Results);
                Shoot($"duplicates-results-{name}", palette, width, height);
                model.Go(Page.Uninstaller);
                model.ScanApps();
                Wait(() => model.AppsPhase == ListPhase.Results);
                Shoot($"uninstaller-results-{name}", palette, width, height);
                if (name == "mist")
                {
                    ThrowByHand(model, window, output);
                    model.Go(Page.SmartClean);
                    model.RequestSmartClean();
                    Pump(1.5);
                    Shoot("smartClean-cleaning-mist", palette, width, height);
                    Wait(() => model.SmartPhase == SmartPhase.Done);
                    Pump(1.6);
                    Shoot("smartClean-done-mist", palette, width, height);
                    model.FinishSmartClean();
                }
                model.Go(Page.Overview);
            }
        }
        Console.WriteLine("Interface previews: " + output);
    }

    /// Drags the first large file into the basket with the (simulated) mouse, like a person would,
    /// photographs the ball in the air, and checks the file really went to the bin.
    private static void ThrowByHand(AppModel model, Window window, string output)
    {
        model.Go(Page.LargeFiles);
        Pump(0.6);
        var row = model.VisibleRows(model.LargeFiles)[0];
        var start = model.IconFrames[row.Id].Center;
        var basket = new Art.BasketGeometry(Art.BasketGeometry.RectIn(window.ClientSize)).Mouth.Center;
        window.MouseDown(start, Avalonia.Input.MouseButton.Left);
        // Carried to just above the basket, then let go with a small nudge so it drops in.
        var path = new List<Point>();
        for (var i = 1; i <= 12; i++) path.Add(new Point(start.X + (basket.X - 60 - start.X) * i / 12, start.Y + (basket.Y - 220 - start.Y) * i / 12));
        foreach (var p in path) { window.MouseMove(p); Pump(0.03); }
        Pump(0.3);
        window.CaptureRenderedFrame()?.Save(Path.Combine(output, "throw-held-mist.png"));
        // A small nudge towards the basket.
        var flick = Enumerable.Range(1, 4).Select(i => new Point(path[^1].X + 5 * i, path[^1].Y)).ToArray();
        foreach (var p in flick) { window.MouseMove(p); Pump(0.016); }
        window.MouseUp(flick[^1], Avalonia.Input.MouseButton.Left);
        Pump(0.25);
        window.CaptureRenderedFrame()?.Save(Path.Combine(output, "throw-flying-mist.png"));
        Pump(2.5);
        var landed = !File.Exists(row.Path) && Directory.EnumerateFiles(model.Places.DemoBin).Any(x => x.EndsWith(row.Name));
        Console.WriteLine($"Throw by hand: {row.Name} {(landed ? "landed in the bin" : "missed (still in place)")}");
        window.CaptureRenderedFrame()?.Save(Path.Combine(output, "throw-after-mist.png"));
    }

    public static void Pump(double seconds)
    {
        var end = DateTime.UtcNow.AddSeconds(seconds);
        do { Dispatcher.UIThread.RunJobs(); Thread.Sleep(15); } while (DateTime.UtcNow < end);
    }

    private static void Wait(Func<bool> done)
    {
        var end = DateTime.UtcNow.AddSeconds(30);
        while (!done() && DateTime.UtcNow < end) Pump(0.1);
        Pump(0.6);
    }

    public static void Settle() => Pump(0.3);
}
