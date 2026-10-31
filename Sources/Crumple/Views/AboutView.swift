import SwiftUI

/// The About window: the icon, the version, and the update check.
struct AboutView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            Canvas { context, size in IconArt.draw(context, side: size.width) }
                .frame(width: 112, height: 112)
                .accessibilityHidden(true)
            Text("Crumple").font(Theme.title(28)).padding(.top, 10)
            Text("版本 \(UpdateCheck.currentVersion)（\(build)）")
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(Theme.secondary)
                .padding(.top, 2)
            Text("把不要的东西揉成纸团，扔掉。")
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)

            UpdateStatus()
                .padding(.top, 18)

            Text(Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? "")
                .font(.system(size: 11))
                .foregroundStyle(Theme.tertiary)
                .padding(.top, 18)
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 28)
        .frame(width: 340)
        .background(Theme.base)
        .preferredColorScheme(model.appearance.colorScheme)
    }

    private var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1" }
}

/// The "检查更新" button and what it found. Shared by the About window and Settings.
struct UpdateStatus: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 8) {
            switch model.update {
            case nil:
                Button("检查更新") { model.checkForUpdates() }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(UpdateCheck.repository == nil)
                if UpdateCheck.repository == nil {
                    note(String(localized: "这个版本没有配置更新地址"))
                }
            case .some(.checking):
                ProgressView().controlSize(.small)
                note(String(localized: "正在检查…"))
            case .some(.done(let outcome)):
                switch outcome {
                case .upToDate:
                    Label("已经是最新版本", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Page.smartClean.accent)
                case .available(let release):
                    Text("有新版本 \(release.version)").font(.system(size: 13, weight: .semibold))
                    Button("去下载") { NSWorkspace.shared.open(release.page) }
                        .buttonStyle(PrimaryButtonStyle(accent: Page.smartClean.accent))
                case .failed(let reason):
                    note(reason)
                    Button("再试一次") { model.checkForUpdates() }.buttonStyle(SecondaryButtonStyle())
                case .notConfigured:
                    note(String(localized: "这个版本没有配置更新地址"))
                }
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(Theme.secondary)
    }
}

/// Puts “关于 Crumple” and “检查更新…” in the app menu.
struct AppMenuCommands: Commands {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("关于 Crumple") { openWindow(id: "about") }
            Button("检查更新…") {
                openWindow(id: "about")
                model.checkForUpdates()
            }
            .disabled(UpdateCheck.repository == nil)
        }
    }
}
