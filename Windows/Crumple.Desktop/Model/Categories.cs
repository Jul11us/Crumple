using Crumple.Core;
using static Crumple.Desktop.Model.Strings;

namespace Crumple.Desktop.Model;

internal enum CategoryKind { Temporary, BrowserCache, Logs, DevCaches, AITools, Installers, OldDownloads, LargeFiles, Duplicates }
internal enum RowStatus { Ready, Tossed, Cleaned, Failed }
internal enum CheckState { Off, On, Mixed }
internal enum FileTag { Video, Archive, DiskImage, Document, Audio, Other }

internal static class CategoryInfo
{
    /// The groups that make up a smart clean on Windows, in the order the scan reveals them.
    public static readonly CategoryKind[] Junk =
        [CategoryKind.Temporary, CategoryKind.BrowserCache, CategoryKind.Logs, CategoryKind.DevCaches, CategoryKind.AITools, CategoryKind.Installers, CategoryKind.OldDownloads];

    public static string Title(this CategoryKind kind) => kind switch
    {
        CategoryKind.Temporary => L("临时文件"),
        CategoryKind.BrowserCache => L("浏览器缓存"),
        CategoryKind.Logs => L("日志文件"),
        CategoryKind.DevCaches => L("开发工具缓存"),
        CategoryKind.AITools => L("AI 工具残留"),
        CategoryKind.Installers => L("安装包"),
        CategoryKind.OldDownloads => L("旧下载文件"),
        CategoryKind.LargeFiles => L("大文件"),
        _ => L("重复文件"),
    };

    public static string Summary(this CategoryKind kind) => kind switch
    {
        CategoryKind.Temporary => L("应用和安装程序留下的临时文件，至少一周没动过。正在使用的会自动跳过。"),
        CategoryKind.BrowserCache => L("浏览器为了加快打开网页保存的数据，删除后会自动重新生成。浏览器开着时投不进纸篓，先关掉它再清理。"),
        CategoryKind.Logs => L("应用和系统组件写下的运行日志与崩溃报告。"),
        CategoryKind.DevCaches => L("npm、Gradle、Cargo、pip 等包管理器下载的缓存，需要时会重新下载。"),
        CategoryKind.AITools => L("Claude、Codex、Cursor 等 AI 工具留下的缓存、运行时和模型文件。缓存默认勾选；体积大的下载只列出来，由你决定。对话记录一律不碰。"),
        CategoryKind.Installers => L("下载文件夹里的 .exe / .msi 安装包，装完通常就不需要了。默认不勾选。"),
        CategoryKind.OldDownloads => L("下载文件夹中很久没碰过的文件。这是你自己的文件，请确认后再勾选。"),
        CategoryKind.LargeFiles => L("个人文件夹里体积很大的文件。"),
        _ => L("内容一模一样的文件，每组只留一份。"),
    };

    public static string Icon(this CategoryKind kind) => kind switch
    {
        CategoryKind.Temporary => Ui.IconData.Archive,
        CategoryKind.BrowserCache => Ui.IconData.AppWindow,
        CategoryKind.Logs => Ui.IconData.FileText,
        CategoryKind.DevCaches => Ui.IconData.Package,
        CategoryKind.AITools => Ui.IconData.Sparkles,
        CategoryKind.Installers => Ui.IconData.Disc3,
        CategoryKind.OldDownloads => Ui.IconData.History,
        CategoryKind.LargeFiles => Ui.IconData.File,
        _ => Ui.IconData.Files,
    };

    /// Shades of the same ink, from dark to pale, so the share chart reads like a printed graph.
    public static Avalonia.Media.IBrush ChartBrush(this CategoryKind kind) => kind switch
    {
        CategoryKind.Temporary => Ui.Ink.Accent,
        CategoryKind.BrowserCache => Ui.Ink.Fill(0.72),
        CategoryKind.Logs => Ui.Ink.Fill(0.56),
        CategoryKind.DevCaches => Ui.Ink.Fill(0.42),
        CategoryKind.AITools => Ui.Ink.Fill(0.30),
        CategoryKind.Installers => Ui.Ink.Fill(0.20),
        CategoryKind.OldDownloads => Ui.Ink.Fill(0.12),
        _ => Ui.Ink.Tertiary,
    };

