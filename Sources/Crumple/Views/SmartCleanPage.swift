import SwiftUI
import Charts

/// Smart clean walks through: landing → scanning → results → (review) → cleaning → done.
struct SmartCleanPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            switch model.smartPhase {
            case .landing: SmartLanding().transition(.phase)
            case .scanning: SmartScanning().transition(.phase)
            case .results: SmartResults().transition(.phase)
            case .review: SmartReview().transition(.phase)
            case .cleaning: SmartCleaning().transition(.phase)
            case .done: SmartDone().transition(.phase)
            }
        }
    }
}

extension AnyTransition {
    static var phase: AnyTransition {
        .asymmetric(insertion: .opacity.combined(with: .offset(y: 8)), removal: .opacity)
    }
}

private let accent = Page.smartClean.accent

// MARK: - Landing

private struct SmartLanding: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        LandingView(
            page: .smartClean, hero: .smartClean, title: String(localized: "智能清理"),
            subtitle: String(localized: "找出缓存、日志、开发垃圾和多余的安装包，\n把它们揉成纸团，扔进纸篓。"),
            chips: [("square.stack.3d.up", String(localized: "应用缓存")), ("doc.text", String(localized: "日志")), ("hammer", "Xcode"),
                    ("shippingbox", String(localized: "开发缓存")), ("arrow.down.app", String(localized: "安装包"))],
            buttonTitle: String(localized: "扫描"), action: { model.startSmartScan() }
        ) {
            if let last = model.lastSmartScan {
                Text("上次扫描：\(last.agoText)，发现 \(model.junkFound.byteString)")
            } else {
                Text("只会读取，不会动任何文件，放心扫描")
            }
        }
    }
}

// MARK: - Scanning

private struct SmartScanning: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let current = CategoryKind.junk.first { !model.revealed.contains($0) }
        VStack(spacing: 0) {
            Spacer(minLength: 30)
            ScanRing(progress: model.scanProgress, accent: accent) {
                VStack(spacing: 4) {
                    Text(model.revealedBytes.byteString)
                        .font(Theme.title(34))
                        .contentTransition(.numericText())
                    Text("已发现").font(.system(size: 13)).foregroundStyle(Theme.secondary)
                }
            }
            .frame(width: 250, height: 250)
            Text("正在扫描…").font(Theme.title(24)).padding(.top, 34)
            Text(current.map { String(localized: "正在查看「\($0.title)」") } ?? String(localized: "马上就好"))
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondary)
                .padding(.top, 6)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(232), spacing: 12), count: 3), spacing: 12) {
                ForEach(CategoryKind.junk) { kind in
                    ScanChip(kind: kind, done: model.revealed.contains(kind), bytes: model.category(kind).totalBytes)
                }
            }
            .padding(.top, 30)
            Spacer(minLength: 24)
            Button("停止扫描") { model.cancelSmartScan() }
                .buttonStyle(SecondaryButtonStyle())
            Spacer().frame(height: 40)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ScanChip: View {
    let kind: CategoryKind
    let done: Bool
    let bytes: Int64

    var body: some View {
        HStack(spacing: 10) {
            CategoryIcon(kind: kind, size: 26)
            Text(kind.title).font(.system(size: 13, weight: .medium)).lineLimit(1).fixedSize()
            Spacer(minLength: 4)
            if done {
                Text(bytes.byteString)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.secondary)
                Image(systemName: "checkmark.circle.fill").foregroundStyle(accent)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .surfaceCard(radius: 12, padding: 10)
        .opacity(done ? 1 : 0.7)
    }
}

// MARK: - Results

private struct SmartResults: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let selected = model.junkSelectedBytes
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("扫描完成").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    CountUpText(bytes: model.junkFound, start: model.resultsShownAt, font: Theme.title(58))
                    Text("可以清理").font(.system(size: 20, weight: .medium)).foregroundStyle(Theme.secondary)
                }
                Text("已为你勾选 \(selected.byteString) 可以放心清理的内容。正在运行的应用和你自己的文件默认不动。")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // An itemised list, one line per kind of junk, with the selected total at the bottom.
            VStack(spacing: 0) {
                ForEach(model.junk) { ResultLine(category: $0) }
                DashedRule().padding(.vertical, 10)
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text("合计").font(.system(size: 14, weight: .semibold))
                    DottedLeader()
                    Text(selected.byteString).font(Theme.figures(16, weight: .semibold))
                }
                .padding(.horizontal, 12)
            }
            .surfaceCard(radius: 16, padding: 16)
            .padding(.top, 28)

            Spacer(minLength: 16)

            HStack(spacing: 12) {
                Button {
                    model.startSmartScan()
                } label: {
                    Label("重新扫描", systemImage: "arrow.clockwise")
                }
                .buttonStyle(GhostButtonStyle())
                Spacer()
                Button("查看详情") { model.openReview() }
                    .buttonStyle(SecondaryButtonStyle(large: true))
                Button {
                    model.requestSmartClean()
                } label: {
                    Label("清理 \(selected.byteString)", systemImage: "arrow.up.trash")
                }
                .buttonStyle(PrimaryButtonStyle(accent: accent, large: true))
                .disabled(model.junkSelectedCount == 0)
                .opacity(model.junkSelectedCount == 0 ? 0.5 : 1)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(.horizontal, 40)
        .padding(.top, 48)
        .padding(.bottom, 34)
    }
}

