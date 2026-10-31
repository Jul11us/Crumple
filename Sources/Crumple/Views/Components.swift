import SwiftUI
import AppKit

// MARK: - Design tokens

enum Theme {
    static let base = Color.adaptive(light: 0xFAF9F6, dark: 0x1D1E1B)
    static let sidebar = Color.adaptive(light: 0xF1F0EC, dark: 0x181916)
    static let primary = Color.adaptive(light: 0x272923, dark: 0xECEEE7)
    static let secondary = Color.adaptive(light: 0x606359, dark: 0xB2B6AA)
    static let tertiary = Color.adaptive(light: 0x73766C, dark: 0x979C8E)
    static let card = Color.adaptive(light: 0xFFFFFF, dark: 0x252722)
    static let raised = Color.adaptive(light: 0xE9EBE4, dark: 0x33362E)
    static let accent = Color.adaptive(light: 0x4F6848, dark: 0xB7CDAA)
    static let onAccent = Color.adaptive(light: 0xFFFFFF, dark: 0x1D1E1B)
    static let accentSurface = Color.adaptive(light: 0xEEF1E9, dark: 0x2B3226)
    static let warning = Color.adaptive(light: 0x996324, dark: 0xDBB477)
    static let danger = Color.adaptive(light: 0xAA413B, dark: 0xE99C92)
    static let chart = Color.adaptive(light: 0x747F6A, dark: 0x8A9B7D)
    static let stroke = primary.opacity(0.09)
    static let fill = primary
    static let sidebarWidth: CGFloat = 240
    static let feedback = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.16)
    static let pageTransition = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.28)

    static func title(_ size: CGFloat) -> Font { .system(size: size, weight: .medium) }
}

/// A quiet paper surface leaves the emphasis to the content.
struct PageBackground: View {
    var body: some View {
        Theme.base
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

extension View {
    func surfaceCard(radius: CGFloat = 16, padding: CGFloat = 20, highlighted: Bool = false) -> some View {
        self
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(highlighted ? Theme.fill.opacity(0.18) : Theme.stroke))
            .animation(Theme.feedback, value: highlighted)
    }
}

// MARK: - Hover

final class HoverModel: ObservableObject {
    @Published var isHovering = false
}

/// Gives its content a hover flag (we can't use @State with this toolchain, but @StateObject works).
struct Hoverable<Content: View>: View {
    @StateObject private var hover = HoverModel()
    @ViewBuilder let content: (Bool) -> Content

    var body: some View {
        content(hover.isHovering)
            .onHover { hover.isHovering = $0 }
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    var accent: Color
    var large = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: large ? 14 : 13, weight: .medium))
            .foregroundStyle(colorScheme == .dark ? Theme.base : .white)
            .padding(.horizontal, large ? 24 : 16)
            .frame(height: large ? 44 : 36)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(colorScheme == .dark ? Theme.primary : accent))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isFocused ? Theme.accent : .clear, lineWidth: 2))
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(Theme.feedback, value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var large = false
    @Environment(\.isFocused) private var isFocused
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: large ? 14 : 13, weight: .medium))
            .foregroundStyle(Theme.primary)
            .padding(.horizontal, large ? 24 : 16)
            .frame(height: large ? 44 : 36)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(configuration.isPressed ? Theme.raised : Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isFocused ? Theme.accent : Theme.stroke, lineWidth: isFocused ? 2 : 1))
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(Theme.feedback, value: configuration.isPressed)
    }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(configuration.isPressed ? Theme.tertiary : Theme.secondary)
            .contentShape(Rectangle())
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(Theme.feedback, value: configuration.isPressed)
    }
}

// MARK: - Small pieces

struct CheckBox: View {
    var state: CheckState
    var tint: Color
    /// What VoiceOver reads, e.g. the file's name.
    var label = String(localized: "全选")
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(state == .off ? Theme.fill.opacity(0.04) : tint)
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(state == .off ? Theme.fill.opacity(0.3) : tint, lineWidth: 1.3)
                switch state {
                case .on: Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.onAccent)
                case .mixed: Image(systemName: "minus").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.onAccent)
                case .off: EmptyView()
                }
            }
            .frame(width: 17, height: 17)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(state == .on ? String(localized: "已选中") : state == .mixed ? String(localized: "部分选中") : String(localized: "未选中"))
        .accessibilityAddTraits(.isToggle)
    }
}

struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.16)))
    }
}

/// Consistent, quiet SF Symbols throughout the interface.
struct SymbolTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .regular))
            .foregroundStyle(Theme.secondary)
            .frame(width: size, height: size)
    }
}

struct CategoryIcon: View {
    let kind: CategoryKind
    let size: CGFloat

    var body: some View {
        SymbolTile(symbol: kind.symbol, color: kind.color, size: size)
    }
}

struct FeatureChip: View {
    let symbol: String
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 16)).frame(width: 20)
            Text(title).font(.system(size: 13))
        }
        .foregroundStyle(Theme.secondary)
    }
}

struct AppGlyph: View {
    var body: some View {
        Canvas { context, size in IconArt.draw(context, side: size.width) }
    }
}

/// Speech bubble above the basket explaining why a paper bounced off.
struct BasketNote: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "hand.raised.fill")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.onAccent)
            .lineLimit(2)
            .frame(maxWidth: 260, alignment: .trailing)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.danger)
            )
    }
}

