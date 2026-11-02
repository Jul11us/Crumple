import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                AppGlyph().frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Crumple").font(.system(size: 18, weight: .semibold, design: .rounded))
                    Text(Paths.isDemo ? String(localized: "演示模式 · 使用假文件") : String(localized: "把垃圾揉成纸团"))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondary)
                }
            }
            .padding(.top, 48)
            .padding(.horizontal, 20)
            .padding(.bottom, 28)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Page.allCases) { page in
                    if let section = page.section {
                        Text(section)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.tertiary)
                            .padding(.leading, 12)
                            .padding(.top, 20)
                            .padding(.bottom, 4)
                    }
                    navItem(page)
                }
            }
            .padding(.horizontal, 12)

            Spacer(minLength: 24)

            if let disk = model.disk {
                MiniDiskCard(disk: disk)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
            }

            Rectangle().fill(Theme.stroke).frame(height: 1).padding(.horizontal, 20)
            VStack(spacing: 0) {
                SettingsLink {
                    HStack(spacing: 12) {
                        Image(systemName: "gearshape").frame(width: 20)
                        Text("设置")
                        Spacer()
                    }
                    .frame(height: 32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(GhostButtonStyle())
                Button {
                    model.requestEmptyTrash()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "trash").frame(width: 20)
                        Text(trashTitle).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .frame(height: 32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(GhostButtonStyle())
                .disabled(model.isCleaning || model.trashSize == 0)
                .help("清倒废纸篓，真正释放空间")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .foregroundStyle(Theme.primary)
    }

    private var trashTitle: String {
        switch model.trashSize {
        case 0?: String(localized: "废纸篓是空的")
        case let size?: String(localized: "清倒 \(size.byteString)")
        case nil: String(localized: "清倒废纸篓")
        }
    }

    private func navItem(_ page: Page) -> some View {
        let selected = model.page == page
        return Hoverable { hovering in
            Button {
                withAnimation(Theme.pageTransition) { model.page = page }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: page.symbol)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(selected ? Theme.accent : Theme.secondary)
                        .frame(width: 20)
                    Text(page.title)
                        .font(.system(size: 13, weight: selected ? .medium : .regular))
                    Spacer(minLength: 4)
                    if let badge = badge(for: page) {
                        Text(badge)
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(Theme.tertiary)
                    }
                }
                .foregroundStyle(selected ? Theme.primary : Theme.secondary)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(RoundedRectangle(cornerRadius: 8)
                    .fill(selected ? Theme.card : hovering ? Theme.fill.opacity(0.04) : .clear))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? Theme.stroke : .clear))
                .overlay(alignment: .leading) {
                    if selected {
                        RoundedRectangle(cornerRadius: 1).fill(Theme.accent).frame(width: 2, height: 16)
                    }
                }
                .contentShape(Rectangle())
                .animation(Theme.feedback, value: hovering)
            }
            .buttonStyle(.plain)
            .disabled(model.isCleaning && !selected)
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
    }

    private func badge(for page: Page) -> String? {
        switch page {
        case .smartClean: model.lastSmartScan != nil ? model.junkFound.byteString : nil
        case .largeFiles: model.filesPhase == .results ? "\(model.largeFiles.liveItems.count)" : nil
        case .uninstaller: model.appsPhase == .results ? "\(model.apps.liveItems.count)" : nil
        case .duplicates: model.dupPhase == .results ? "\(model.duplicates.liveItems.count)" : nil
        case .overview, .status, .analysis, .optimize, .history: nil
        }
    }
}

struct Keycap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(Theme.tertiary)
            .padding(.horizontal, 4)
            .frame(height: 20)
            .background(RoundedRectangle(cornerRadius: 4).fill(Theme.base))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.stroke))
            .accessibilityHidden(true)
    }
}

private struct MiniDiskCard: View {
    let disk: DiskInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(disk.name).font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(Int(disk.usedFraction * 100))%")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Theme.secondary)
            }
            ProgressBar(value: disk.usedFraction, accent: disk.usedFraction > 0.9 ? .red : Theme.chart)
            Text("可用 \(disk.available.byteString) · 共 \(disk.total.byteString)")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
        }
    }
}