private struct ResultLine: View {
    let category: CleanCategory
    @Environment(AppModel.self) private var model

    var body: some View {
        let kind = category.kind
        let empty = category.liveItems.isEmpty
        Hoverable { hovering in
            HStack(alignment: .center, spacing: 12) {
                CheckBox(state: category.selectionState, tint: kind.color, label: kind.title) { category.toggleAll() }
                    .disabled(empty)
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(kind.title).font(.system(size: 14))
                    Text(empty ? String(localized: "很干净") : String(localized: "\(category.liveItems.count) 项 · 已选 \(category.selectedBytes.byteString)"))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.tertiary)
                        .lineLimit(1)
                    DottedLeader()
                    Text(category.totalBytes.byteString).font(Theme.figures(14)).fixedSize()
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(hovering && !empty ? Theme.primary : Theme.tertiary)
                    .opacity(empty ? 0 : 1)
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.fill.opacity(hovering && !empty ? 0.04 : 0)))
            .contentShape(Rectangle())
            .onTapGesture { if !empty { model.openReview(kind) } }
            .opacity(empty ? 0.5 : 1)
            .accessibilityAddTraits(empty ? [] : .isButton)
            .accessibilityHint(empty ? "" : String(localized: "查看"))
        }
    }
}

// MARK: - Review

private struct SmartReview: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let current = model.category(model.reviewKind)
        VStack(spacing: 0) {
            HStack {
                Button {
                    model.backToResults()
                } label: {
                    Label("返回结果", systemImage: "chevron.left")
                }
                .buttonStyle(GhostButtonStyle())
                Spacer()
                ModePicker()
            }
            .padding(.horizontal, 32)
            .padding(.top, 40)

            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 3) {
                    ForEach(model.junk) { ReviewCategoryRow(category: $0) }
                    Spacer(minLength: 0)
                }
                .frame(width: 236)
                .surfaceCard(radius: 16, padding: 8)

                VStack(alignment: .leading, spacing: 16) {
                    ReviewHeader(category: current)
                    ItemList(category: current)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 16)

            ActionBar(label: String(localized: "已选择"), bytes: model.junkSelectedBytes,
                      detail: String(localized: "\(model.junkSelectedCount) 项 · 来自 \(model.junk.filter { !$0.selectedItems.isEmpty }.count) 个类别")) {
                Button {
                    model.requestSmartClean()
                } label: {
                    Label("开始清理", systemImage: "arrow.up.trash")
                }
                .buttonStyle(PrimaryButtonStyle(accent: accent, large: true))
                .disabled(model.junkSelectedCount == 0)
                .opacity(model.junkSelectedCount == 0 ? 0.5 : 1)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }
}

