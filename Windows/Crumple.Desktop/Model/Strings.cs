using System.Globalization;
using System.Text;
using System.Text.Json;
using Avalonia.Platform;

namespace Crumple.Desktop.Model;

/// The interface is written in Chinese; English comes from the same translations as the Mac version
/// (Localization/en.py, built into Assets/en.json). Text that names the macOS Trash is adjusted for Windows.
internal static class Strings
{
    private static Dictionary<string, string> english = [];
    public static bool English { get; private set; }

    public static void Load(string language)
    {
        English = language == "en" || (language == "system" && CultureInfo.CurrentUICulture.TwoLetterISOLanguageName != "zh");
        try
        {
            using var stream = AssetLoader.Open(new Uri("avares://Crumple/Assets/en.json"));
            english = JsonSerializer.Deserialize<Dictionary<string, string>>(stream) ?? [];
        }
        catch (Exception e) when (e is IOException or JsonException or FileNotFoundException) { english = []; }
    }

    /// Looks up `key` and fills in `%@` / `%lld` in order, like the Mac version's String(localized:).
    public static string L(string key, params object[] args)
    {
        var text = English && english.TryGetValue(key, out var value) ? value : key;
        return ForWindows(Fill(text, args));
    }

    private static string Fill(string text, object[] args)
    {
        var result = new StringBuilder();
        var next = 0;
        for (var i = 0; i < text.Length; i++)
        {
            if (text[i] == '{' && text.IndexOf('|', i) is var bar and > 0 && text.IndexOf('}', i) is var end && bar < end)
            {
                // "{%lld item|%lld items}": choose by the next number.
                var count = next < args.Length ? Convert.ToInt64(args[next], CultureInfo.InvariantCulture) : 0;
                var chosen = count == 1 ? text[(i + 1)..bar] : text[(bar + 1)..end];
                var filled = Fill(chosen, args[next..]);
                next++;
                result.Append(filled);
                i = end;
                continue;
            }
            if (text[i] == '%' && i + 1 < text.Length)
            {
                if (text[i + 1] == '%') { result.Append('%'); i++; continue; }
                if (text[i + 1] == '@') { result.Append(Arg(args, next++)); i++; continue; }
                if (string.CompareOrdinal(text, i + 1, "lld", 0, 3) == 0) { result.Append(Arg(args, next++)); i += 3; continue; }
            }
            result.Append(text[i]);
        }
        return result.ToString();
    }

    private static string Arg(object[] args, int index) => index < args.Length
        ? Convert.ToString(args[index], CultureInfo.CurrentCulture) ?? "" : "";

    /// On Windows the system bin is 回收站 / the Recycle Bin, and it is emptied (清空), not tipped out.
    private static string ForWindows(string text) => English
        ? text.Replace("the Trash", "the Recycle Bin").Replace("Trash", "Recycle Bin")
        : text.Replace("清倒废纸篓", "清空回收站").Replace("废纸篓", "回收站").Replace("清倒", "清空");
}

internal static class Format
{
    /// Sizes in the units Explorer uses (1 KB = 1024 bytes), rounded the way the Mac version shows them.
    public static string Bytes(long bytes)
    {
        if (bytes <= 0) return "0 KB";
        string[] units = ["KB", "MB", "GB", "TB"];
        double value = bytes / 1024.0;
        var i = 0;
        while (value >= 1000 && i < units.Length - 1) { value /= 1024; i++; }
        var text = i switch
        {
            0 => Math.Max(1, Math.Round(value)).ToString("0", CultureInfo.CurrentCulture),
            1 => value.ToString(value >= 100 ? "0" : "0.#", CultureInfo.CurrentCulture),
            _ => value.ToString("0.##", CultureInfo.CurrentCulture),
        };
        return $"{text} {units[i]}";
    }

    public static string Ago(DateTimeOffset date)
    {
        var days = (int)(DateTimeOffset.Now - date).TotalDays;
        return days switch
        {
            < 1 => Strings.L("今天"),
            1 => Strings.L("昨天"),
            < 31 => Strings.L("%lld 天前", days),
            < 365 => Strings.L("%lld 个月前", days / 30),
            _ => Strings.L("%lld 年前", days / 365),
        };
    }

    public static string Time(DateTimeOffset date) => date.ToLocalTime().ToString("t", CultureInfo.CurrentCulture);
}
