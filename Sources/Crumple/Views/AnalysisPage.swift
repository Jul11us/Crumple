import SwiftUI
import Charts
import AppKit

/// Space analysis: what is taking up room in a folder, drilling down folder by folder.
struct AnalysisPage: View {
    @Environment(AppModel.self) private var model

    private static let palette: [Color] = CategoryKind.junk.map(\.chartColor) + [Theme.fill.opacity(0.12)]

    var body: some View {
        let analyzer = model.analyzer
        let top = Array(analyzer.entries.filter { ($0.size ?? 0) > 0 }.prefix(7))
        let largest = analyzer.entries.compactMap(\.size).max() ?? 0
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("空间分析").font(Theme.title(30))
                    Text("看看每个文件夹各占了多少，点进去一层层找。").font(.system(size: 13)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Picker("位置", selection: Binding(get: { analyzer.base }, set: { analyzer.open(base: $0) })) {
                    ForEach(SpaceAnalyzer.Base.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 210)
                Button {
                    analyzer.rescan()
                } label: {
                    Label("重新计算", systemImage: "arrow.clockwise")
                }
                .buttonStyle(GhostButtonStyle())
                .padding(.leading, 6)
            }

            // Breadcrumb
            HStack(spacing: 4) {
                ForEach(Array(analyzer.trail.enumerated()), id: \.offset) { index, url in
                    if index > 0 { Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.tertiary) }
                    Button(index == 0 ? analyzer.base.title : FileManager.default.displayName(atPath: url.path)) {
                        withAnimation(Theme.pageTransition) { analyzer.goBack(to: index) }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: index == analyzer.trail.count - 1 ? .semibold : .regular))
                    .foregroundStyle(index == analyzer.trail.count - 1 ? Theme.primary : Theme.secondary)
                }
            }

            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 16) {
                    ZStack {
                        if top.isEmpty {
                            Circle().stroke(Theme.fill.opacity(0.07), lineWidth: 34).padding(17)
                        } else {
                            Chart(Array(top.enumerated()), id: \.element.id) { index, entry in
                                SectorMark(angle: .value(String(localized: "大小"), Double(entry.size ?? 0)), innerRadius: .ratio(0.64), angularInset: 1.5)
                                    .foregroundStyle(Self.palette[index % Self.palette.count])
                                    .cornerRadius(3)
                            }
                            .chartLegend(.hidden)
                        }
                        VStack(spacing: 2) {
                            Text(analyzer.total.byteString).font(Theme.title(24)).contentTransition(.numericText())
                            Text(analyzer.pending > 0 ? String(localized: "还在算 \(analyzer.pending) 项…") : String(localized: "共 \(analyzer.entries.count) 项"))
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.secondary)
                        }
                    }
                    .frame(width: 220, height: 220)

                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(Array(top.prefix(5).enumerated()), id: \.element.id) { index, entry in
                            HStack(spacing: 8) {
                                Circle().fill(Self.palette[index]).frame(width: 8, height: 8)
                                Text(entry.name).font(.system(size: 12)).lineLimit(1)
                                Spacer(minLength: 6)
                                Text(percent(entry.size, of: analyzer.total))
                                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                                    .foregroundStyle(Theme.secondary)
                            }
                        }
                    }
                }
                .frame(width: 252)
                .surfaceCard(radius: 16, padding: 16)

                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(analyzer.entries) { entry in
                            EntryRow(entry: entry, largest: largest,
                                     color: top.firstIndex(of: entry).map { Self.palette[$0] })
                        }
                    }
                    .padding(6)
                }
                .id(analyzer.current)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .surfaceCard(radius: 16, padding: 4)
            }
        }
        .padding(.leading, 32)
        // The right-hand column stays clear for the basket, which sits in the corner of every page.
        .padding(.trailing, BasketGeometry.reservedTrailing)
        .padding(.top, 48)
        .padding(.bottom, 32)
        .onAppear {
            if analyzer.trail.isEmpty { analyzer.open(base: .home) }
        }
    }

    private func percent(_ size: Int64?, of total: Int64) -> String {
        guard let size, total > 0 else { return "--" }
        return String(format: "%.0f%%", Double(size) / Double(total) * 100)
    }
}

private struct EntryRow: View {
    let entry: SpaceAnalyzer.Entry
    let largest: Int64
    let color: Color?
    @Environment(AppModel.self) private var model

    var body: some View {
        Hoverable { hovering in
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.fill.opacity(0.06))
                            Capsule()
                                .fill(color ?? Theme.fill.opacity(0.35))
                                .frame(width: geo.size.width * fraction)
                        }
                    }
                    .frame(height: 5)
                }
                Spacer(minLength: 12)
                Group {
                    if entry.isProtected {
                        Text("受保护").foregroundStyle(Theme.tertiary)
                    } else if let size = entry.size {
                        Text(size.byteString)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .frame(width: 84, alignment: .trailing)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.tertiary)
                    .opacity(entry.isFolder && !entry.isProtected ? 1 : 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.fill.opacity(hovering ? 0.06 : 0)))
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(Theme.pageTransition) { model.analyzer.open(entry) } }
            .contextMenu {
                Button("在访达中显示") { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
                if Cleaner.isSafeTarget(entry.url) {
                    Button("移到废纸篓…") { model.requestTrash(entry) }
                }
            }
            .help(entry.isProtected ? String(localized: "macOS 保护的文件夹，打开需要单独授权") : Paths.display(entry.url))
        }
    }

    private var fraction: CGFloat {
        guard let size = entry.size, largest > 0 else { return 0 }
        return CGFloat(Double(size) / Double(largest))
    }
}
