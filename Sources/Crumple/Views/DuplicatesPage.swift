import SwiftUI

struct DuplicatesPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let page = Page.duplicates
        ZStack {
            switch model.dupPhase {
            case .landing:
                LandingView(
                    page: page, hero: .duplicates, title: String(localized: "重复文件"),
                    subtitle: String(localized: "在桌面、文稿、下载、影片、音乐和图片里，\n找出内容一模一样的文件，每组只留一份。"),
                    chips: [("photo", String(localized: "照片")), ("film", String(localized: "视频")), ("doc.richtext", String(localized: "文档")), ("doc.zipper", String(localized: "压缩包"))],
                    buttonTitle: String(localized: "扫描"), action: { model.scanDuplicates() }
                ) {
                    Text("逐字节比对，名字不同也能认出来；只有内容完全相同才算重复")
                }
                .transition(.phase)
            case .scanning:
                ListScanning(page: page, title: String(localized: "正在比对文件…"), detail: model.dupProgress)
                    .transition(.phase)
            case .results:
                DuplicatesResults().transition(.phase)
            }
        }
    }
}

private struct DuplicatesResults: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let page = Page.duplicates
        let files = model.duplicates
        let live = files.liveItems
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("重复文件").font(Theme.title(30))
                        Text(live.isEmpty
                             ? (model.banner?.source == .duplicates ? String(localized: "副本都扔掉了，每份文件只留下一份") : String(localized: "没有找到重复的文件，每份都是独一无二的"))
                             : String(localized: "\(model.duplicateGroups) 组文件有重复，多出来的副本占了 \(files.totalBytes.byteString)"))
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    Button {
                        model.scanDuplicates()
                    } label: {
                        Label("重新扫描", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(GhostButtonStyle())
                }
                if !live.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle").foregroundStyle(page.accent)
                        Text("每组都会留下一份（见每行的“和…一样”），列出来的是多出来的副本。右键可以改为保留另一份。")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.secondary)
                    }
                }
                if let banner = model.banner, banner.source == .duplicates {
                    SummaryBanner(summary: banner).transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 44)

            ItemList(category: files)
                .padding(.horizontal, 32)
                .padding(.vertical, 16)

            ActionBar(label: model.isCleaning ? String(localized: "待清理") : String(localized: "已选择"), bytes: files.selectedBytes,
                      detail: String(localized: "\(files.selectedItems.count) 个副本 · \(model.cleaningMode(for: .duplicates).title)")) {
                Button {
                    model.requestDuplicateClean()
                } label: {
                    Label(model.isCleaning ? String(localized: "揉纸团中 \(model.cleanDone)/\(model.cleanTotal)") : String(localized: "清理副本"), systemImage: "arrow.up.trash")
                        .monospacedDigit()
                }
                .buttonStyle(PrimaryButtonStyle(accent: page.accent, large: true))
                .disabled(model.isCleaning || files.selectedItems.isEmpty)
                .opacity(files.selectedItems.isEmpty && !model.isCleaning ? 0.5 : 1)
            }
        }
    }
}
