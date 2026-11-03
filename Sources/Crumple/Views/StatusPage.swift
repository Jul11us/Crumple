import SwiftUI
import AppKit

/// Live view of the machine: health, CPU, GPU, memory, battery, disk, network, temperature,
/// and the apps using the most memory. Refreshes every 1.5 seconds while it is open.
struct StatusPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let monitor = model.monitor
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("状态").font(Theme.title(30))
                    Text("每 \(String(format: "%.1f", SystemMonitor.interval)) 秒刷新")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.tertiary)
                }
                HealthLine(monitor: monitor)
                Readings(monitor: monitor)
                ProcessTable(monitor: monitor)
            }
            .padding(.leading, 32)
            // The right-hand column stays clear for the basket, which sits in the corner of every page.
            .padding(.trailing, BasketGeometry.reservedTrailing)
            .padding(.top, 48)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.never)
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
    }
}

// MARK: - Health

/// The score as one printed line, with the machine's particulars underneath.
private struct HealthLine: View {
    let monitor: SystemMonitor

    var body: some View {
        let health = monitor.health
        let info = SystemInfo.current
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(monitor.hasSample ? "\(health.score)" : "--")
                    .font(Theme.title(44))
                    .contentTransition(.numericText())
                Text([health.label, health.note].joined(separator: " · "))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(health.score >= 70 ? Theme.primary : Theme.danger)
            }
            Text([info.chip, info.memory.byteString, info.osVersion,
                  String(localized: "已运行 \(monitor.uptime.durationText)")].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "健康分 \(health.score)"))
    }
}

// MARK: - Readings

/// Every reading on one sheet: name, figure, a thin trace of the last few seconds, and a note.
private struct Readings: View {
    let monitor: SystemMonitor

    var body: some View {
        let memory = monitor.memory
        let pressured = memory.pressure >= 2 || memory.fraction > 0.85
        let pressure = memory.pressure >= 4 ? String(localized: "压力很大") : String(localized: "压力偏高")
        VStack(spacing: 0) {
            ReadingRow(title: "CPU", value: "\(Int(monitor.cpu * 100))", unit: "%",
                       note: [level(monitor.cpu), String(localized: "平均负载 \(String(format: "%.1f", monitor.load))"),
                              String(localized: "\(monitor.cores) 核")].joined(separator: " · ")) {
                Trace(values: monitor.cpuHistory)
            }
            Divider().overlay(Theme.stroke)
            ReadingRow(title: "GPU", value: monitor.gpu.map { "\(Int($0 * 100))" } ?? "--", unit: "%",
                       note: monitor.gpu.map(level) ?? String(localized: "读不到 GPU 占用")) {
                Trace(values: monitor.gpuHistory)
            }
            Divider().overlay(Theme.stroke)
            ReadingRow(title: String(localized: "内存"), value: "\(Int(memory.fraction * 100))", unit: "%",
                       note: ([pressured ? pressure : nil, memory.used.byteString,
                               String(localized: "交换 \(memory.swap.byteString)")] as [String?]).compactMap { $0 }.joined(separator: " · "),
                       warning: pressured) {
                Trace(values: monitor.memoryHistory)
            }
            Divider().overlay(Theme.stroke)
            batteryRow
            Divider().overlay(Theme.stroke)
            let free = (monitor.disk?.available ?? 0).byteString.split(separator: " ")
            ReadingRow(title: String(localized: "可用空间"), value: String(free.first ?? "--"), unit: String(free.dropFirst().first ?? ""),
                       note: String(localized: "读 \(monitor.diskRead.rateString) · 写 \(monitor.diskWrite.rateString)")) {
                Gauge(fraction: monitor.disk?.usedFraction ?? 0)
            }
            Divider().overlay(Theme.stroke)
            let down = monitor.download.rateString.split(separator: " ")
            ReadingRow(title: String(localized: "网络"), value: String(down.first ?? "0"), unit: down.dropFirst().joined(separator: " "),
                       note: String(localized: "下载 · 上传 \(monitor.upload.rateString)")) {
                Trace(values: monitor.downloadHistory, ceiling: nil)
            }
            Divider().overlay(Theme.stroke)
            thermalRow
        }
        .surfaceCard(radius: 16, padding: 8)
    }

    @ViewBuilder private var batteryRow: some View {
        if let battery = monitor.battery {
            ReadingRow(title: String(localized: "电池"), value: "\(battery.percent)", unit: "%",
                       note: [statusText(battery), battery.cycles.map { String(localized: "循环 \($0) 次") },
                              battery.health.map { String(localized: "健康 \($0)%") }].compactMap { $0 }.joined(separator: " · "),
                       warning: battery.percent <= 20 && !battery.pluggedIn) {
                Gauge(fraction: Double(battery.percent) / 100)
            }
        } else {
            ReadingRow(title: String(localized: "电源"), value: String(localized: "外接"), unit: "",
                       note: String(localized: "这台 Mac 没有电池")) { Color.clear }
        }
    }

