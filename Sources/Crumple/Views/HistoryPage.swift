import SwiftUI
import Charts

struct HistoryPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.history.isEmpty {
            LandingView(
                page: .history, hero: .history, title: String(localized: "还没有清理记录"),
                subtitle: String(localized: "每次清理都会记在这里：\n扔了多少、什么时候、用的是哪种方式。"),
                chips: [], buttonTitle: String(localized: "去清理"), action: { model.startSmartScan() }
            ) {
                EmptyView()
            }
        } else {
            HistoryContent()
        }
    }
}

private struct HistoryContent: View {
    @Environment(AppModel.self) private var model

    private struct DayTotal: Identifiable {
        let day: Date
        let bytes: Int64
        var id: Date { day }
    }

    private var lastTwoWeeks: [DayTotal] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<14).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: today)!
            let bytes = model.history.filter { calendar.isDate($0.date, inSameDayAs: day) }.reduce(Int64(0)) { $0 + $1.bytes }
            return DayTotal(day: day, bytes: bytes)
        }
    }

    private var groups: [(day: Date, entries: [HistoryEntry])] {
        let grouped = Dictionary(grouping: model.history) { Calendar.current.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0]!.sorted { $0.date > $1.date }) }
    }

    var body: some View {
        let accent = Page.history.accent
        let days = lastTwoWeeks
        let useGB = (days.map(\.bytes).max() ?? 0) >= 1_000_000_000
        let unit = useGB ? 1_000_000_000.0 : 1_000_000.0
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("清理记录").font(Theme.title(30))
                        Text("从第一次清理到现在，一共扔掉了这么多").font(.system(size: 13)).foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    Button("清空记录") { model.clearHistory() }
                        .buttonStyle(GhostButtonStyle())
                }

                HStack(spacing: 16) {
                    BigStat(symbol: "trash.fill", value: model.historyTotal.byteString, label: String(localized: "累计扔掉"), color: accent)
                    BigStat(symbol: "number", value: String(localized: "\(model.history.count) 次"), label: String(localized: "清理次数"), color: Page.overview.accent)
                    BigStat(symbol: "circle.hexagongrid.fill", value: String(localized: "\(model.historyPapers) 个"), label: String(localized: "揉过的纸团"), color: Page.smartClean.accent)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("最近 14 天").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.secondary)
                    Chart(days) { day in
                        BarMark(
                            x: .value(String(localized: "日期"), day.day, unit: .day),
                            y: .value(useGB ? "GB" : "MB", Double(day.bytes) / unit)
                        )
                        .foregroundStyle(Calendar.current.isDateInToday(day.day) ? accent : Theme.fill.opacity(0.18))
                        .cornerRadius(3)
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                            AxisValueLabel(format: .dateTime.month(.defaultDigits).day(), centered: true)
                                .foregroundStyle(Theme.tertiary)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine().foregroundStyle(Theme.fill.opacity(0.07))
                            AxisValueLabel {
                                if let number = value.as(Double.self) {
                                    Text("\(number, specifier: "%.0f") \(useGB ? "GB" : "MB")").foregroundStyle(Theme.tertiary)
                                }
                            }
                        }
                    }
                    .frame(height: 170)
                }
                .surfaceCard(radius: 20, padding: 20)

                ForEach(groups, id: \.day) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(dayTitle(group.day))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.tertiary)
                            .padding(.leading, 4)
                        VStack(spacing: 0) {
                            ForEach(group.entries) { HistoryRow(entry: $0) }
                        }
                        .surfaceCard(radius: 16, padding: 6)
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 48)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.never)
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return String(localized: "今天") }
        if calendar.isDateInYesterday(day) { return String(localized: "昨天") }
        return day.formatted(.dateTime.month().day().weekday(.wide))
    }
}

private struct BigStat: View {
    let symbol: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.secondary)
            Text(value).font(Theme.title(28)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard(radius: 16, padding: 16)
    }
}

struct HistoryRow: View {
    let entry: HistoryEntry
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            SymbolTile(symbol: entry.source.symbol, color: entry.source.color, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.source.title).font(.system(size: 13, weight: .medium))
                    if entry.isRestored { Badge(text: String(localized: "已撤销"), color: Theme.secondary) }
                }
                Text(detail).font(.system(size: 12)).foregroundStyle(Theme.tertiary)
            }
            Spacer()
            if model.canRestore(entry) {
                Button {
                    model.restore(entry.id)
                } label: {
                    Label("放回", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(GhostButtonStyle())
                .help("把这次扔掉的文件从废纸篓放回原处")
            }
            Text(entry.bytes.byteString)
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                .strikethrough(entry.isRestored)
                .foregroundStyle(entry.isRestored ? Theme.tertiary : .primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var detail: String {
        let time = entry.date.formatted(date: .omitted, time: .shortened)
        var parts = [time, String(localized: "\(entry.count) 个纸团")]
        if entry.failed > 0 { parts.append(String(localized: "\(entry.failed) 项没扔进去")) }
        parts.append(entry.mode.title)
        return parts.joined(separator: " · ")
    }
}
