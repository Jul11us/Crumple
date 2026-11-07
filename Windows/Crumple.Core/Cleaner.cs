namespace Crumple.Core;

public interface ITrashService
{
    TrashRecord Recycle(CleanItem item);
    bool Restore(TrashRecord record);
}

public sealed class Cleaner(PathPolicy policy, ITrashService trash, Func<string[], bool> isRunning)
{
    /// Run on an STA on Windows. Save the receipt after every move, so interrupted batches remain undoable.
    public CleanupReceipt Clean(IEnumerable<CleanItem> items, ScanKind source, Action<CleanupReceipt> save,
        IProgress<ScanProgress>? progress, CancellationToken token)
    {
        var receipt = new CleanupReceipt { Source = source };
        save(receipt); // Prove the history is writable before touching any files.
        int count = 0;
        foreach (var item in items.Where(x => !x.Removed))
        {
            if (token.IsCancellationRequested) break;
            progress?.Report(new(++count, item.Path));
            try
            {
                if (!policy.CanReadFile(item.Path) || !item.Stamp.Matches(item.Path))
                    throw new IOException("The file changed, moved, or is outside the allowed folders. Scan again.");
                if (isRunning(item.OwnerProcesses)) throw new IOException("Close the application that owns this cache first.");
                FileStream? keeperStream = null, targetStream = null;
                try
                {
                    if (item.Keeper != null)
                    {
                        if (!policy.CanReadFile(item.Keeper) || item.KeeperStamp?.Matches(item.Keeper) != true)
                            throw new IOException("The copy to keep changed or is unavailable. Scan again.");
                        keeperStream = Scanner.OpenRead(item.Keeper);
                        targetStream = Scanner.OpenRead(item.Path, allowDelete: true);
                        if (Scanner.FullHash(keeperStream, token) != item.ContentHash || Scanner.FullHash(targetStream, token) != item.ContentHash)
                            throw new IOException("The duplicate contents changed. Scan again.");
                    }
                    // Check again after hashing; never pass a directory to the recycle service.
                    if (!policy.CanReadFile(item.Path) || !item.Stamp.Matches(item.Path)) throw new IOException("The file changed. Scan again.");
                    var record = trash.Recycle(item);
                    receipt.Files.Add(record);
                    item.Removed = true;
                    item.Selected = false;
                }
                finally { keeperStream?.Dispose(); targetStream?.Dispose(); }
            }
            catch (OperationCanceledException) { break; }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException or System.Runtime.InteropServices.COMException)
            {
                receipt.Errors.Add($"{item.Path}\n{e.Message}");
            }
            save(receipt); // A failed journal write stops subsequent cleanup.
        }
        return receipt;
    }

    public bool Restore(TrashRecord record)
    {
        if (record.Restored || !policy.CanRestoreTo(record.Original)) return false;
        if (!trash.Restore(record)) return false;
        record.Restored = true;
        return true;
    }
}
