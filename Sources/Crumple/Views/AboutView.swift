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

        // Undo puts the latest clean back from the Trash. Crumple has no text fields, so nothing else needs ⌘Z.
        CommandGroup(replacing: .undoRedo) { UndoItem(model: model) }
        // In place of the text editing items (there is no text to edit), so ⌘A selects files.
        CommandGroup(replacing: .pasteboard) { SelectionItems(model: model) }
        CommandMenu("前往") { GoItems(model: model) }
    }
}

// The items stay enabled: SwiftUI doesn't reliably refresh a menu item's enabled state, so each action
// checks for itself and says (or beeps) when there's nothing to do.
private struct UndoItem: View {
    let model: AppModel

    var body: some View {
        Button("撤销上次清理") { model.undoLastClean() }
            .keyboardShortcut("z", modifiers: .command)
    }
}

private struct SelectionItems: View {
    let model: AppModel

    var body: some View {
        Button("全选") { model.selectAllInList() }
            .keyboardShortcut("a", modifiers: .command)
        Button("把所选扔进纸篓") { model.throwSelection(shred: false) }
            .keyboardShortcut(.delete, modifiers: .command)
        Button("把所选送进碎纸机") { model.throwSelection(shred: true) }
            .keyboardShortcut(.delete, modifiers: [.command, .option])
    }
}

private struct GoItems: View {
    let model: AppModel

    var body: some View {
        ForEach(Array(Page.allCases.enumerated()), id: \.element) { index, page in
            Button(page.title) { model.go(to: page) }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
        }
        Divider()
        Button("重新扫描") { model.rescan() }
            .keyboardShortcut("r", modifiers: .command)
        Button("停止扫描") { model.cancelCurrentScan() }
            .keyboardShortcut(".", modifiers: .command)
    }
}
