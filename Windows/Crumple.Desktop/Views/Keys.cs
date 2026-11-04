using Avalonia.Input;
using Crumple.Desktop.Model;

namespace Crumple.Desktop.Views;

/// The Mac version's shortcuts, with Ctrl for ⌘: Ctrl+1–9 pages, Ctrl+R / F5 rescan, Ctrl+A select all,
/// Delete throws the ticked files, Ctrl+Z undoes the last clean, Esc stops a scan, Ctrl+, opens settings.
internal static class Keys
{
    public static void Handle(AppModel model, KeyEventArgs e)
    {
        if (model.Confirmation != null || e.Handled) return;
        var ctrl = e.KeyModifiers.HasFlag(KeyModifiers.Control);
        if (ctrl && e.Key is >= Key.D1 and <= Key.D9)
        {
            model.Go((Page)(e.Key - Key.D1));
            e.Handled = true;
        }
        else if ((ctrl && e.Key == Key.R) || e.Key == Key.F5) { model.Rescan(); e.Handled = true; }
        else if (ctrl && e.Key == Key.A) { model.SelectAllInList(); e.Handled = true; }
        else if (ctrl && e.Key == Key.Z) { model.UndoLastClean(); e.Handled = true; }
        else if (ctrl && e.Key == Key.OemComma) { model.OpenSettings(); e.Handled = true; }
        else if (e.Key == Key.Delete && !ctrl) { model.ThrowSelection(); e.Handled = true; }
        else if (e.Key == Key.Escape && model.IsScanning(model.Page)) { model.CancelScan(model.Page); e.Handled = true; }
    }
}
