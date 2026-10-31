import SwiftUI

struct OverviewPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let info = SystemInfo.current
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("概览").font(Theme.title(30))
                    Text([info.computerName, info.chip, String(localized: "\(info.memory.byteString) 内存"), info.osVersion]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondary)
                }

                if !model.hasFullDiskAccess && !model.hidesPermissionBanner {
                    PermissionBanner()
                }

                HStack(alignment: .top, spacing: 16) {
                    StorageCard()
                    JunkCard().frame(width: 264)
                }
                .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 12) {
                    Text("更多工具")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.secondary)
                    VStack(spacing: 0) {
                        toolRow(.status, .analysis)
                        Rectangle().fill(Theme.stroke).frame(height: 1).padding(.horizontal, 16)
                        toolRow(.optimize, .largeFiles)
                        Rectangle().fill(Theme.stroke).frame(height: 1).padding(.horizontal, 16)
                        toolRow(.duplicates, .uninstaller)
                    }
                    .surfaceCard(padding: 0)
                }

                if !model.history.isEmpty { RecentCard() }
            }
            .padding(.horizontal, 32)
            .padding(.top, 48)
            .padding(.bottom, 32)
            .frame(maxWidth: 1440)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.never)
        .foregroundStyle(Theme.primary)
    }

    private func toolRow(_ first: Page, _ second: Page) -> some View {
        HStack(spacing: 0) {
            ModuleTile(page: first)
            Rectangle().fill(Theme.stroke).frame(width: 1).padding(.vertical, 16)
            ModuleTile(page: second)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct PermissionBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.open").font(.system(size: 16)).foregroundStyle(Theme.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text("允许访问更多文件").font(.system(size: 12, weight: .medium))
                Text("完全磁盘访问可让扫描覆盖更多应用缓存")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 12)
            Button("去开启") { Permissions.openFullDiskAccessSettings() }
                .buttonStyle(SecondaryButtonStyle())
            Button {
                withAnimation(Theme.pageTransition) { model.hidesPermissionBanner = true }
            } label: {
                Image(systemName: "xmark").font(.system(size: 11))
                    .frame(width: 24, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(GhostButtonStyle())
            .help("不再提醒")
            .accessibilityLabel("不再提醒")
        }
        .surfaceCard(radius: 12, padding: 12)
    }
}

private struct StorageCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let disk = model.disk {
                HStack {
                    Text(disk.name).font(.system(size: 14, weight: .medium))
                    Spacer()
                    Text("共 \(disk.total.byteString)")
                        .font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.tertiary)
                }
                HStack(spacing: 24) {
                    storageRing(disk)
                    VStack(alignment: .leading, spacing: 16) {
                        LegendRow(color: Theme.chart, title: String(localized: "已使用"), value: disk.used.byteString)
                        LegendRow(color: Theme.accent, title: String(localized: "可以清理的垃圾"),
                                  value: model.lastSmartScan == nil ? String(localized: "尚未扫描") : model.junkFound.byteString)
                        LegendRow(color: Theme.raised, title: String(localized: "可用空间"), value: disk.available.byteString)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                Text("读不到磁盘信息").foregroundStyle(Theme.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .surfaceCard(padding: 24)
    }

    private func storageRing(_ disk: DiskInfo) -> some View {
        let junkFraction = model.lastSmartScan == nil ? 0 : min(disk.usedFraction, Double(model.junkFound) / Double(max(disk.total, 1)))
        return ZStack {
            Circle().stroke(Theme.raised, lineWidth: 10)
            Circle()
                .trim(from: 0, to: disk.usedFraction)
                .stroke(Theme.chart, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if junkFraction > 0.002 {
                Circle()
                    .trim(from: disk.usedFraction - junkFraction, to: disk.usedFraction)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 10))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 4) {
                Text(disk.available.byteString).font(Theme.title(22)).monospacedDigit()
                Text("可用").font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
        }
        .frame(width: 132, height: 132)
        .padding(6)
        .accessibilityElement(children: .combine)
    }
}

private struct LegendRow: View {
    let color: Color
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title).font(.system(size: 12)).foregroundStyle(Theme.secondary).lineLimit(1)
            Spacer(minLength: 8)
            Text(value).font(.system(size: 12, weight: .medium).monospacedDigit()).lineLimit(1).fixedSize()
        }
    }
}

private struct JunkCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("智能清理").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.secondary)
            if let last = model.lastSmartScan {
                Text(model.junkFound.byteString)
                    .font(Theme.title(32)).monospacedDigit()
                Text("可以清理 · \(last.agoText)扫描")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                Spacer(minLength: 12)
                Button("查看并清理") { model.showSmartResults() }
                    .buttonStyle(PrimaryButtonStyle(accent: Theme.accent))
            } else {
                Text("看看能腾出多少空间")
                    .font(Theme.title(22))
                    .fixedSize(horizontal: false, vertical: true)
                Text("检查缓存、日志和安装包，清理前由你确认")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                Button {
                    model.startSmartScan()
                } label: {
                    HStack(spacing: 16) {
                        Text("开始扫描")
                        Image(systemName: "arrow.right")
                    }
                }
                .buttonStyle(PrimaryButtonStyle(accent: Theme.accent))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.accentSurface))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.stroke))
    }
}

private struct ModuleTile: View {
    let page: Page
    @Environment(AppModel.self) private var model

    private var status: String {
        switch page {
        case .largeFiles:
            model.filesPhase == .results
                ? String(localized: "找到 \(model.largeFiles.liveItems.count) 个，共 \(model.largeFiles.totalBytes.byteString)")
                : String(localized: "找出个人文件夹里最占地方的文件")
        case .duplicates:
            model.dupPhase == .results
                ? String(localized: "\(model.duplicateGroups) 组重复，多占了 \(model.duplicates.totalBytes.byteString)")
                : String(localized: "找出内容一模一样的照片、视频和文档")
        case .uninstaller:
            model.appsPhase == .results
                ? String(localized: "\(model.apps.liveItems.count) 个应用，共 \(model.apps.totalBytes.byteString)")
                : String(localized: "连同残留文件一起删掉不用的应用")
        case .status: String(localized: "实时查看 CPU、内存、电池、网络和最占资源的应用")
        case .analysis: String(localized: "看看每个文件夹各占了多少空间")
        case .optimize: String(localized: "关掉占资源的应用和后台启动项，做常用维护")
        case .overview, .smartClean, .history: ""
        }
    }

    var body: some View {
        Hoverable { hovering in
            Button {
                withAnimation(Theme.pageTransition) { model.page = page }
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: page.symbol)
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.secondary)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(page.title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.primary)
                        Text(status)
                            .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10)).foregroundStyle(Theme.tertiary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(hovering ? Theme.fill.opacity(0.035) : .clear))
                .contentShape(Rectangle())
                .animation(Theme.feedback, value: hovering)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct RecentCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("最近清理").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.secondary)
                Spacer()
                Button("全部记录") { withAnimation(Theme.pageTransition) { model.page = .history } }
                    .buttonStyle(GhostButtonStyle())
            }
            VStack(spacing: 0) {
                ForEach(model.history.prefix(3)) { entry in HistoryRow(entry: entry) }
            }
            .surfaceCard(padding: 8)
        }
    }
}
