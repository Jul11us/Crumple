import SwiftUI
import AppKit

enum RowStyle { case standard, app }

/// A scrolling list of items in a glass panel. Rows can be ticked, or dragged and thrown at the basket.
struct ItemList: View {
    let category: CleanCategory
    var style: RowStyle = .standard
    @Environment(AppModel.self) private var model

    var body: some View {
        let items = model.visibleItems(in: category)
        let isCleaningHere = model.cleaningCategoryID == category.kind
        ZStack {
            if items.isEmpty {
                ListPlaceholder(scanning: category.isScanning, cleaning: isCleaningHere)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(items) { item in
                            ItemRow(item: item, category: category, style: style)
                                .transition(.asymmetric(
                                    insertion: .opacity,
                                    removal: .opacity.combined(with: .scale(scale: 0.92, anchor: .leading))
                                ))
                        }
                    }
                    .padding(8)
                }
                // A fresh scroll view when cleaning starts, so the queue starts at the top.
                .id("\(category.kind.rawValue)-\(isCleaningHere)")
                .allowsHitTesting(!model.isCleaning)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.stroke))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(StageSpace.name)) } action: { model.listViewport = $0 }
    }
}

struct ItemRow: View {
    let item: CleanItem
    let category: CleanCategory
    var style: RowStyle = .standard
    @Environment(AppModel.self) private var model

    // Only read inside gesture callbacks, so dragging doesn't re-render every row.
    private var isHeld: Bool { model.stage.held?.itemID == item.id }

    var body: some View {
        let focused = style == .app && model.focusedAppID == item.id
        Hoverable { hovering in
            HStack(spacing: 12) {
                CheckBox(state: item.isSelected ? .on : .off, tint: category.kind.color, label: item.name) { category.toggle(item.id) }
                ItemIcon(item: item)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(StageSpace.name)) } action: { model.iconFrames[item.id] = $0 }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(item.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        if let badge = item.badge { Badge(text: badge, color: Page.largeFiles.accent) }
                        if item.isAppStore { Badge(text: "App Store", color: Color(hex: 0x6FA8FF)) }
                        if item.status == .failed { Badge(text: String(localized: "没扔进去"), color: Page.duplicates.accent) }
                    }
                    Text(item.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 12)
                Text(item.size.byteString)
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.primary.opacity(0.85))
            }
            // Hidden (not removed) while its paper is in the air, so the drag gesture stays alive.
            .opacity(item.status == .tossed ? 0 : 1)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(focused ? category.kind.color.opacity(0.22)
                          : Theme.fill.opacity(hovering && item.status != .tossed ? 0.06 : 0))
            )
            .contentShape(Rectangle())
            .onHover { inside in if inside { model.pointedURL = item.appURL ?? item.url } }
            .gesture(tossGesture)
            .onTapGesture {
                model.pointedURL = item.appURL ?? item.url
                if style == .app {
                    withAnimation(Theme.pageTransition) { model.focusedAppID = item.id }
                } else {
                    category.toggle(item.id)
                }
            }
            .onDisappear {
                if isHeld { model.endToss(item, in: category, velocity: .zero) }
            }
            .accessibilityAction(named: "扔进纸篓") { model.throwAway(item, in: category) }
            .contextMenu {
                Button("快速查看") { model.previewURL = item.appURL ?? item.url }
                    .keyboardShortcut(.space, modifiers: [])
                Button("扔进纸篓") { model.throwAway(item, in: category) }
                    .disabled(model.isCleaning)
                Button("在访达中显示") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                if let keeper = item.keeper {
                    Button("显示保留的那一份") { NSWorkspace.shared.activateFileViewerSelecting([keeper]) }
                    Button("改为保留这一份") { model.keepInstead(item) }
                }
                Divider()
                Button("忽略，以后不再列出") { model.ignore(item, in: category) }
            }
            .help(item.badge == String(localized: "运行中") ? String(localized: "这个应用正在运行，它的缓存投不进纸篓，先退出它再试") : Paths.display(item.url))
        }
    }

    /// Pick the file up, crumple it, and fling it at the basket.
    private var tossGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(StageSpace.name))
            .onChanged { value in
                if isHeld {
                    model.moveToss(to: value.location)
                } else {
                    model.beginToss(item, in: category, at: value.location)
                }
            }
            .onEnded { value in
                if isHeld { model.endToss(item, in: category, velocity: value.velocity) }
            }
    }
}

struct ListPlaceholder: View {
    let scanning: Bool
    var cleaning = false

    var body: some View {
        VStack(spacing: 10) {
            if scanning {
                ProgressView().controlSize(.large)
                Text("正在扫描…").foregroundStyle(Theme.secondary)
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: 38))
                    .foregroundStyle(Page.smartClean.accent)
                Text(cleaning ? String(localized: "这一类清完了") : String(localized: "这里很干净")).font(.system(size: 15, weight: .semibold))
                Text(cleaning ? String(localized: "接着清理下一类…") : String(localized: "没有发现可以清理的文件")).font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
        }
        .padding(.bottom, 20)
    }
}

/// Scanning screen for the large-files and uninstaller pages.
struct ListScanning: View {
    let page: Page
    let title: String
    let detail: String
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            ScanRing(progress: 0, accent: page.accent, indeterminate: true) {
                Image(systemName: page.symbol)
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(page.accent)
            }
            .frame(width: 220, height: 220)
            Text(title).font(Theme.title(24)).padding(.top, 34)
            Text(detail)
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondary)
                .monospacedDigit()
                .contentTransition(.numericText())
                .padding(.top, 6)
            Spacer(minLength: 24)
            Button("停止扫描") { model.cancelScan(on: page) }
                .buttonStyle(SecondaryButtonStyle())
                .keyboardShortcut(.cancelAction)
            Spacer().frame(height: 40)
        }
        .frame(maxWidth: .infinity)
    }
}

struct FilterChip: View {
    let title: String
    var symbol: String? = nil
    let count: Int
    let selected: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol) }
                Text(title).foregroundStyle(selected ? accent : Theme.secondary)
                Text("\(count)").monospacedDigit().foregroundStyle(Theme.tertiary)
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Theme.accentSurface : .clear))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? Theme.stroke : .clear))
        }
        .buttonStyle(.plain)
    }
}

struct ProgressBar: View {
    let value: Double
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.fill.opacity(0.08))
                Capsule().fill(accent)
                    .frame(width: geo.size.width * max(0, min(1, value)))
            }
        }
        .frame(height: 6)
    }
}

struct ModePicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Picker("清理方式", selection: $model.mode) {
            ForEach(CleanMode.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 260)
        .disabled(model.isCleaning)
        .help("移到废纸篓可以恢复；直接删除会立刻释放空间")
    }
}
