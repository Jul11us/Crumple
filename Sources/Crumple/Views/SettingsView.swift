import SwiftUI

final class FlagModel: ObservableObject {
    @Published var isOn = false
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @StateObject private var askClear = FlagModel()

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Picker("清理方式", selection: $model.mode) {
                    ForEach(CleanMode.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text("清理")
            } footer: {
                Text("“移到废纸篓”可以恢复，清倒废纸篓后才真正释放空间；“直接删除”会立刻释放空间，无法恢复。卸载应用总是先移到废纸篓。")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section {
                LabeledContent("完全磁盘访问") {
                    if model.hasFullDiskAccess {
                        Label("已开启", systemImage: "checkmark.circle.fill").foregroundStyle(Page.smartClean.accent)
                    } else {
                        Button("打开系统设置…") { Permissions.openFullDiskAccessSettings() }
                    }
                }
                LabeledContent("控制“访达”") {
                    Button("打开系统设置…") { Permissions.openAutomationSettings() }
                }
            } header: {
                Text("权限")
            } footer: {
                Text("完全磁盘访问能让 Crumple 看到废纸篓和更多应用的缓存；控制“访达”用来清倒废纸篓和卸载需要管理员权限的应用。")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section("外观") {
                Picker("外观", selection: $model.appearance) {
                    ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
                }
                Toggle("启动时播放开场动画", isOn: $model.playsLaunchAnimation)
            }

            Section {
                Picker("语言", selection: $model.language) {
                    ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
                }
                .disabled(model.isCleaning)
                if model.languageNeedsRestart {
                    Button("立即重新打开") { model.relaunch() }
                        .disabled(model.isCleaning)
                }
            } footer: {
                Text("重新打开 Crumple 后生效")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("在菜单栏显示 Crumple", isOn: $model.showsMenuBarExtra)
                Toggle("磁盘快满时提醒我", isOn: $model.remindsLowDisk)
                Toggle("一周没清理时提醒我", isOn: $model.remindsWeekly)
                if model.notificationsDenied && (model.remindsLowDisk || model.remindsWeekly) {
                    LabeledContent("通知被关掉了") {
                        Button("打开系统设置…") { Permissions.openNotificationSettings() }
                    }
                }
            } header: {
                Text("菜单栏和提醒")
            } footer: {
                Text("菜单栏里能随时看 CPU、内存和磁盘。开着它时，关掉主窗口 Crumple 也会继续在菜单栏运行，提醒才能按时送到。")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section("扫描") {
                Picker("大文件下限", selection: $model.largeFileThresholdMB) {
                    ForEach([50, 100, 250, 500, 1000], id: \.self) { mb in
                        Text(mb >= 1000 ? "1 GB" : "\(mb) MB").tag(mb)
                    }
                }
                Picker("“旧下载”是指多久没动过", selection: $model.oldDownloadDays) {
                    ForEach([30, 60, 90, 180, 365], id: \.self) { days in
                        Text(days == 365 ? String(localized: "1 年") : String(localized: "\(days) 天")).tag(days)
                    }
                }
            }

            Section {
                if model.ignoredPaths.isEmpty {
                    Text("还没有忽略任何东西。在列表里右键一项，选“忽略”。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.ignoredPaths, id: \.self) { path in
                        HStack {
                            Image(systemName: "eye.slash").foregroundStyle(.secondary)
                            Text(Paths.display(URL(fileURLWithPath: path)))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                model.unignore(path)
                            } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("恢复，以后照常列出")
                            .accessibilityLabel("恢复 \(Paths.display(URL(fileURLWithPath: path)))")
                        }
                    }
                }
                Button("添加文件夹…") { chooseIgnoredFolder() }
            } header: {
                Text("忽略列表")
            } footer: {
                Text("这里的文件和文件夹（包括里面的一切）不会出现在任何扫描结果里。")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section("关于") {
                LabeledContent("版本", value: String(localized: "\(UpdateCheck.currentVersion)（\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1")）"))
                HStack {
                    Spacer()
                    UpdateStatus()
                    Spacer()
                }
            }

            Section("记录") {
                LabeledContent("累计扔掉", value: model.historyTotal.byteString)
                LabeledContent("清理次数", value: String(localized: "\(model.history.count) 次"))
                Button("清空清理记录…", role: .destructive) { askClear.isOn = true }
                    .disabled(model.history.isEmpty)
            }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 680)
        .onAppear { model.refreshNotificationStatus() }
        .confirmationDialog("清空清理记录？", isPresented: $askClear.isOn) {
            Button("清空", role: .destructive) { model.clearHistoryNow() }
        } message: {
            Text("只会删除记录，不影响任何文件。")
        }
        .alert("没能重新打开", isPresented: Binding(
            get: { model.relaunchError != nil },
            set: { if !$0 { model.relaunchError = nil } }
        )) {
            Button("好") {}
        } message: {
            Text(model.relaunchError ?? "")
        }
    }

    private func chooseIgnoredFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.directoryURL = Paths.home
        panel.prompt = String(localized: "忽略")
        panel.message = String(localized: "选中的文件和文件夹不会再出现在扫描结果里")
        if panel.runModal() == .OK {
            panel.urls.forEach(model.addIgnored)
        }
    }
}
