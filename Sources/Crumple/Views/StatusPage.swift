import SwiftUI
import AppKit

/// Live view of the machine: health, CPU, GPU, memory, battery, disk, network, temperature,
/// and the apps using the most memory. Refreshes every 1.5 seconds while it is open.
struct StatusPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let monitor = model.monitor
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text("状态").font(Theme.title(30))
                    Text("每 \(String(format: "%.1f", SystemMonitor.interval)) 秒刷新")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.tertiary)
                    Spacer()
                }
                .padding(.bottom, 4)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 16) {
                    HealthCard(monitor: monitor)
                    CPUCard(monitor: monitor)
                    GPUCard(monitor: monitor)
                    MemoryCard(monitor: monitor)
                    BatteryCard(monitor: monitor)
                    DiskCard(monitor: monitor)
                    NetworkCard(monitor: monitor)
                    ThermalCard(monitor: monitor)
                }

                ProcessTable(monitor: monitor)
            }
            .padding(.horizontal, 32)
            .padding(.top, 48)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.never)
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
    }
}

// MARK: - Card scaffolding

private struct StatusCard<Content: View>: View {
    let symbol: String
    let title: String
    var chip: String? = nil
    var chipColor: Color = Theme.secondary
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 16)).foregroundStyle(Theme.secondary)
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 4)
                if let chip {
                    Text(chip)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(chipColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(chipColor.opacity(0.14)))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            content
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .surfaceCard(radius: 16, padding: 16)
    }
}

private struct BigValue: View {
    let value: String
    let unit: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value).font(Theme.title(32)).monospacedDigit().contentTransition(.numericText())
            Text(unit).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

private struct Footnote: View {
    let text: String

    var body: some View {
        Text(text).font(.system(size: 12)).foregroundStyle(Theme.secondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A row of bars, newest on the right.
private struct BarHistory: View {
    let values: [Double]
    let color: Color

    var body: some View {
        Canvas { context, size in
            let count = 14
            let shown = Array(values.suffix(count))
            let gap: CGFloat = 3
            let width = (size.width - gap * CGFloat(count - 1)) / CGFloat(count)
            for (i, value) in shown.enumerated() {
                let x = CGFloat(count - shown.count + i) * (width + gap)
                let h = max(3, size.height * CGFloat(min(1, value)))
                context.fill(Path(roundedRect: CGRect(x: x, y: size.height - h, width: width, height: h), cornerRadius: 2),
                             with: .color(color.opacity(0.45 + 0.55 * min(1, value * 1.5))))
            }
        }
        .frame(height: 30)
        .accessibilityHidden(true)
    }
}

/// A line (optionally filled underneath) of the recent values.
private struct Sparkline: View {
    let values: [Double]
    let color: Color
    /// The value at the top of the chart; nil scales to the largest value shown.
    var ceiling: Double? = 1
    var filled = false

    var body: some View {
        Canvas { context, size in
            guard values.count > 1 else { return }
            let top = ceiling ?? max(values.max() ?? 1, 1)
            let step = size.width / CGFloat(values.count - 1)
            let points = values.enumerated().map { i, value in
                CGPoint(x: CGFloat(i) * step, y: size.height - 2 - (size.height - 4) * CGFloat(min(1, value / top)))
            }
            var line = Path()
            line.addLines(points)
            if filled {
                var area = line
                area.addLine(to: CGPoint(x: size.width, y: size.height))
                area.addLine(to: CGPoint(x: 0, y: size.height))
                area.closeSubpath()
                context.fill(area, with: .linearGradient(Gradient(colors: [color.opacity(0.35), color.opacity(0.02)]),
                                                         startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            }
            context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .frame(height: 30)
        .accessibilityHidden(true)
    }
}

// MARK: - Cards

private struct HealthCard: View {
    let monitor: SystemMonitor

    var body: some View {
        let health = monitor.health
        let info = SystemInfo.current
        let color = health.score >= 85 ? Page.smartClean.accent : health.score >= 70 ? Theme.warning : Theme.danger
        StatusCard(symbol: "heart.text.square.fill", title: String(localized: "健康度"),
                   chip: [info.chip.replacingOccurrences(of: "Apple ", with: ""), info.memory.byteString].joined(separator: " · ")) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(monitor.hasSample ? "\(health.score)" : "--").font(Theme.title(38)).contentTransition(.numericText())
                        Text(health.label).font(.system(size: 15, weight: .semibold)).foregroundStyle(color)
                    }
                    Footnote(text: health.note)
                    Spacer(minLength: 4)
                    Footnote(text: String(localized: "已运行 \(monitor.uptime.durationText)"))
                    Footnote(text: info.osVersion)
                }
                Spacer(minLength: 8)
                ZStack {
                    Circle().stroke(Theme.fill.opacity(0.08), lineWidth: 9)
                    Circle()
                        .trim(from: 0, to: Double(health.score) / 100)
                        .stroke(color, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.6), value: health.score)
                    Image(systemName: health.score >= 85 ? "checkmark" : "exclamationmark")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(color)
                }
                .frame(width: 86, height: 86)
            }
        }
    }
}

private struct CPUCard: View {
    let monitor: SystemMonitor