private struct ReviewCategoryRow: View {
    let category: CleanCategory
    @Environment(AppModel.self) private var model

    var body: some View {
        let active = model.reviewKind == category.kind
        Hoverable { hovering in
            HStack(spacing: 10) {
                CheckBox(state: category.selectionState, tint: category.kind.color, label: String(localized: "全选\(category.kind.title)")) { category.toggleAll() }
                    .disabled(category.liveItems.isEmpty)
                CategoryIcon(kind: category.kind, size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(category.kind.title).font(.system(size: 13, weight: .semibold))
                    Text(category.liveItems.isEmpty ? String(localized: "很干净") : String(localized: "\(category.selectedItems.count)/\(category.liveItems.count) 项已选"))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.tertiary)
                }
                Spacer(minLength: 4)
                Text(category.totalBytes.byteString)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Theme.fill.opacity(active ? 0.1 : (hovering ? 0.04 : 0)))
            )
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(Theme.pageTransition) { model.reviewKind = category.kind } }
        }
    }
}

private struct ReviewHeader: View {
    let category: CleanCategory

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            CategoryIcon(kind: category.kind, size: 42)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(category.kind.title).font(Theme.title(22))
                    Text(category.totalBytes.byteString)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.secondary)
                        .contentTransition(.numericText())
                }
                Text(category.kind.summary)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Label("拖起任意一行，亲手甩进右下角的纸篓；按住 ⌥ 会出现碎纸机，永久删除", systemImage: "hand.draw.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(accent)
                    .padding(.top, 2)
            }
            Spacer(minLength: 12)
            Button(category.selectionState == .on ? String(localized: "全不选") : String(localized: "全选")) { category.toggleAll() }
                .buttonStyle(GhostButtonStyle())
                .disabled(category.liveItems.isEmpty)
        }
    }
}

// MARK: - Cleaning

private struct SmartCleaning: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let current = model.category(model.reviewKind)
        let progress = model.cleanTotal > 0 ? Double(model.cleanDone) / Double(model.cleanTotal) : 0
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("正在揉纸团…").font(Theme.title(28))
                    Spacer()
                    Text("\(model.cleanDone) / \(model.cleanTotal)")
                        .font(.system(size: 15, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Theme.secondary)
                        .contentTransition(.numericText())
                }
                ProgressBar(value: progress, accent: accent)
                HStack(spacing: 8) {
                    CategoryIcon(kind: current.kind, size: 22)
                    Text("正在清理「\(current.kind.title)」").font(.system(size: 13)).foregroundStyle(Theme.secondary)
                }
            }
            .padding(.horizontal, 36)
            .padding(.top, 48)

            ItemList(category: current)
                .padding(.horizontal, 32)
                .padding(.vertical, 18)

            ActionBar(label: String(localized: "待清理"), bytes: model.junkSelectedBytes, detail: String(localized: "\(model.cleanTotal - model.cleanDone) 项")) {
                Label("清理中", systemImage: "hands.sparkles.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
            }
        }
    }
}

// MARK: - Done

/// The finish screen: the hoop badge catches a paper ball, the freed space counts up,
/// and a paper receipt prints out with the breakdown.
private struct SmartDone: View {
    @Environment(AppModel.self) private var model
    @StateObject private var shown = FlagModel()

