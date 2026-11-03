import SwiftUI
import AppKit

/// Optimise: quit memory-hungry apps, switch off background launch items, run maintenance jobs.
struct OptimizePage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("优化").font(Theme.title(30))
                    Text("关掉占资源的应用，管住偷偷启动的后台程序，再做几项常用维护。")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondary)
                }
                HeavyApps()
                LaunchItems()
                MaintenanceGrid()
            }
            .padding(.leading, 36)
            // The right-hand column stays clear for the basket, which sits in the corner of every page.
            .padding(.trailing, BasketGeometry.reservedTrailing)
            .padding(.top, 48)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.never)
        .onAppear {
            model.monitor.start()
            model.loadLaunchAgents()
        }
        .onDisappear { model.monitor.stop() }
    }
}

private struct SectionTitle: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title).font(.system(size: 16, weight: .semibold))
            Text(detail).font(.system(size: 12)).foregroundStyle(Theme.tertiary)
        }
    }
}

private struct HeavyApps: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let apps = model.monitor.apps.filter { $0.app != nil && $0.app?.processIdentifier != ProcessInfo.processInfo.processIdentifier }.prefix(5)
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: String(localized: "占用最多的应用"), detail: String(localized: "内存 \(Int(model.monitor.memory.fraction * 100))% 已用 · 不用的就先退出"))
            VStack(spacing: 2) {
                if apps.isEmpty {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(16)
                }
                ForEach(Array(apps)) { usage in
                    HStack(spacing: 12) {
                        if let icon = usage.icon {
                            Image(nsImage: icon).resizable().interpolation(.high).frame(width: 28, height: 28)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(usage.name).font(.system(size: 13, weight: .medium))
                            Text("内存 \(usage.memory.byteString) · CPU \(String(format: "%.1f", usage.cpu))%")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.tertiary)
                        }
                        Spacer()
                        Button("退出") { usage.app?.terminate() }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
            .surfaceCard(radius: 16, padding: 6)
        }
    }
}

private struct LaunchItems: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let agents = model.launchAgents
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle(title: String(localized: "后台启动项"), detail: String(localized: "开机或登录时自己跑起来的后台程序"))
                Spacer()
                Button {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
                } label: {
                    Label("登录项设置", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(GhostButtonStyle())
            }
            VStack(spacing: 2) {
                if agents.isEmpty {
                    Text("没有找到后台启动项").font(.system(size: 13)).foregroundStyle(Theme.secondary)
                        .frame(maxWidth: .infinity).padding(16)
                }
                ForEach(agents) { agent in
                    HStack(spacing: 12) {
                        SymbolTile(symbol: agent.isUserLevel ? "person.fill" : "lock.fill",
                                   color: agent.isUserLevel ? Page.optimize.accent : Color(hex: 0x7D93A6), size: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(agent.label).font(.system(size: 13, weight: .medium)).lineLimit(1)
                            Text(agent.program ?? Paths.display(agent.url))
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 12)
                        if agent.isUserLevel {
                            Toggle("", isOn: Binding(get: { agent.isEnabled }, set: { model.setLaunchAgent(agent, enabled: $0) }))
                                .toggleStyle(.switch)
                                .labelsHidden()
                                .controlSize(.small)
                        } else {
                            Text("系统级 · 只读").font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .opacity(agent.isEnabled ? 1 : 0.6)
                }
            }
            .surfaceCard(radius: 16, padding: 6)
            Text("关掉的启动项会挪到“启动代理/Disabled by Crumple”里，随时可以打开恢复。")
                .font(.system(size: 12))
                .foregroundStyle(Theme.tertiary)
        }
    }
}

private struct MaintenanceGrid: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: String(localized: "维护"), detail: String(localized: "带锁的需要输入管理员密码，由 macOS 自己弹窗"))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                ForEach(MaintenanceTask.all) { task in
                    let state = model.taskStates[task.id] ?? .idle
                    HStack(alignment: .top, spacing: 12) {
                        SymbolTile(symbol: task.symbol, color: Page.optimize.accent, size: 34)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(task.title).font(.system(size: 14, weight: .semibold))
                                if task.needsAdmin {
                                    Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(Theme.tertiary)
                                }
                            }
                            Text(task.detail).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        Group {
                            switch state {
                            case .idle:
                                Button("运行") { model.runMaintenance(task) }
                                    .buttonStyle(SecondaryButtonStyle())
                                    .disabled(Paths.isDemo)
                                    .opacity(Paths.isDemo ? 0.4 : 1)
                                    .help(Paths.isDemo ? String(localized: "演示模式下不运行维护任务") : task.detail)
                            case .running:
                                ProgressView().controlSize(.small)
                            case .done:
                                Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundStyle(Page.smartClean.accent)
                            case .failed:
                                Button("重试") { model.runMaintenance(task) }
                                    .buttonStyle(SecondaryButtonStyle())
                            }
                        }
                        .frame(minWidth: 60)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .surfaceCard(radius: 16, padding: 14)
                }
            }
        }
    }
}