    var body: some View {
        StatusCard(symbol: "cpu", title: "CPU", chip: String(localized: "\(monitor.cores) 核")) {
            BigValue(value: "\(Int(monitor.cpu * 100))", unit: "%")
            BarHistory(values: monitor.cpuHistory, color: Page.smartClean.accent)
            Footnote(text: String(localized: "\(level(monitor.cpu)) · 平均负载 \(String(format: "%.1f", monitor.load))"))
        }
    }
}

private struct GPUCard: View {
    let monitor: SystemMonitor

    var body: some View {
        StatusCard(symbol: "square.stack.3d.down.forward.fill", title: "GPU") {
            if let gpu = monitor.gpu {
                BigValue(value: "\(Int(gpu * 100))", unit: "%")
                Sparkline(values: monitor.gpuHistory, color: Page.status.accent)
                Footnote(text: level(gpu))
            } else {
                BigValue(value: "--", unit: "%")
                Spacer(minLength: 30)
                Footnote(text: String(localized: "读不到 GPU 占用"))
            }
        }
    }
}

private struct MemoryCard: View {
    let monitor: SystemMonitor

    var body: some View {
        let memory = monitor.memory
        let pressure = memory.pressure >= 4 ? (String(localized: "压力很大"), Theme.danger)
            : memory.pressure >= 2 || memory.fraction > 0.85 ? (String(localized: "压力偏高"), Theme.warning)
            : (String(localized: "正常"), Page.smartClean.accent)
        StatusCard(symbol: "memorychip.fill", title: String(localized: "内存"), chip: pressure.0, chipColor: pressure.1) {
            BigValue(value: "\(Int(memory.fraction * 100))", unit: "%")
            Sparkline(values: monitor.memoryHistory, color: pressure.1, filled: true)
            Footnote(text: String(localized: "\(memory.used.byteString) · 交换 \(memory.swap.byteString)"))
        }
    }
}

private struct BatteryCard: View {
    let monitor: SystemMonitor

    var body: some View {
        if let battery = monitor.battery {
            StatusCard(symbol: "battery.100percent", title: String(localized: "电池"), chip: battery.health.map { String(localized: "健康 \($0)%") }) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    BigValue(value: "\(battery.percent)", unit: "%")
                    if battery.pluggedIn {
                        Label(battery.adapterWatts.map { "\($0)W" } ?? String(localized: "电源"), systemImage: "bolt.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Page.smartClean.accent)
                    }
                }
                ProgressBar(value: Double(battery.percent) / 100,
                            accent: battery.percent <= 20 ? Theme.danger : Page.smartClean.accent)
                Footnote(text: [statusText(battery), battery.cycles.map { String(localized: "循环 \($0) 次") }].compactMap { $0 }.joined(separator: " · "))
            }
        } else {
            StatusCard(symbol: "powerplug.fill", title: String(localized: "电源")) {
                BigValue(value: String(localized: "外接"), unit: String(localized: "电源"))
                Spacer(minLength: 20)
                Footnote(text: String(localized: "这台 Mac 没有电池"))
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

private struct DiskCard: View {
    let monitor: SystemMonitor

    var body: some View {
        StatusCard(symbol: "internaldrive.fill", title: String(localized: "可用空间"), chip: monitor.disk.map { String(format: "%.0f GB", Double($0.total) / 1_000_000_000) }) {
            let parts = (monitor.disk?.available ?? 0).byteString.split(separator: " ")
            BigValue(value: String(parts.first ?? "--"), unit: String(parts.last ?? ""))
            ProgressBar(value: monitor.disk?.usedFraction ?? 0, accent: Theme.chart)
            Footnote(text: String(localized: "读 \(monitor.diskRead.rateString) · 写 \(monitor.diskWrite.rateString)"))
        }
    }
}

private struct NetworkCard: View {
    let monitor: SystemMonitor

    var body: some View {
        StatusCard(symbol: "network", title: String(localized: "网络")) {
            let parts = monitor.download.rateString.split(separator: " ")
            BigValue(value: String(parts.first ?? "0"), unit: parts.dropFirst().joined(separator: " "))
            Sparkline(values: monitor.downloadHistory, color: Theme.chart, ceiling: nil)
            Footnote(text: String(localized: "下载 · 上传 \(monitor.upload.rateString)"))
        }
    }
}

private struct ThermalCard: View {
    let monitor: SystemMonitor

    var body: some View {
        let (label, color, step): (String, Color, Int) = switch monitor.thermal {
        case .nominal: (String(localized: "正常"), Page.smartClean.accent, 1)
        case .fair: (String(localized: "偏热"), Theme.warning, 2)
        case .serious: (String(localized: "很热"), Theme.warning, 3)
        case .critical: (String(localized: "过热"), Theme.danger, 4)
        @unknown default: (String(localized: "未知"), Theme.secondary, 1)
        }
        StatusCard(symbol: "thermometer.medium", title: String(localized: "温度"), chip: label, chipColor: color) {
            BigValue(value: label, unit: "")
            HStack(spacing: 4) {
                ForEach(1...4, id: \.self) { i in
                    Capsule().fill(i <= step ? color : Theme.fill.opacity(0.08)).frame(height: 8)
                }
            }
            .padding(.vertical, 11)
            Footnote(text: String(localized: "macOS 报告的散热状态"))
        }
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