    var body: some View {
        let summary = model.lastSummary ?? CleanSummary(source: .smartClean, mode: model.mode)
        let canEmptyTrash = summary.mode == .trash && summary.count > 0 && !summary.trashEmptied
        HStack(alignment: .center, spacing: 64) {
            VStack(alignment: .leading, spacing: 0) {
                HoopBadge(dropped: shown.isOn)
                    .accessibilityHidden(true)
                    .frame(width: 112, height: 112)
                Text(summary.count > 0 ? String(localized: "清理完成") : String(localized: "这次没有扔掉任何东西"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accent)
                    .padding(.top, 28)
                CountUpText(bytes: summary.bytes, start: model.doneAt, duration: 1.2, font: Theme.title(64))
                    .padding(.top, 2)
                Text(summary.mode == .trash ? String(localized: "已扔进废纸篓") : String(localized: "已释放"))
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.secondary)
                if canEmptyTrash {
                    Text("清倒废纸篓之后，这些空间才会真正腾出来。")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.tertiary)
                        .padding(.top, 12)
                }
                HStack(spacing: 10) {
                    Button("完成") { model.finishSmartClean() }
                        .buttonStyle(PrimaryButtonStyle(accent: accent, large: true))
                        .keyboardShortcut(.defaultAction)
                    if canEmptyTrash {
                        Button("清倒废纸篓") { model.requestEmptyTrash() }
                            .buttonStyle(SecondaryButtonStyle(large: true))
                    }
                    if model.canRestore(summary) {
                        Button {
                            model.restore(summary.historyID)
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                        }
                        .buttonStyle(SecondaryButtonStyle(large: true))
                        .help("撤销：把这次扔掉的文件全部放回原处")
                        .accessibilityLabel("撤销这次清理")
                    }
                }
                .padding(.top, 32)
            }
            .frame(width: 330, alignment: .leading)

            Receipt(summary: summary, printed: shown.isOn)
                .frame(width: 350)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
        .task { shown.isOn = true }
    }
}

/// The app's mark in miniature: an off-white tile with the hoop, and a paper ball dropping in.
private struct HoopBadge: View {
    let dropped: Bool

    var body: some View {
        GeometryReader { geo in
            let side = geo.size.width
            ZStack {
                RoundedRectangle(cornerRadius: side * 0.24, style: .continuous)
                    .fill(Color(hex: 0xF4F0E7))
                    .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
                Canvas { context, size in
                    var g = context
                    let scale = size.width * 0.62 / BinLogo.hoopRing.width
                    g.translateBy(x: size.width / 2, y: size.height * 0.44)
                    g.scaleBy(x: scale, y: scale)
                    g.translateBy(x: -BinLogo.hoopRing.midX, y: -BinLogo.hoopRing.midY)
                    BinLogo.drawHoop(g, ink: Splash.charcoal)
                }
                // Drawn over the net: in this flat style a ball behind the strings just disappears.
                Canvas { context, size in
                    var g = context
                    g.translateBy(x: size.width / 2, y: size.height / 2)
                    g.scaleBy(x: size.width * 0.4 / 78, y: size.width * 0.4 / 78)
                    MinimalLogo.drawBall(g, center: .zero, radius: 78, ink: .white, cut: Splash.charcoal, detailed: false, outline: Splash.charcoal)
                }
                .frame(width: side * 0.3, height: side * 0.3)
                .rotationEffect(.degrees(dropped ? 160 : 0))
                .offset(y: dropped ? side * 0.1 : -side * 0.3)
                .animation(.easeIn(duration: 0.55).delay(0.25), value: dropped)
            }
        }
    }
}

/// A paper till receipt with the breakdown. It "prints" from the top when the page opens.
private struct Receipt: View {
    let summary: CleanSummary
    let printed: Bool

