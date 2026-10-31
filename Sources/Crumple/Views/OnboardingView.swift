import SwiftUI

/// First-run sheet explaining the permissions Crumple asks for, and why.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 16) {
                AppGlyph().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text("开始之前").font(Theme.title(26))
                    Text("Crumple 需要看得到文件，才能帮你找出垃圾。一切都只在这台 Mac 上进行，不会上传任何东西。")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            PermissionRow(
                symbol: "lock.open.fill", color: Page.smartClean.accent, title: String(localized: "完全磁盘访问（推荐）"),
                detail: String(localized: "能看到废纸篓、邮件下载和更多应用的缓存。在系统设置里打开 Crumple 的开关，回来后会自动识别。"),
                status: model.hasFullDiskAccess ? .granted : .missing
            ) {
                Button("打开系统设置") { Permissions.openFullDiskAccessSettings() }
                    .buttonStyle(SecondaryButtonStyle())
            }
            PermissionRow(
                symbol: "folder.fill", color: Page.largeFiles.accent, title: String(localized: "桌面、文稿和下载"),
                detail: String(localized: "第一次扫描这几个文件夹时，macOS 会弹窗询问，选“允许”就好。"),
                status: .whenAsked
            ) { EmptyView() }
            PermissionRow(
                symbol: "gearshape.2.fill", color: Page.uninstaller.accent, title: String(localized: "控制“访达”"),
                detail: String(localized: "清倒废纸篓、卸载需要管理员权限的应用时会用到，到时会弹窗询问。"),
                status: .whenAsked
            ) { EmptyView() }

            HStack {
                Text("以后可以在“设置 › 权限”里再看。").font(.system(size: 12)).foregroundStyle(Theme.tertiary)
                Spacer()
                Button("开始使用") { model.finishOnboarding() }
                    .buttonStyle(PrimaryButtonStyle(accent: Page.smartClean.accent, large: true))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(28)
        .frame(width: 560)
        .background(Theme.base)
        .preferredColorScheme(model.appearance.colorScheme)
    }
}

enum PermissionStatus { case granted, missing, whenAsked }

struct PermissionRow<Action: View>: View {
    let symbol: String
    let color: Color
    let title: String
    let detail: String
    let status: PermissionStatus
    @ViewBuilder let action: Action

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            SymbolTile(symbol: symbol, color: color, size: 34)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title).font(.system(size: 14, weight: .semibold))
                    switch status {
                    case .granted: Badge(text: String(localized: "已开启"), color: Page.smartClean.accent)
                    case .missing: Badge(text: String(localized: "未开启"), color: Page.largeFiles.accent)
                    case .whenAsked: Badge(text: String(localized: "用到时询问"), color: Theme.secondary)
                    }
                }
                Text(detail).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if status == .missing { action }
        }
        .surfaceCard(radius: 14, padding: 14)
    }
}
