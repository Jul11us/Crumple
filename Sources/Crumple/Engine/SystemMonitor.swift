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
    /// The overall score, eased toward each new reading so it doesn't jump every refresh.
    private(set) var smoothedHealth: Double?
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
        let target = HealthScore.combine(healthFactors)
        smoothedHealth = smoothedHealth.map { $0 + 0.3 * (target - $0) } ?? target
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

    /// The five parts of the score, each 0–100, from the latest readings.
    var healthFactors: [HealthScore.Factor] {
        var factors = [
            HealthScore.memory(pressure: memory.pressure, swap: memory.swap),
            HealthScore.cpu(history: cpuHistory, load: load, cores: cores),
            HealthScore.disk(available: disk?.available ?? 0, total: disk?.total ?? 0),
            HealthScore.thermal(thermal),
        ]
        if let health = battery?.health { factors.append(HealthScore.battery(health: health)) }
        return factors
    }

    /// The overall score (smoothed between samples), what it means, and the weakest part.
    var health: (score: Int, label: String, note: String) {
        let factors = healthFactors
        let score = Int((smoothedHealth ?? HealthScore.combine(factors)).rounded())
        let weakest = factors.min { $0.score < $1.score }
        let note = weakest.map { $0.score < 85 ? $0.note : String(localized: "一切正常") } ?? String(localized: "一切正常")
        return (score, HealthScore.label(score), note)
    }
}

/// How healthy the Mac is right now, out of 100.
///
/// Each part is scored on a smooth curve rather than by fixed deductions, the parts are weighted
/// (memory 30%, disk 25%, CPU 20%, temperature 15%, battery 10%), and the weakest part caps the
/// total at its own score + 35, so one real problem can't be averaged away.
enum HealthScore {
    struct Factor: Identifiable, Equatable {
        let title: String
        let score: Int
        let weight: Double
        /// What is wrong, shown when this part is the weakest.
        let note: String
        var id: String { title }
    }

    static func combine(_ factors: [Factor]) -> Double {
        guard !factors.isEmpty else { return 100 }
        let total = factors.reduce(0) { $0 + $1.weight }
        let mean = factors.reduce(0) { $0 + Double($1.score) * $1.weight } / total
        let worst = Double(factors.map(\.score).min() ?? 100)
        return min(mean, worst + 35)
    }

    static func label(_ score: Int) -> String {
        score >= 90 ? String(localized: "很好")
            : score >= 75 ? String(localized: "良好")
            : score >= 55 ? String(localized: "一般")
            : String(localized: "需要关注")
    }

    /// Straight lines between the given (input, score) points.
    static func curve(_ x: Double, _ points: [(Double, Double)]) -> Double {
        guard let first = points.first, let last = points.last else { return 100 }
        if x <= first.0 { return first.1 }
        if x >= last.0 { return last.1 }
        for (a, b) in zip(points, points.dropFirst()) where x <= b.0 {
            return a.1 + (b.1 - a.1) * (x - a.0) / (b.0 - a.0)
        }
        return last.1
    }

    /// macOS fills memory on purpose, so how full it is says little. The kernel's pressure level
    /// and how much has spilled into swap are what slow a Mac down.
    static func memory(pressure: Int, swap: Int64) -> Factor {
        let base: Double = pressure >= 4 ? 25 : pressure >= 2 ? 62 : 100
        let swapGB = Double(swap) / 1_000_000_000
        let score = max(5, base - min(30, max(0, swapGB - 1) * 7))
        let note = pressure >= 4 ? String(localized: "内存压力很大")
            : pressure >= 2 ? String(localized: "内存压力偏高")
            : String(localized: "交换空间用得多")
        return Factor(title: String(localized: "内存"), score: Int(score.rounded()), weight: 0.30, note: note)
    }

    /// The last half minute, not this instant: a short spike is normal, staying busy is not.
    static func cpu(history: [Double], load: Double, cores: Int) -> Factor {
        let recent = history.suffix(20)
        let average = recent.isEmpty ? 0 : recent.reduce(0, +) / Double(recent.count)
        var score = curve(average, [(0.5, 100), (0.8, 70), (1.0, 40)])
        let perCore = load / Double(max(cores, 1))
        if perCore > 1 { score -= min(20, (perCore - 1) * 20) }
        return Factor(title: "CPU", score: Int(max(5, score).rounded()), weight: 0.20, note: String(localized: "CPU 一直很忙"))
    }

    static func disk(available: Int64, total: Int64) -> Factor {
        guard total > 0 else { return Factor(title: String(localized: "磁盘"), score: 100, weight: 0.25, note: "") }
        let free = Double(available) / Double(total)
        var score = curve(free, [(0, 0), (0.02, 15), (0.05, 40), (0.10, 70), (0.20, 100)])
        // A big disk can be 10% free and still have plenty; a small one can't afford that.
        if available < 5_000_000_000 { score = min(score, 35) } else if available < 10_000_000_000 { score = min(score, 60) }
        let note = score < 60 ? String(localized: "磁盘快满了") : String(localized: "磁盘空间偏少")
        return Factor(title: String(localized: "磁盘"), score: Int(score.rounded()), weight: 0.25, note: note)
    }

    static func thermal(_ state: ProcessInfo.ThermalState) -> Factor {
        let (score, note): (Int, String) = switch state {
        case .nominal: (100, "")
        case .fair: (75, String(localized: "温度偏高"))
        case .serious: (40, String(localized: "温度很高"))
        case .critical: (10, String(localized: "温度过高"))
        @unknown default: (100, "")
        }
        return Factor(title: String(localized: "温度"), score: score, weight: 0.15, note: note)
    }

    /// Battery health as macOS reports it (100% = like new).
    static func battery(health: Int) -> Factor {
        let score = curve(Double(health), [(50, 20), (70, 60), (80, 85), (90, 100)])
        return Factor(title: String(localized: "电池"), score: Int(score.rounded()), weight: 0.10,
                      note: String(localized: "电池已经老化"))
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
