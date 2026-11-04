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

                if !model.history.isEmpty { RecentCard() }
            }
            .padding(.leading, 32)
            // The right-hand column stays clear for the basket, which sits in the corner of every page.
            .padding(.trailing, BasketGeometry.reservedTrailing)
            .padding(.top, 48)
            .padding(.bottom, 32)
            .frame(maxWidth: 1440)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.never)
        .foregroundStyle(Theme.primary)
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
        VStack(alignment: .leading, spacing: 20) {
            if let disk = model.disk {
                Text(disk.name).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(disk.available.byteString).font(Theme.title(40))
                    Text("可用 · 共 \(disk.total.byteString)")
                        .font(.system(size: 13)).foregroundStyle(Theme.secondary)
                }
                DiskRuler(disk: disk, junk: model.lastSmartScan == nil ? 0 : model.junkFound)
                VStack(spacing: 10) {
                    LeaderRow(title: String(localized: "已使用"), value: disk.used.byteString)
                    LeaderRow(title: String(localized: "可以清理的垃圾"),
                              value: model.lastSmartScan == nil ? String(localized: "尚未扫描") : model.junkFound.byteString)
                    LeaderRow(title: String(localized: "可用空间"), value: disk.available.byteString)
                }
            } else {
                Text("读不到磁盘信息").foregroundStyle(Theme.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .surfaceCard(padding: 24)
    }
}

/// The disk as a ruler: used space in ink, the junk found hatched at its end, tick marks every tenth.
private struct DiskRuler: View {
    let disk: DiskInfo
    let junk: Int64

    var body: some View {
        Canvas { context, size in
            let barHeight: CGFloat = 10
            let bar = CGRect(x: 0, y: 0, width: size.width, height: barHeight)
            context.fill(Path(bar), with: .color(Theme.raised))
            let used = size.width * disk.usedFraction
            context.fill(Path(CGRect(x: 0, y: 0, width: used, height: barHeight)), with: .color(Theme.primary))
            let junkWidth = min(used, size.width * Double(junk) / Double(max(disk.total, 1)))
            if junkWidth > 1 {
                let rect = CGRect(x: used - junkWidth, y: 0, width: junkWidth, height: barHeight)
                context.fill(Path(rect), with: .color(Theme.base))
                var hatch = Path()
                for x in stride(from: rect.minX - barHeight, through: rect.maxX, by: 4) {
                    hatch.move(to: CGPoint(x: x, y: barHeight))
                    hatch.addLine(to: CGPoint(x: x + barHeight, y: 0))
                }
                var clipped = context
                clipped.clip(to: Path(rect))
                clipped.stroke(hatch, with: .color(Theme.primary), lineWidth: 1)
            }
            var ticks = Path()
            for i in 0...10 {
                let x = min(size.width - 0.5, max(0.5, size.width * CGFloat(i) / 10))
                ticks.move(to: CGPoint(x: x, y: barHeight + 3))
                ticks.addLine(to: CGPoint(x: x, y: barHeight + (i % 5 == 0 ? 9 : 6)))
            }
            context.stroke(ticks, with: .color(Theme.tertiary), lineWidth: 1)
        }
        .frame(height: 20)
        .accessibilityElement()
        .accessibilityLabel("已使用 \(Int(disk.usedFraction * 100))%")
    }
}

/// "Title ........ value", like a line on a receipt.
struct LeaderRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 6) {
            Text(title).font(.system(size: 13)).foregroundStyle(Theme.secondary).lineLimit(1)
            DottedLeader()
            Text(value).font(Theme.figures(13)).lineLimit(1).fixedSize()
        }
        .accessibilityElement(children: .combine)
    }
}

struct DottedLeader: View {
    var body: some View {
        Canvas { context, size in
            var line = Path()
            line.move(to: CGPoint(x: 0, y: size.height - 1))
            line.addLine(to: CGPoint(x: size.width, y: size.height - 1))
            context.stroke(line, with: .color(Theme.tertiary.opacity(0.7)), style: StrokeStyle(lineWidth: 1, dash: [1, 3]))
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}

private struct JunkCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("智能清理").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.secondary)
            if let last = model.lastSmartScan {
                Text(model.junkFound.byteString)
                    .font(Theme.title(32))
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
                Button("开始扫描") { model.startSmartScan() }
                .buttonStyle(PrimaryButtonStyle(accent: Theme.accent))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.accentSurface))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.stroke))
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