    private var thermalRow: some View {
        let (label, step): (String, Int) = switch monitor.thermal {
        case .nominal: (String(localized: "正常"), 1)
        case .fair: (String(localized: "偏热"), 2)
        case .serious: (String(localized: "很热"), 3)
        case .critical: (String(localized: "过热"), 4)
        @unknown default: (String(localized: "未知"), 1)
        }
        return ReadingRow(title: String(localized: "温度"), value: label, unit: "",
                          note: String(localized: "macOS 报告的散热状态"), warning: step >= 3) {
            HStack(spacing: 3) {
                ForEach(1...4, id: \.self) { i in
                    Rectangle().fill(i <= step ? Theme.primary : Theme.raised).frame(height: 6)
                }
            }
        }
    }

    private func statusText(_ battery: SystemMonitor.Battery) -> String {
        if battery.charging { return String(localized: "正在充电") }
        if battery.pluggedIn { return battery.percent >= 99 ? String(localized: "已充满") : String(localized: "已接电源") }
        if let minutes = battery.minutesLeft { return String(localized: "约剩 \(TimeInterval(minutes * 60).durationText)") }
        return String(localized: "使用电池")
    }
}

private struct ReadingRow<Trace: View>: View {
    let title: String
    let value: String
    let unit: String
    let note: String
    var warning = false
    @ViewBuilder let trace: Trace

    var body: some View {
        HStack(spacing: 20) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondary)
                .frame(width: 84, alignment: .leading)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(Theme.figures(22, weight: .medium)).contentTransition(.numericText())
                Text(unit).font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
            .lineLimit(1)
            .frame(width: 150, alignment: .leading)
            trace
                .frame(width: 180, height: 22)
            Text(note)
                .font(.system(size: 12))
                .foregroundStyle(warning ? Theme.warning : Theme.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(value)\(unit)")
        .accessibilityValue(note)
    }
}

/// A thin ink line of the recent values, newest on the right.
private struct Trace: View {
    let values: [Double]
    /// The value at the top; nil scales to the largest value shown.
    var ceiling: Double? = 1

    var body: some View {
        Canvas { context, size in
            var base = Path()
            base.move(to: CGPoint(x: 0, y: size.height - 0.5))
            base.addLine(to: CGPoint(x: size.width, y: size.height - 0.5))
            context.stroke(base, with: .color(Theme.stroke), lineWidth: 1)
            guard values.count > 1 else { return }
            let top = ceiling ?? max(values.max() ?? 1, 1)
            let step = size.width / CGFloat(values.count - 1)
            var line = Path()
            line.addLines(values.enumerated().map { i, value in
                CGPoint(x: CGFloat(i) * step, y: size.height - 1 - (size.height - 3) * CGFloat(min(1, value / top)))
            })
            context.stroke(line, with: .color(Theme.primary), style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

/// How full something is, as a flat ink bar.
private struct Gauge: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Theme.raised)
                Rectangle().fill(Theme.primary).frame(width: geo.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

private func level(_ usage: Double) -> String {
    usage < 0.3 ? String(localized: "低负载") : usage < 0.7 ? String(localized: "中等负载") : String(localized: "高负载")
}

// MARK: - Processes

private struct ProcessTable: View {
    let monitor: SystemMonitor
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("名称（\(monitor.processCount) 个进程）")
                Spacer()
                Text("内存").frame(width: 90, alignment: .trailing)
                Text("% CPU").frame(width: 150, alignment: .trailing)
                Text("PID").frame(width: 70, alignment: .trailing)
                Color.clear.frame(width: 34, height: 1)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.tertiary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Rectangle().fill(Theme.stroke).frame(height: 1)

            if monitor.apps.isEmpty {
                ProgressView().controlSize(.small).padding(20)
            }
            ForEach(monitor.apps) { usage in
                Hoverable { hovering in
                    HStack(spacing: 10) {
                        Group {
                            if let icon = usage.icon {
                                Image(nsImage: icon).resizable().interpolation(.high)
                            } else {
                                Image(systemName: "gearshape.fill").foregroundStyle(Theme.tertiary)
                            }
                        }
                        .frame(width: 22, height: 22)
                        Text(usage.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(usage.memory.byteString)
                            .font(.system(size: 12).monospacedDigit())
                            .frame(width: 90, alignment: .trailing)
                        HStack(spacing: 8) {
                            let busy = usage.cpu > 80
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Theme.fill.opacity(0.08))
                                    Capsule().fill(busy ? Theme.danger : Theme.secondary)
                                        .frame(width: geo.size.width * min(1, usage.cpu / 100))
                                }
                            }
                            .frame(width: 64, height: 5)
                            Text(String(format: "%.1f", usage.cpu))
                                .font(.system(size: 12).monospacedDigit())
                                .foregroundStyle(busy ? Theme.danger : Theme.primary.opacity(0.85))
                                .frame(width: 48, alignment: .trailing)
                        }
                        .frame(width: 150, alignment: .trailing)
                        Text(verbatim: String(usage.pid))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Theme.secondary)
                            .frame(width: 70, alignment: .trailing)
                        actions(for: usage).frame(width: 34)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.fill.opacity(hovering ? 0.05 : 0)))
                }
            }
        }
        .surfaceCard(radius: 16, padding: 8)
    }

    @ViewBuilder private func actions(for usage: SystemMonitor.AppUsage) -> some View {
        if let app = usage.app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            Menu {
                Button("退出 \(usage.name)") { app.terminate() }
                Button("强制退出…") { model.requestForceQuit(app, name: usage.name) }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        } else {
            Color.clear
        }
    }
}
