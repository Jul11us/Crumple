using Avalonia.Threading;
using Crumple.Desktop.Platform;
using static Crumple.Desktop.Model.Strings;

namespace Crumple.Desktop.Model;

/// A question to confirm before doing something that can't be undone easily.
internal sealed record Confirmation(string Title, string Message, string ActionTitle, Action Action, Action? Cancel = null);

internal sealed partial class AppModel
{
    public List<Category> Junk { get; } = CategoryInfo.Junk.Select(x => new Category(x)).ToList();
    public Category LargeFiles { get; } = new(CategoryKind.LargeFiles);
    public Category Duplicates { get; } = new(CategoryKind.Duplicates);
    public List<InstalledApp> Apps { get; private set; } = [];

    public long JunkFound => Junk.Sum(x => x.TotalBytes);

    public Confirmation? Confirmation { get; private set; }
    public string? Toast { get; private set; }
    private int toastToken;

    /// Opens the settings window; set by the main window.
    public Action OpenSettings { get; set; } = () => { };

    public void Confirm(Confirmation confirmation) { Confirmation = confirmation; Notify(); }

    public void AnswerConfirmation(bool accepted)
    {
        var confirmation = Confirmation;
        Confirmation = null;
        Notify();
        if (accepted) confirmation?.Action(); else confirmation?.Cancel?.Invoke();
    }

    public void ShowToast(string text)
    {
        var token = ++toastToken;
        Toast = text;
        Notify();
        DispatcherTimer.RunOnce(() => { if (token == toastToken) { Toast = null; Notify(); } }, TimeSpan.FromSeconds(3));
    }

    public void RequestEmptyTrash()
    {
        if (IsCleaning || TrashSize == 0) return;
        Confirm(new(L("清倒废纸篓？"), L("废纸篓里的所有项目都会被永久删除，无法恢复。"), L("清倒"), EmptyTrash));
    }

    /// Fires when the bin was emptied, so the basket can tip over and pour out its balls.
    public event Action? TrashEmptied;

    private void EmptyTrash()
    {
        Task.Run(() =>
        {
            if (Demo || !OperatingSystem.IsWindows())
            {
                if (Directory.Exists(Places.DemoBin)) Directory.Delete(Places.DemoBin, true);
                return true;
            }
            return Native.EmptyRecycleBin();
        }).ContinueWith(t => Dispatcher.UIThread.Post(() =>
        {
            if (t.IsCompletedSuccessfully && t.Result)
            {
                TrashEmptied?.Invoke();
                RefreshDisk();
            }
            else ShowToast(L("没能清空回收站，稍后再试一次"));
        }));
    }
}
