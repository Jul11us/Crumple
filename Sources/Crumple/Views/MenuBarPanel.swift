import SwiftUI
import AppKit

/// The little window under the menu bar icon: how the Mac is doing, and a couple of shortcuts.
struct MenuBarPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let monitor = model.monitor
        let health = monitor.health
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                AppGlyph().frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Crumple").font(.system(size: 14, weight: .semibold))
                    Text(monitor.hasSample ? String(localized: "状态\(health.label) · \(health.note)") : String(localized: "正在读取…"))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if monitor.hasSample {
                    Text("\(health.score)")
                        .font(.system(size: 20, weight: .semibold).monospacedDigit())
                        .foregroundStyle(scoreColor(health.score))
                        .accessibilityLabel("健康分 \(health.score)")
                }
            }

            VStack(spacing: 10) {
                Meter(symbol: "cpu", title: "CPU", value: "\(Int(monitor.cpu * 100))%",
                      fraction: monitor.cpu, color: Page.status.accent)
                Meter(symbol: "memorychip", title: String(localized: "内存"), value: "\(Int(monitor.memory.fraction * 100))%",
                      fraction: monitor.memory.fraction, color: Page.analysis.accent)
                if let disk = model.disk {
                    Meter(symbol: "internaldrive", title: String(localized: "磁盘"), value: String(localized: "可用 \(disk.available.byteString)"),
                          fraction: disk.usedFraction, color: Page.overview.accent)
                }
                if let battery = monitor.battery {
                    Meter(symbol: battery.charging ? "battery.100.bolt" : "battery.75", title: String(localized: "电池"),
                          value: "\(battery.percent)%", fraction: Double(battery.percent) / 100, color: Page.optimize.accent)
                }
            }

            if let (top, busy) = standout(monitor.apps) {
                HStack(spacing: 8) {
                    if let icon = top.icon {
                        Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                    }
                    Text(busy ? String(localized: "最忙：\(top.name)") : String(localized: "最占内存：\(top.name)")).font(.system(size: 12)).lineLimit(1)
                    Spacer()
                    Text(busy ? "\(Int(top.cpu))% CPU" : top.memory.byteString)
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(Theme.secondary)
                }
                .accessibilityElement(children: .combine)
            }

            Divider().overlay(Theme.stroke)

            VStack(spacing: 4) {
                PanelButton(symbol: Page.smartClean.symbol, title: String(localized: "智能清理"), color: Page.smartClean.accent) {
                    showMainWindow()
                    model.startSmartScan()
                }
                PanelButton(symbol: "trash", title: trashTitle, color: Page.history.accent) {
                    showMainWindow()
                    model.requestEmptyTrash()
                }
                .disabled(model.isCleaning || model.trashSize == 0)
            }

            HStack {
                Button("打开 Crumple") { showMainWindow() }
                    .buttonStyle(GhostButtonStyle())
                Spacer()
                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(GhostButtonStyle())
                .accessibilityLabel("设置")
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .buttonStyle(GhostButtonStyle())
                .accessibilityLabel("退出 Crumple")
            }
        }
        .padding(16)
        .frame(width: 300)
        .background(Theme.base)
        .preferredColorScheme(model.appearance.colorScheme)
        .onAppear {
            model.openMainWindow = { openWindow(id: "main") }
            model.refreshDisk()
            monitor.start()
        }
        .onDisappear { monitor.stop() }
    }

    private var trashTitle: String {
        switch model.trashSize {
        case 0?: String(localized: "废纸篓是空的")
        case let size?: String(localized: "清倒废纸篓 · \(size.byteString)")
        case nil: String(localized: "清倒废纸篓")
        }
    }

    /// The app working hardest right now, or, when nothing is busy, the one holding the most memory.
    private func standout(_ apps: [SystemMonitor.AppUsage]) -> (SystemMonitor.AppUsage, Bool)? {
        if let busiest = apps.max(by: { $0.cpu < $1.cpu }), busiest.cpu >= 5 { return (busiest, true) }
        return apps.max(by: { $0.memory < $1.memory }).map { ($0, false) }
    }

    private func showMainWindow() {
        openWindow(id: "main")
        NSApp.activate()
    }

    private func scoreColor(_ score: Int) -> Color {
        score >= 80 ? Theme.accent : score >= 60 ? Theme.warning : Theme.danger
    }
}

private struct Meter: View {
    let symbol: String
    let title: String
    let value: String
    let fraction: Double
    let color: Color

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(color).frame(width: 16)
                Text(title).font(.system(size: 12))
                Spacer()
                Text(value).font(.system(size: 12, weight: .medium).monospacedDigit()).foregroundStyle(Theme.secondary)
            }
            ProgressBar(value: fraction, accent: color)
                .frame(height: 5)
                .clipShape(Capsule())
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PanelButton: View {
    let symbol: String
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Hoverable { hovering in
            Button(action: action) {
                HStack(spacing: 10) {
                    SymbolTile(symbol: symbol, color: color, size: 24)
                    Text(title).font(.system(size: 13))
                    Spacer()
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.fill.opacity(hovering ? 0.08 : 0)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

/// The menu bar icon: the hoop and the paper ball, as a template image so it takes the menu bar's colour.
@MainActor
enum MenuBarIcon {
    static let image: NSImage = {
        let mark = Canvas { context, size in
            var g = context
            // The mark sits in roughly x 250…770, y 200…780 of the logo's 1024 grid.
            let scale = size.height / 580
            g.translateBy(x: (size.width - 520 * scale) / 2, y: 0)
            g.scaleBy(x: scale, y: scale)
            g.translateBy(x: -250, y: -200)
            let ring = BinLogo.hoopRing
            var net = Path()
            let bottom = CGRect(x: 432, y: 735, width: 160, height: 30)
            for i in 0...4 {
                let t = CGFloat(i) / 4
                net.move(to: CGPoint(x: ring.minX + 30 + t * (ring.width - 60), y: ring.maxY - 6))
                net.addLine(to: CGPoint(x: bottom.minX + t * bottom.width, y: bottom.midY))
            }
            g.stroke(net, with: .color(.black), style: StrokeStyle(lineWidth: 34, lineCap: .round))
            g.stroke(Path(ellipseIn: ring), with: .color(.black), lineWidth: 56)
            g.fill(Path(ellipseIn: CGRect(x: 566 - 96, y: 316 - 96, width: 192, height: 192)), with: .color(.black))
            for (x, y, r) in [(300.0, 420.0, 22.0), (360.0, 330.0, 26.0)] {
                g.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)), with: .color(.black))
            }
        }
        .frame(width: 20, height: 18)
        let renderer = ImageRenderer(content: mark)
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage(systemSymbolName: "trash", accessibilityDescription: nil)!
        image.isTemplate = true
        image.accessibilityDescription = "Crumple"
        return image
    }()
}