    public static CategoryKind From(FileCategory category) => category switch
    {
        FileCategory.Temporary => CategoryKind.Temporary,
        FileCategory.BrowserCache => CategoryKind.BrowserCache,
        FileCategory.Logs => CategoryKind.Logs,
        FileCategory.DeveloperCache => CategoryKind.DevCaches,
        FileCategory.AITools => CategoryKind.AITools,
        FileCategory.Installers => CategoryKind.Installers,
        FileCategory.OldDownloads => CategoryKind.OldDownloads,
        FileCategory.Large => CategoryKind.LargeFiles,
        _ => CategoryKind.Duplicates,
    };

    public static string Title(this FileTag tag) => tag switch
    {
        FileTag.Video => L("视频"),
        FileTag.Archive => L("压缩包"),
        FileTag.DiskImage => L("磁盘镜像"),
        FileTag.Document => L("文档"),
        FileTag.Audio => L("音频"),
        _ => L("其他"),
    };

    public static string Icon(this FileTag tag) => tag switch
    {
        FileTag.Video => Ui.IconData.Film,
        FileTag.Archive => Ui.IconData.Archive,
        FileTag.DiskImage => Ui.IconData.Disc3,
        FileTag.Document => Ui.IconData.FileText,
        FileTag.Audio => Ui.IconData.Music,
        _ => Ui.IconData.File,
    };

    public static FileTag TagOf(string path) => Path.GetExtension(path).ToLowerInvariant() switch
    {
        ".mov" or ".mp4" or ".mkv" or ".avi" or ".wmv" or ".m4v" or ".webm" => FileTag.Video,
        ".zip" or ".rar" or ".7z" or ".tar" or ".gz" or ".tgz" or ".bz2" or ".xz" => FileTag.Archive,
        ".iso" or ".img" or ".vhd" or ".vhdx" or ".vmdk" or ".dmg" or ".exe" or ".msi" => FileTag.DiskImage,
        ".pdf" or ".doc" or ".docx" or ".ppt" or ".pptx" or ".xls" or ".xlsx" or ".psd" or ".ai" or ".key" or ".txt" => FileTag.Document,
        ".mp3" or ".wav" or ".flac" or ".m4a" or ".aac" or ".ogg" => FileTag.Audio,
        _ => FileTag.Other,
    };
}

/// One row of a list. A smart clean row can stand for a whole cache folder; the other lists have one file per row.
internal sealed class CleanRow
{
    public required string Id { get; init; }
    public required string Name { get; init; }
    public required string Detail { get; init; }
    /// What the row points at, for Explorer and Quick Look.
    public required string Path { get; init; }
    public required List<CleanItem> Files { get; init; }
    public long Size => Files.Where(x => !x.Removed).Sum(x => x.Size);
    public bool Selected { get; set; }
    public RowStatus Status { get; set; }
    public string? Badge { get; init; }
    public string? Keeper { get; init; }
    public FileTag Tag { get; init; } = FileTag.Other;
    public DateTime LastUsed { get; init; }
    public string[] Owners => Files.SelectMany(x => x.OwnerProcesses).Distinct().ToArray();
}

internal sealed class Category(CategoryKind kind)
{
    public CategoryKind Kind { get; } = kind;
    public List<CleanRow> Rows { get; set; } = [];
    public bool Scanning { get; set; }

    public IEnumerable<CleanRow> Live => Rows.Where(x => x.Status != RowStatus.Cleaned);
    public int LiveCount => Live.Count();
    public IEnumerable<CleanRow> SelectedRows => Live.Where(x => x.Selected);
    public long TotalBytes => Live.Sum(x => x.Size);
    public long SelectedBytes => SelectedRows.Sum(x => x.Size);

    public CheckState Selection
    {
        get
        {
            var live = Live.ToList();
            var selected = live.Count(x => x.Selected);
            return selected == 0 ? CheckState.Off : selected == live.Count ? CheckState.On : CheckState.Mixed;
        }
    }

    public void ToggleAll()
    {
        var value = Selection != CheckState.On;
        foreach (var row in Live) row.Selected = value;
    }

    public void SelectAll() { foreach (var row in Live) row.Selected = true; }

    public void Toggle(string id)
    {
        if (Rows.FirstOrDefault(x => x.Id == id) is { } row) row.Selected = !row.Selected;
    }
}
