namespace Crumple.Core;

/// Where AI tools keep past conversations, their checkpoints and the history people come back to.
/// Nothing inside these, and nothing that holds one of them, is ever offered for cleanup.
public static class AIConversations
{
    public static string[] Stores(string home, string roaming) =>
    [
        Path.Combine(home, ".claude", "projects"), Path.Combine(home, ".claude", "history.jsonl"),
        Path.Combine(home, ".claude", "todos"), Path.Combine(home, ".claude", "file-history"), Path.Combine(home, ".claude", "plans"),
        Path.Combine(home, ".codex", "sessions"), Path.Combine(home, ".codex", "archived_sessions"), Path.Combine(home, ".codex", "history.jsonl"),
        Path.Combine(home, ".gemini", "tmp"), Path.Combine(home, ".gemini", "history"),
        Path.Combine(roaming, "Claude", "claude-code-sessions"), Path.Combine(roaming, "Claude", "local-agent-mode-sessions"),
        Path.Combine(roaming, "Claude", "IndexedDB"), Path.Combine(roaming, "Claude", "Local Storage"),
        Path.Combine(roaming, "Cursor", "User"), Path.Combine(roaming, "Windsurf", "User"),
    ];

    /// Whether `path` is a conversation store, lies inside one, or contains one.
    public static bool Touches(string path, IEnumerable<string> stores)
    {
        var full = PathPolicy.Normalize(path);
        return stores.Select(PathPolicy.Normalize).Any(store =>
            PathPolicy.Comparer.Equals(full, store) || PathPolicy.IsBelow(full, store) || PathPolicy.IsBelow(store, full));
    }
}
