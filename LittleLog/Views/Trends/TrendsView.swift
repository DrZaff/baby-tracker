import SwiftUI
import Charts

enum TrendRange: String, CaseIterable, Identifiable {
    case week = "Week", month = "Month", year = "Year"
    var id: String { rawValue }
}

/// Two-series chart colors, checked for color-blind separation in light and dark mode.
enum ChartPalette {
    static let first = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0x5A / 255, green: 0x82 / 255, blue: 0xDE / 255, alpha: 1)
        : UIColor(red: 0x3F / 255, green: 0x6F / 255, blue: 0xD8 / 255, alpha: 1) })
    static let second = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0xD4 / 255, green: 0x76 / 255, blue: 0x34 / 255, alpha: 1)
        : UIColor(red: 0xD0 / 255, green: 0x6A / 255, blue: 0x28 / 255, alpha: 1) })
}

struct TrendPoint: Identifiable {
    let date: Date
    let series: String
    let value: Double
    var id: String { "\(date.timeIntervalSince1970)-\(series)" }
}

struct TrendsView: View {
    let baby: Baby

    @AppStorage("useMetric") private var useMetric = false
    @State private var range: TrendRange = .week
    @State private var entries: [LogEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var calendar: Calendar { Calendar.current }

    /// Week and month show one bar per day. Year shows one bar per month with the daily average.
    private var bucketUnit: Calendar.Component { range == .year ? .month : .day }

    private var rangeStart: Date {
        let today = calendar.startOfDay(for: Date())
        switch range {
        case .week: return calendar.date(byAdding: .day, value: -6, to: today) ?? today
        case .month: return calendar.date(byAdding: .day, value: -29, to: today) ?? today
        case .year:
            let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
            return calendar.date(byAdding: .month, value: -11, to: thisMonth) ?? today
        }
    }

    private struct Bucket {
        let start: Date
        let summary: DaySummary
        let days: Double
    }

    private var buckets: [Bucket] {
        let now = Date()
        let birthDay = calendar.startOfDay(for: baby.birthDate)
        var result: [Bucket] = []
        var cursor = rangeStart
        while cursor <= now {
            guard let next = calendar.date(byAdding: bucketUnit, value: 1, to: cursor) else { break }
            let inBucket = entries.filter { $0.timestamp >= cursor && $0.timestamp < next }
            // Days that count toward the average: not before birth and not in the future.
            let from = max(cursor, birthDay)
            let to = min(next, calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? next)
            let days = max(1, (to.timeIntervalSince(from) / 86_400).rounded())
            result.append(Bucket(start: cursor, summary: DaySummary(entries: inBucket), days: range == .year ? days : 1))
            cursor = next
        }
        return result
    }

    private func points(_ series: [(String, (DaySummary) -> Double)]) -> [TrendPoint] {
        buckets.flatMap { bucket in
            series.map { name, value in
                TrendPoint(date: bucket.start, series: name, value: value(bucket.summary) / bucket.days)
            }
        }
    }

    private var volumeScale: Double { useMetric ? 1 : 1 / Units.mlPerOunce }
    private var volumeUnit: String { Units.volumeUnit(metric: useMetric) }
    private var perLabel: String { range == .year ? "avg per day" : "per day" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("Range", selection: $range) {
                        ForEach(TrendRange.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if let errorMessage {
                        Text(errorMessage).font(.footnote).foregroundStyle(.red)
                    }

                    ChartCard(
                        title: "Feeds", subtitle: perLabel, unit: bucketUnit, valueFormat: "%.1f",
                        points: points([("Feeds", { Double($0.feedCount) })])
                    )
                    ChartCard(
                        title: "Breastfeeding", subtitle: "minutes \(perLabel)", unit: bucketUnit, valueFormat: "%.0f",
                        points: points([
                            ("Left", { Double($0.breastLeftSeconds) / 60 }),
                            ("Right", { Double($0.breastRightSeconds) / 60 }),
                        ])
                    )
                    ChartCard(
                        title: "Bottle", subtitle: "\(volumeUnit) \(perLabel)", unit: bucketUnit, valueFormat: "%.1f",
                        points: points([
                            ("Formula", { $0.formulaML * volumeScale }),
                            ("Breast milk", { $0.breastMilkML * volumeScale }),
                        ])
                    )
                    ChartCard(
                        title: "Pumped", subtitle: "\(volumeUnit) \(perLabel)", unit: bucketUnit, valueFormat: "%.1f",
                        points: points([("Pumped", { $0.pumpedML * volumeScale })])
                    )
                    ChartCard(
                        title: "Diapers", subtitle: perLabel, unit: bucketUnit, valueFormat: "%.1f",
                        points: points([
                            ("Wet", { Double($0.wetCount) }),
                            ("Dirty", { Double($0.dirtyCount) }),
                        ])
                    )
                    WeightChart(entries: entries.filter { $0.kind == .weight && $0.weightGrams != nil }, metric: useMetric)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .overlay {
                if isLoading && entries.isEmpty { ProgressView() }
            }
            .navigationTitle("Trends")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { BabySwitcher() }
            }
            .task(id: "\(baby.babyID)|\(range.rawValue)") { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            entries = try await EntryRepository.fetch(babyID: baby.babyID, from: rangeStart, to: Date().addingTimeInterval(60))
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// A bar chart (stacked when there are two series) with tap-to-inspect.
struct ChartCard: View {
    let title: String
    let subtitle: String
    let unit: Calendar.Component
    let valueFormat: String
    let points: [TrendPoint]

    @State private var selectedDate: Date?

    private var seriesNames: [String] {
        var seen: [String] = []
        for p in points where !seen.contains(p.series) { seen.append(p.series) }
        return seen
    }

    private var hasData: Bool { points.contains { $0.value > 0 } }

    private var selectedPoints: [TrendPoint] {
        guard let selectedDate else { return [] }
        let calendar = Calendar.current
        return points.filter { calendar.isDate($0.date, equalTo: selectedDate, toGranularity: unit) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let first = selectedPoints.first {
                    Text(selectionText(date: first.date))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            if hasData {
                Chart(points) { point in
                    BarMark(
                        x: .value("Date", point.date, unit: unit),
                        y: .value(title, point.value)
                    )
                    .foregroundStyle(by: .value("Series", point.series))
                    .cornerRadius(3)
                    .opacity(selectedDate == nil || Calendar.current.isDate(point.date, equalTo: selectedDate!, toGranularity: unit) ? 1 : 0.4)
                }
                .chartForegroundStyleScale(domain: seriesNames, range: [ChartPalette.first, ChartPalette.second].prefix(max(1, seriesNames.count)).map { $0 })
                .chartLegend(seriesNames.count > 1 ? .visible : .hidden)
                .chartXSelection(value: $selectedDate)
                .chartXAxis {
                    AxisMarks(values: .stride(by: unit, count: unit == .day && points.count > 20 ? 7 : 1)) { _ in
                        AxisGridLine().foregroundStyle(.clear)
                        AxisValueLabel(format: axisFormat, centered: true)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(.secondary.opacity(0.3))
                        AxisValueLabel()
                    }
                }
                .frame(height: 160)
            } else {
                Text("Nothing logged in this period yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var axisFormat: Date.FormatStyle {
        if unit == .month { return .dateTime.month(.narrow) }
        if points.count > 20 { return .dateTime.month(.abbreviated).day() }
        return .dateTime.weekday(.narrow)
    }

    private func selectionText(date: Date) -> String {
        let label = unit == .month
            ? date.formatted(.dateTime.month(.abbreviated).year())
            : date.formatted(.dateTime.month(.abbreviated).day())
        let values = selectedPoints.map { p in
            (seriesNames.count > 1 ? "\(p.series) " : "") + String(format: valueFormat, p.value)
        }
        return "\(label): " + values.joined(separator: " · ")
    }
}

struct WeightChart: View {
    let entries: [LogEntry]
    let metric: Bool

    @State private var selectedDate: Date?

    private func value(_ entry: LogEntry) -> Double {
        let grams = entry.weightGrams ?? 0
        return metric ? grams / 1000 : grams / Units.gramsPerPound
    }

    private var sorted: [LogEntry] { entries.sorted { $0.timestamp < $1.timestamp } }

    private var selected: LogEntry? {
        guard let selectedDate else { return nil }
        return sorted.min { abs($0.timestamp.timeIntervalSince(selectedDate)) < abs($1.timestamp.timeIntervalSince(selectedDate)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Weight").font(.headline)
                Text(metric ? "kg" : "lb").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let entry = selected ?? sorted.last, let grams = entry.weightGrams {
                    Text("\(entry.timestamp.formatted(.dateTime.month(.abbreviated).day())): \(Units.weight(grams, metric: metric))")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            if sorted.isEmpty {
                Text("Log a weight to see growth over time.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                Chart {
                    ForEach(sorted) { entry in
                        LineMark(x: .value("Date", entry.timestamp), y: .value("Weight", value(entry)))
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .foregroundStyle(ChartPalette.first)
                        PointMark(x: .value("Date", entry.timestamp), y: .value("Weight", value(entry)))
                            .symbolSize(60)
                            .foregroundStyle(ChartPalette.first)
                    }
                    if let selected {
                        RuleMark(x: .value("Selected", selected.timestamp))
                            .foregroundStyle(.secondary.opacity(0.4))
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXSelection(value: $selectedDate)
                .frame(height: 160)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