/// A number that counts up from zero after `start`, then stops redrawing.
struct CountUpText: View {
    let bytes: Int64
    let start: Date
    var duration: Double = 1.1
    var font: Font
    @StateObject private var finished = FlagModel()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: finished.isOn)) { timeline in
            let t = finished.isOn ? 1 : clamp01(timeline.date.timeIntervalSince(start) / duration)
            Text(Int64(Double(bytes) * easeOutCubic(t)).byteString)
                .font(font)
                .monospacedDigit()
        }
        .task(id: start) {
            finished.isOn = false
            let remaining = duration - Date().timeIntervalSince(start)
            if remaining > 0 { try? await Task.sleep(for: .seconds(remaining + 0.05)) }
            finished.isOn = true
        }
    }
}

/// Determinate scans show progress; only an indeterminate scan needs a moving arc.
struct ScanRing<Content: View>: View {
    let progress: Double
    let accent: Color
    var indeterminate = false
    @ViewBuilder let content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().stroke(Theme.fill.opacity(0.07), lineWidth: 14)
            if !indeterminate {
                Circle()
                    .trim(from: 0, to: max(0.001, progress))
                    .stroke(accent, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.45), value: progress)
            }
            if indeterminate {
                TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
                    let angle = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 2.4) / 2.4 * 360
                    Circle()
                        .trim(from: 0, to: 0.28)
                        .stroke(accent, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .rotationEffect(.degrees(angle))
                }
            }
            content
        }
    }
}

/// Bottom bar of the list pages: what's selected, the main button, and the running total.
/// Leaves room on the right for the basket.
struct ActionBar<Trailing: View>: View {
    let label: String
    let bytes: Int64
    let detail: String
    @ViewBuilder let button: Trailing
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 22) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                Text(bytes.byteString)
                    .font(Theme.title(28))
                    .contentTransition(.numericText())
                Text(detail).font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
            Spacer()
            button
            VStack(alignment: .trailing, spacing: 2) {
                Text("本次已扔掉").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                Text(model.sessionFreed.byteString)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Page.smartClean.accent)
                    .contentTransition(.numericText())
            }
            .frame(minWidth: 84, alignment: .trailing)
        }
        .padding(.leading, 32)
        .padding(.trailing, BasketGeometry.reservedTrailing)
        .frame(height: 124)
        .background(Theme.base)
        .overlay(alignment: .top) { Rectangle().fill(Theme.stroke).frame(height: 1) }
    }
}

/// Shown on list pages after a cleaning run.
struct SummaryBanner: View {
    let summary: CleanSummary
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: summary.count > 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 22))
                .foregroundStyle(summary.count > 0 ? Theme.accent : Theme.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("揉了 \(summary.count) 个纸团，共 \(summary.bytes.byteString)")
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 8)
            if model.canRestore(summary) {
                Button {
                    model.restore(summary.historyID)
                } label: {
                    Label("撤销", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(SecondaryButtonStyle())
                .help("把这次扔掉的文件从废纸篓放回原处")
            }
            if summary.mode == .trash && !summary.trashEmptied && summary.count > 0 {
                Button("清倒废纸篓") { model.requestEmptyTrash() }.buttonStyle(SecondaryButtonStyle())
            }
            Button {
                withAnimation(Theme.pageTransition) { model.banner = nil }
            } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.secondary)
            }
            .buttonStyle(.plain)
        }
        .surfaceCard(radius: 14, padding: 12)
    }

    private var detail: String {
        var parts: [String] = []
        if summary.failed > 0 { parts.append(String(localized: "\(summary.failed) 项没扔进去。")) }
        if summary.mode == .trash {
            parts.append(summary.trashEmptied ? String(localized: "废纸篓已清倒，空间已释放。") : String(localized: "文件在废纸篓里，清倒后才会真正释放空间。"))
        } else {
            parts.append(String(localized: "文件已直接删除。"))
        }
        return parts.joined(separator: " ")
    }
}

/// A small capsule message at the top of the window.
struct Toast: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Page.smartClean.accent)
            Text(text).font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.stroke))
        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}

/// The paper object sits beside the task, with a single conventional action.
struct LandingView<Footer: View>: View {
    let page: Page
    let hero: HeroStyle
    let title: String
    let subtitle: String
    let chips: [(String, String)]
    let buttonTitle: String
    let action: () -> Void
    @ViewBuilder let footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(page.title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.secondary)
            Spacer(minLength: 40)
            HStack(alignment: .center, spacing: 32) {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(title).font(Theme.title(36))
                        Text(subtitle.replacingOccurrences(of: "\n", with: " "))
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.secondary)
                            .lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !chips.isEmpty {
                        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                                  alignment: .leading, spacing: 16) {
                            ForEach(chips, id: \.1) { FeatureChip(symbol: $0.0, title: $0.1) }
                        }
                    }
                    Button(action: action) {
                        HStack(spacing: 24) {
                            Text(buttonTitle)
                            Image(systemName: "arrow.right")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle(accent: page.accent, large: true))
                    footer
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HeroScene(style: hero, accent: page.accent)
                    .frame(width: 360, height: 280)
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 40)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
