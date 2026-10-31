import Foundation
import AppKit
import IOKit
import IOKit.ps
import Darwin

/// Samples the machine's live state — CPU, GPU, memory, battery, disk, network and the busiest apps —
/// using public APIs only. It runs only while a page that shows it is on screen.
@MainActor @Observable
final class SystemMonitor {
    struct Memory {
        var used: Int64 = 0
        var total: Int64 = 0
        var swap: Int64 = 0
        /// The kernel's pressure level: 1 normal, 2 warning, 4 critical.
        var pressure = 1

        var fraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
    }

    struct Battery {
        var percent: Int
        var charging: Bool
        var pluggedIn: Bool
        var adapterWatts: Int? = nil
        var health: Int? = nil
        var cycles: Int? = nil
        var minutesLeft: Int? = nil
    }

    /// One app (with all its helper processes) or one stand-alone process.
    struct AppUsage: Identifiable {
        let id: String
        let name: String
        let icon: NSImage?
        let memory: Int64
        let cpu: Double
        let pid: Int32
        let app: NSRunningApplication?
    }

    private(set) var cpu = 0.0
    private(set) var cpuHistory: [Double] = []
    private(set) var load = 0.0
    private(set) var gpu: Double?
    private(set) var gpuHistory: [Double] = []
    private(set) var memory = Memory()
    private(set) var memoryHistory: [Double] = []
    private(set) var battery: Battery?
    private(set) var disk: DiskInfo?
    private(set) var diskRead = 0.0
    private(set) var diskWrite = 0.0
    private(set) var download = 0.0
    private(set) var upload = 0.0
    private(set) var downloadHistory: [Double] = []
    private(set) var thermal = ProcessInfo.ThermalState.nominal
    private(set) var uptime: TimeInterval = 0
    private(set) var apps: [AppUsage] = []
    private(set) var processCount = 0
    private(set) var hasSample = false
    let cores = ProcessInfo.processInfo.activeProcessorCount

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var watchers = 0
    @ObservationIgnored private var lastTicks: [UInt32]?
    @ObservationIgnored private var lastNetwork: (down: UInt64, up: UInt64, at: Date)?
    @ObservationIgnored private var lastDisk: (read: UInt64, write: UInt64, at: Date)?
    @ObservationIgnored private var round = 0

    static let interval = 1.5
    private static let historyLength = 30

