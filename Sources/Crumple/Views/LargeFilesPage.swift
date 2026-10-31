import SwiftUI

struct LargeFilesPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let page = Page.largeFiles
        ZStack {
            switch model.filesPhase {
            case .landing:
                LandingView(
                    page: page, hero: .largeFiles, title: String(localized: "大文件"),
                    subtitle: String(localized: "在桌面、文稿、下载、影片、音乐和图片里，\n找出超过 \(thresholdText) 的文件，看看是谁占了地方。"),
                    chips: [("film", String(localized: "视频")), ("doc.zipper", String(localized: "压缩包")), ("externaldrive.fill", String(localized: "磁盘镜像")), ("doc.richtext", String(localized: "文档"))],
                    buttonTitle: String(localized: "扫描"), action: { model.scanLargeFiles() }
                ) {
                    Text("只会列出来，默认一个都不勾选；照片图库这类资料库会被跳过")
                }
                .transition(.phase)
            case .scanning:
                ListScanning(page: page, title: String(localized: "正在寻找大文件…"), detail: String(localized: "已检查 \(model.filesChecked.formatted()) 个文件"))
                    .transition(.phase)
            case .results:
                LargeFilesResults().transition(.phase)
            }
        }
    }

    private var thresholdText: String {
        model.largeFileThresholdMB >= 1000 ? "1 GB" : "\(model.largeFileThresholdMB) MB"
    }
}

private struct LargeFilesResults: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let page = Page.largeFiles
        let files = model.largeFiles
        let live = files.liveItems
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("大文件").font(Theme.title(30))
                        Text(live.isEmpty ? String(localized: "没有找到大文件，空间用得很节省") : String(localized: "找到 \(live.count) 个大文件，共 \(files.totalBytes.byteString)"))
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    Picker("排序", selection: $model.fileSort) {
                        ForEach(FileSort.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Button {
                        model.scanLargeFiles()
                    } label: {
                        Label("重新扫描", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(GhostButtonStyle())
                    .padding(.leading, 8)
                }
                HStack(spacing: 8) {
                    FilterChip(title: String(localized: "全部"), count: live.count, selected: model.fileFilter == nil, accent: page.accent) {
                        withAnimation(Theme.pageTransition) { model.fileFilter = nil }
                    }
                    ForEach(FileTag.allCases) { tag in
                        let count = live.filter { $0.tag == tag }.count
                        if count > 0 {
                            FilterChip(title: tag.title, symbol: tag.symbol, count: count, selected: model.fileFilter == tag, accent: page.accent) {
                                withAnimation(Theme.pageTransition) { model.fileFilter = tag }
                            }
                        }
                    }
                }
                if let banner = model.banner, banner.source == .largeFiles {
                    SummaryBanner(summary: banner).transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 44)

            ItemList(category: files)
                .padding(.horizontal, 32)
                .padding(.vertical, 16)

            ActionBar(label: model.isCleaning ? String(localized: "待清理") : String(localized: "已选择"), bytes: files.selectedBytes,
                      detail: String(localized: "\(files.selectedItems.count) 个文件 · \(model.cleaningMode(for: .largeFiles).title)")) {
                Button {
                    model.requestLargeFileClean()
                } label: {
                    Label(model.isCleaning ? String(localized: "揉纸团中 \(model.cleanDone)/\(model.cleanTotal)") : String(localized: "清理选中"), systemImage: "arrow.up.trash")
                        .monospacedDigit()
                }
                .buttonStyle(PrimaryButtonStyle(accent: page.accent, large: true))
                .disabled(model.isCleaning || files.selectedItems.isEmpty)
                .opacity(files.selectedItems.isEmpty && !model.isCleaning ? 0.5 : 1)
            }
        }
    }
}
