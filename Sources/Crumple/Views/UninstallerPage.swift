import SwiftUI
import AppKit

struct UninstallerPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let page = Page.uninstaller
        ZStack {
            switch model.appsPhase {
            case .landing:
                LandingView(
                    page: page, hero: .apps, title: String(localized: "应用卸载"),
                    subtitle: String(localized: "把不用的应用，连同它在资源库里留下的缓存、\n偏好设置和支持文件，一起揉成纸团扔掉。"),
                    chips: [("square.grid.2x2", String(localized: "第三方应用")), ("folder", String(localized: "残留文件")), ("clock", String(localized: "很久没用"))],
                    buttonTitle: String(localized: "扫描"), action: { model.scanApps() }
                ) {
                    Text("系统自带的应用不会出现在列表里；卸载的应用总是先放进废纸篓")
                }
                .transition(.phase)
            case .scanning:
                ListScanning(page: page, title: String(localized: "正在读取应用…"),
                             detail: model.appsProgress.total > 0 ? "\(model.appsProgress.done) / \(model.appsProgress.total)" : String(localized: "正在查找应用"))
                    .transition(.phase)
            case .results:
                UninstallerResults().transition(.phase)
            }
        }
    }
}

private struct UninstallerResults: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let page = Page.uninstaller
        let apps = model.apps
        let live = apps.liveItems
        let focused = live.first { $0.id == model.focusedAppID } ?? model.visibleItems(in: apps).first
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("应用卸载").font(Theme.title(30))
                        Text("\(live.count) 个应用，共 \(apps.totalBytes.byteString)（含残留文件）")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    Button {
                        model.scanApps()
                    } label: {
                        Label("重新扫描", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(GhostButtonStyle())
                }
                HStack(spacing: 8) {
                    ForEach(AppFilter.allCases) { filter in
                        let count = AppModel.filter(live, by: filter).count
                        FilterChip(title: filter.title, count: count, selected: model.appFilter == filter, accent: page.accent) {
                            withAnimation(Theme.pageTransition) { model.appFilter = filter }
                        }
                    }
                }
                if let banner = model.banner, banner.source == .uninstaller {
                    SummaryBanner(summary: banner).transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 44)

            HStack(alignment: .top, spacing: 16) {
                ItemList(category: apps, style: .app)
                AppDetailPanel(app: focused)
                    .frame(width: 310)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 16)

            ActionBar(label: model.isCleaning ? String(localized: "待卸载") : String(localized: "已选择"), bytes: apps.selectedBytes,
                      detail: String(localized: "\(apps.selectedItems.count) 个应用 · 移到废纸篓")) {
                Button {
                    model.requestUninstall()
                } label: {
                    Label(model.isCleaning ? String(localized: "揉纸团中 \(model.cleanDone)/\(model.cleanTotal)") : String(localized: "卸载选中"), systemImage: "trash")
                        .monospacedDigit()
                }
                .buttonStyle(PrimaryButtonStyle(accent: page.accent, large: true))
                .disabled(model.isCleaning || apps.selectedItems.isEmpty)
                .opacity(apps.selectedItems.isEmpty && !model.isCleaning ? 0.5 : 1)
            }
        }
    }

}

private struct AppDetailPanel: View {
    let app: CleanItem?
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let app {
                HStack(spacing: 16) {
                    Image(nsImage: model.icons.icon(for: app))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.name).font(.system(size: 18, weight: .semibold)).lineLimit(1)
                        Text(app.version.map { String(localized: "版本 \($0)") } ?? String(localized: "未知版本"))
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.secondary)
                        Text(app.ownerBundleID ?? "")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                HStack(spacing: 10) {
                    miniStat(String(localized: "总大小"), app.size.byteString)
                    miniStat(String(localized: "上次使用"), app.lastUsed?.agoText ?? String(localized: "没有记录"))
                }
                Text("会一起扔掉的内容")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                    .padding(.top, 2)
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(app.components, id: \.url) { component in
                            HStack(spacing: 10) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: component.url.path))
                                    .resizable()
                                    .frame(width: 22, height: 22)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(component.name).font(.system(size: 12, weight: .medium))
                                    Text(Paths.display(component.url))
                                        .font(.system(size: 11))
                                        .foregroundStyle(Theme.tertiary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer(minLength: 6)
                                Text(component.size.byteString)
                                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                                    .foregroundStyle(Theme.secondary)
                            }
                            .padding(.vertical, 5)
                            .padding(.horizontal, 8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.fill.opacity(0.04)))
                        }
                    }
                }
                .scrollIndicators(.never)
                Spacer(minLength: 0)
                if let reason = model.blockReason(for: app) {
                    Label(reason, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Page.largeFiles.accent)
                }
                Button {
                    model.requestUninstall(only: app.id)
                } label: {
                    Label("卸载 \(app.name)", systemImage: "trash").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle(accent: Page.uninstaller.accent))
                .disabled(model.isCleaning)
            } else {
                Spacer()
                Text("选择一个应用查看详情")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .surfaceCard(radius: 16, padding: 16)
    }

    private func miniStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.tertiary)
            Text(value).font(.system(size: 15, weight: .semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.fill.opacity(0.05)))
    }
}