    func start() {
        watchers += 1
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.sample()
                try? await Task.sleep(for: .seconds(SystemMonitor.interval))
            }
        }
    }

    func stop() {
        watchers = max(0, watchers - 1)
        guard watchers == 0 else { return }
        task?.cancel()
        task = nil
    }

    // MARK: - Sampling

    private func sample() async {
        if let usage = readCPU() {
            cpu = usage
            Self.append(&cpuHistory, usage)
        }
        var loads = [Double](repeating: 0, count: 3)
        if getloadavg(&loads, 3) > 0 { load = loads[0] }
        gpu = Self.readGPU()
        if let gpu { Self.append(&gpuHistory, gpu) }
        memory = Self.readMemory()
        Self.append(&memoryHistory, memory.fraction)
        battery = Self.readBattery()
        disk = DiskInfo.current()
        thermal = ProcessInfo.processInfo.thermalState
        uptime = Self.readUptime()

        let now = Date()
        let io = Self.readDiskBytes()
        if let last = lastDisk {
            let dt = now.timeIntervalSince(last.at)
            diskRead = io.read >= last.read ? Double(io.read - last.read) / dt : 0
            diskWrite = io.write >= last.write ? Double(io.write - last.write) / dt : 0
        }
        lastDisk = (io.read, io.write, now)
        let net = Self.readNetworkBytes()
        if let last = lastNetwork {
            let dt = now.timeIntervalSince(last.at)
            download = net.down >= last.down ? Double(net.down - last.down) / dt : 0
            upload = net.up >= last.up ? Double(net.up - last.up) / dt : 0
            Self.append(&downloadHistory, download)
        }
        lastNetwork = (net.down, net.up, now)

        // The process list costs a `ps` call, so refresh it every other round.
        if round % 2 == 0 {
            let rows = await Task.detached(priority: .utility) { Self.readProcesses() }.value
            processCount = rows.count
            apps = Self.group(rows)
        }
        round += 1
        hasSample = true
    }

    private static func append(_ history: inout [Double], _ value: Double) {
        history.append(value)
        if history.count > historyLength { history.removeFirst(history.count - historyLength) }
    }

    private func readCPU() -> Double? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        // user, system, idle, nice
        let ticks = [info.cpu_ticks.0, info.cpu_ticks.1, info.cpu_ticks.2, info.cpu_ticks.3]
        defer { lastTicks = ticks }
        guard let last = lastTicks else { return nil }
        let delta = zip(ticks, last).map { Double($0 &- $1) }
        let total = delta.reduce(0, +)
        return total > 0 ? (delta[0] + delta[1] + delta[3]) / total : nil
    }

    nonisolated private static func readGPU() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var usage: Double?
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let stats = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any],
               let percent = (stats["Device Utilization %"] as? NSNumber)?.doubleValue {
                usage = max(usage ?? 0, percent / 100)
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return usage
    }

    /// "Memory used" the way Activity Monitor counts it: app memory + wired + compressed.
    nonisolated private static func readMemory() -> Memory {
        var memory = Memory(total: Int64(ProcessInfo.processInfo.physicalMemory))
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            let page = Int64(vm_kernel_page_size)
            let app = Int64(stats.internal_page_count) - Int64(stats.purgeable_count)
            memory.used = (app + Int64(stats.wire_count) + Int64(stats.compressor_page_count)) * page
        }
        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 { memory.swap = Int64(swap.xsu_used) }
        var level: Int32 = 1
        size = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 { memory.pressure = Int(level) }
        return memory
    }

    nonisolated private static func readBattery() -> Battery? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  info[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let current = info[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maximum = info[kIOPSMaxCapacityKey] as? Int ?? 100
            var battery = Battery(percent: maximum > 0 ? current * 100 / maximum : current,
                                  charging: info[kIOPSIsChargingKey] as? Bool ?? false,
                                  pluggedIn: info[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue)
            if let minutes = info[kIOPSTimeToEmptyKey] as? Int, minutes > 0 { battery.minutesLeft = minutes }
            if let adapter = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] {
                battery.adapterWatts = adapter[kIOPSPowerAdapterWattsKey] as? Int
            }
            let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
            if service != 0 {
                defer { IOObjectRelease(service) }
                func property(_ key: String) -> Any? {
                    IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
                }
                // Newer Macs keep the capacities inside "BatteryData"; older ones at the top level.
                let data = property("BatteryData") as? [String: Any] ?? [:]
                func value(_ key: String) -> Int? {
                    ((data[key] ?? property(key)) as? NSNumber)?.intValue
                }
                if let design = value("DesignCapacity"), design > 0,
                   let full = value("FullChargeCapacity") ?? value("AppleRawMaxCapacity") ?? value("NominalChargeCapacity") {
                    battery.health = min(100, full * 100 / design)
                }
                battery.cycles = value("CycleCount")
            }
            return battery
        }
        return nil
    }

    nonisolated private static func readUptime() -> TimeInterval {
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0 else { return 0 }
        return Date().timeIntervalSince1970 - Double(boot.tv_sec)
    }

    nonisolated private static func readDiskBytes() -> (read: UInt64, write: UInt64) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS else { return (0, 0) }
        defer { IOObjectRelease(iterator) }
        var read: UInt64 = 0
        var write: UInt64 = 0
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let stats = IORegistryEntryCreateCFProperty(service, "Statistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any] {
                read += (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
                write += (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return (read, write)
    }

    /// Bytes in and out over the physical interfaces (en0, en1…).
    nonisolated private static func readNetworkBytes() -> (down: UInt64, up: UInt64) {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return (0, 0) }
        defer { freeifaddrs(list) }
        var down: UInt64 = 0
        var up: UInt64 = 0
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK),
                  String(cString: entry.pointee.ifa_name).hasPrefix("en"),
                  let data = entry.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }
            down += UInt64(data.pointee.ifi_ibytes)
            up += UInt64(data.pointee.ifi_obytes)
        }
        return (down, up)
    }

    // MARK: - Processes

    struct ProcessRow: Sendable {
        let pid: Int32
        let memory: Int64
        let cpu: Double
        let path: String
    }

    nonisolated private static func readProcesses() -> [ProcessRow] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,rss=,%cpu=,comm="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap { line in
            let fields = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard fields.count == 4, let pid = Int32(fields[0]), let rss = Int64(fields[1]), let cpu = Double(fields[2]) else { return nil }
            return ProcessRow(pid: pid, memory: rss * 1024, cpu: cpu, path: String(fields[3]))
        }
    }

    /// Folds helper processes into the app they belong to (the outermost .app in their path).
    private static func group(_ rows: [ProcessRow]) -> [AppUsage] {
        var groups: [String: (bundle: URL?, memory: Int64, cpu: Double, pids: [Int32])] = [:]
        for row in rows {
            var key = (row.path as NSString).lastPathComponent
            var bundle: URL?
            if let range = row.path.range(of: ".app/") {
                key = String(row.path[..<range.lowerBound]) + ".app"
                bundle = URL(fileURLWithPath: key)
            }
            var group = groups[key] ?? (bundle, 0, 0, [])
            group.memory += row.memory
            group.cpu += row.cpu
            group.pids.append(row.pid)
            groups[key] = group
        }
        let running = NSWorkspace.shared.runningApplications
        return groups.sorted { $0.value.memory > $1.value.memory }.prefix(12).map { key, group in
            let app = running.first { $0.bundleURL?.path == key } ?? running.first { group.pids.contains($0.processIdentifier) }
            var name = app?.localizedName ?? key
            if app == nil, let bundle = group.bundle {
                name = FileManager.default.displayName(atPath: bundle.path)
                if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
            }
            return AppUsage(id: key, name: name, icon: app?.icon ?? group.bundle.map { NSWorkspace.shared.icon(forFile: $0.path) },
                            memory: group.memory, cpu: group.cpu, pid: app?.processIdentifier ?? group.pids.min() ?? 0, app: app)
        }
    }

    // MARK: - Health

    /// A rough 0–100 score with the main thing dragging it down.
    var health: (score: Int, label: String, note: String) {
        var score = 100
        var notes: [String] = []
        if memory.pressure >= 4 {
            score -= 25
            notes.append(String(localized: "内存压力很大"))
        } else if memory.pressure >= 2 || memory.fraction > 0.85 {
            score -= 12
            notes.append(String(localized: "内存压力偏高"))
        }
        if memory.swap > 2_000_000_000 { score -= 5 }
        if cpu > 0.85 {
            score -= 10
            notes.append(String(localized: "CPU 很忙"))
        }
        if let disk, disk.total > 0 {
            let free = Double(disk.available) / Double(disk.total)
            if free < 0.1 {
                score -= 18
                notes.append(String(localized: "磁盘快满了"))
            } else if free < 0.2 {
                score -= 8
                notes.append(String(localized: "磁盘空间偏少"))
            }
        }
        switch thermal {
        case .serious:
            score -= 15
            notes.append(String(localized: "温度偏高"))
        case .critical:
            score -= 30
            notes.append(String(localized: "温度过高"))
        default: break
        }
        if let health = battery?.health, health < 80 {
            score -= 8
            notes.append(String(localized: "电池已经老化"))
        }
        score = max(0, score)
        return (score, score >= 85 ? String(localized: "良好") : score >= 70 ? String(localized: "一般") : String(localized: "需要关注"), notes.first ?? String(localized: "一切正常"))
    }
}

extension Double {
    /// "12 KB/s"
    var rateString: String { Int64(self).byteString + "/s" }
}

extension TimeInterval {
    /// "18 天 3 小时", "2 小时 5 分钟"
    var durationText: String {
        let minutes = Int(self) / 60
        let days = minutes / 1440
        let hours = minutes % 1440 / 60
        if days > 0 { return String(localized: "\(days) 天 \(hours) 小时") }
        if hours > 0 { return String(localized: "\(hours) 小时 \(minutes % 60) 分钟") }
        return String(localized: "\(minutes) 分钟")
    }
}
