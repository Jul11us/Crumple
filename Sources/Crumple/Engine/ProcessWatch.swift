import Darwin
import Foundation

/// Which processes are running, by name. Apps are better asked through NSWorkspace, but command-line
/// agents (claude, codex, ollama…) have no bundle ID, so their files are guarded by process name instead.
enum ProcessWatch {
    /// The names of every process running right now, as `proc_name` reports them ("Claude", "claude", "Claude Helper").
    static func runningNames() -> Set<String> {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) * 2)
        let filled = pids.withUnsafeMutableBufferPointer { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count * MemoryLayout<pid_t>.size))
        }
        var names = Set<String>()
        var buffer = [CChar](repeating: 0, count: 512)
        for pid in pids.prefix(Int(max(filled, 0))) where pid > 0 {
            let length = buffer.withUnsafeMutableBufferPointer { proc_name(pid, $0.baseAddress, UInt32($0.count)) }
            if length > 0 { names.insert(String(cString: buffer)) }
        }
        return names
    }

    /// Whether any of `names` is running: exactly, or as a helper of the same name ("Claude Helper (GPU)").
    static func isRunning(any names: [String], among running: Set<String>) -> Bool {
        names.contains { name in running.contains(name) || running.contains { $0.hasPrefix(name + " ") } }
    }

    static func isRunning(any names: [String]) -> Bool {
        names.isEmpty ? false : isRunning(any: names, among: runningNames())
    }
}