    private let paper = Color(hex: 0xF6F0E4)
    private let ink = Color(hex: 0x2E2C29)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Crumple").font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(summary.finishedAt.formatted(date: .numeric, time: .shortened))
                    .font(.system(size: 11, design: .monospaced))
                    .opacity(0.6)
            }
            Text("清理小票 · \(summary.source.title)").font(.system(size: 11)).opacity(0.55)
            DashedRule()

            if summary.lines.isEmpty {
                Text("这次没有清理任何东西").font(.system(size: 13)).opacity(0.6)
            }
            ForEach(summary.lines, id: \.kind) { line in
                HStack(spacing: 8) {
                    Text(line.kind.title).font(.system(size: 13, weight: .medium))
                    Text("×\(line.count)").font(.system(size: 12, design: .monospaced)).opacity(0.45)
                    Spacer(minLength: 8)
                    Text(line.bytes.byteString).font(.system(size: 13, weight: .medium).monospacedDigit())
                }
            }
            DashedRule()

            HStack {
                figure(String(localized: "纸团"), String(localized: "\(summary.count) 个"))
                figure(String(localized: "用时"), String(format: String(localized: "%.0f 秒"), max(1, summary.duration)))
                figure(String(localized: "没扔进去"), String(localized: "\(summary.failed) 项"))
            }
            if !summary.failures.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(summary.failures.prefix(3), id: \.self) { failure in
                        Text("· \(failure.name)：\(failure.reason.replacingOccurrences(of: "\(failure.name) ", with: ""))")
                            .font(.system(size: 11))
                            .opacity(0.6)
                            .lineLimit(1)
                    }
                    if summary.failures.count > 3 {
                        Text("· 还有 \(summary.failures.count - 3) 项").font(.system(size: 11)).opacity(0.6)
                    }
                }
            }
            DashedRule()

            HStack(alignment: .firstTextBaseline) {
                Text("合计").font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(summary.bytes.byteString).font(.system(size: 28, weight: .semibold))
            }
            Text(summary.mode == .trash ? String(localized: "已移到废纸篓") : String(localized: "已直接删除"))
                .font(.system(size: 11))
                .opacity(0.55)
                .frame(maxWidth: .infinity, alignment: .trailing)

            Barcode(seed: UInt64(truncatingIfNeeded: summary.bytes) &+ UInt64(summary.count))
                .frame(height: 36)
                .padding(.top, 4)
            Text("谢谢光临 · 把垃圾揉成纸团")
                .font(.system(size: 11))
                .opacity(0.55)
                .frame(maxWidth: .infinity)
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 34)
        .background(TornPaper().fill(paper).shadow(color: .black.opacity(0.08), radius: 12, y: 6))
        .rotationEffect(.degrees(1.2))
        .mask {
            Rectangle()
                .padding(-50)
                .scaleEffect(x: 1, y: printed ? 1 : 0, anchor: .top)
        }
        .offset(y: printed ? 0 : -24)
        .animation(.easeOut(duration: 1.1).delay(0.35), value: printed)
    }

    private func figure(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 11)).opacity(0.55)
            Text(value).font(.system(size: 14, weight: .semibold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A receipt's outline: straight top, a torn zigzag bottom.
private struct TornPaper: Shape {
    func path(in rect: CGRect) -> Path {
        let tooth: CGFloat = 8
        let count = max(1, Int(rect.width / (tooth * 2)))
        let step = rect.width / CGFloat(count)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - tooth))
        for i in 0..<count {
            let x = rect.maxX - CGFloat(i) * step
            path.addLine(to: CGPoint(x: x - step / 2, y: rect.maxY))
            path.addLine(to: CGPoint(x: x - step, y: rect.maxY - tooth))
        }
        path.closeSubpath()
        return path
    }
}

private struct DashedRule: View {
    var body: some View {
        Canvas { context, size in
            var line = Path()
            line.move(to: CGPoint(x: 0, y: size.height / 2))
            line.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            context.stroke(line, with: .foreground, style: StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
        }
        .frame(height: 2)
        .opacity(0.35)
        .accessibilityHidden(true)
    }
}

private struct Barcode: View {
    let seed: UInt64

    var body: some View {
        Canvas { context, size in
            var rng = SeededRandom(seed | 1)
            var x: CGFloat = 0
            while x < size.width {
                let bar = rng.range(1, 4).rounded()
                context.fill(Path(CGRect(x: x, y: 0, width: bar, height: size.height)), with: .foreground)
                x += bar + rng.range(1.5, 4).rounded()
            }
        }
        .accessibilityHidden(true)
    }
}
