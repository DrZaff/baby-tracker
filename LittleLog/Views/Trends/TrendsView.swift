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
    @State private var growth: [LogEntry] = []
    @State private var showingReport = false
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
            ScrollViewReader { proxy in
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
                        animal: Theme.feedAnimal,
                        colors: [Theme.feed],
                        points: points([("Feeds", { Double($0.feedCount) })])
                    )
                    ChartCard(
                        title: "Breastfeeding", subtitle: "minutes \(perLabel)", unit: bucketUnit, valueFormat: "%.0f",
                        animal: "🤱",
                        colors: [Theme.feed, Theme.mango],
                        points: points([
                            ("Left", { Double($0.breastLeftSeconds) / 60 }),
                            ("Right", { Double($0.breastRightSeconds) / 60 }),
                        ])
                    )
                    ChartCard(
                        title: "Bottle", subtitle: "\(volumeUnit) \(perLabel)", unit: bucketUnit, valueFormat: "%.1f",
                        animal: Theme.bottleAnimal,
                        colors: [Theme.bottle, Theme.hibiscus],
                        points: points([
                            ("Formula", { $0.formulaML * volumeScale }),
                            ("Breast milk", { $0.breastMilkML * volumeScale }),
                        ])
                    )
                    ChartCard(
                        title: "Pumped", subtitle: "\(volumeUnit) \(perLabel)", unit: bucketUnit, valueFormat: "%.1f",
                        animal: Theme.pumpAnimal,
                        colors: [Theme.pump],
                        points: points([("Pumped", { $0.pumpedML * volumeScale })])
                    )
                    ChartCard(
                        title: "Diapers", subtitle: perLabel, unit: bucketUnit, valueFormat: "%.1f",
                        animal: Theme.diaperAnimal,
                        colors: [Theme.diaper, Theme.bark],
                        points: points([
                            ("Wet", { Double($0.wetCount) }),
                            ("Dirty", { Double($0.dirtyCount) }),
                        ])
                    )
                    ChartCard(
                        title: "Tummy time", subtitle: "minutes \(perLabel)", unit: bucketUnit, valueFormat: "%.0f",
                        animal: Theme.tummyAnimal,
                        colors: [Theme.tummy],
                        points: points([("Tummy time", { Double($0.tummySeconds) / 60 })])
                    )
                    GrowthChart(entries: growth, baby: baby, metric: useMetric)
                        .id("growth")
                }
                .padding()
            }
            .onAppear { if DesignPreview.scrollTarget == "growth" { DesignPreview.scroll(proxy) { "growth" } } }
            }
            .background(JungleBackground())
            .overlay {
                if isLoading && entries.isEmpty { ProgressView() }
            }
            .navigationTitle("Trends")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingReport = true } label: {
                        Label("Doctor report", systemImage: "doc.richtext")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { BabySwitcher() }
            }
            .sheet(isPresented: $showingReport) {
                ReportView(baby: baby)
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
            growth = try await EntryRepository.fetchGrowth(babyID: baby.babyID)
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
    var animal: String = "🌿"
    /// One color per series, in order.
    var colors: [Color] = [ChartPalette.first, ChartPalette.second]
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
                Text("\(animal) \(title)").font(.headline).foregroundStyle(Theme.canopy)
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
                .chartForegroundStyleScale(domain: seriesNames, range: Array(colors.prefix(max(1, seriesNames.count))))
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
        .jungleCard(padding: 16)
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

/// Weight, length or head size over time, drawn over the WHO percentile curves.
struct GrowthChart: View {
    let entries: [LogEntry]
    let baby: Baby
    let metric: Bool

    @State private var measure: GrowthMeasure = .weight
    @State private var selectedDate: Date?

    private static let curves: [(name: String, z: Double)] = [
        ("3rd", -1.881), ("15th", -1.036), ("50th", 0), ("85th", 1.036), ("97th", 1.881),
    ]

    private struct Point: Identifiable {
        let entry: LogEntry
        let value: Double  // kg or cm
        var id: String { entry.id ?? "\(entry.timestamp.timeIntervalSince1970)" }
    }

    private struct CurvePoint: Identifiable {
        let name: String
        let date: Date
        let value: Double
        var id: String { "\(name)-\(date.timeIntervalSince1970)" }
    }

    private func standardValue(_ entry: LogEntry) -> Double? {
        switch measure {
        case .weight: return entry.weightGrams.map { $0 / 1000 }
        case .length: return entry.lengthCm
        case .head: return entry.headCm
        }
    }

    /// kg or cm in the units being shown.
    private func shown(_ value: Double) -> Double {
        switch measure {
        case .weight: return metric ? value : value * 1000 / Units.gramsPerPound
        case .length, .head: return metric ? value : value / Units.cmPerInch
        }
    }

    private func text(_ value: Double) -> String {
        measure == .weight ? Units.weight(value * 1000, metric: metric) : Units.length(value, metric: metric)
    }

    private var unitLabel: String {
        measure == .weight ? (metric ? "kg" : "lb") : (metric ? "cm" : "in")
    }

    private var points: [Point] {
        entries
            .sorted { $0.timestamp < $1.timestamp }
            .compactMap { entry in standardValue(entry).map { Point(entry: entry, value: $0) } }
    }

    private var selected: Point? {
        guard let selectedDate else { return nil }
        return points.min { abs($0.entry.timestamp.timeIntervalSince(selectedDate)) < abs($1.entry.timestamp.timeIntervalSince(selectedDate)) }
    }

    private var curvePoints: [CurvePoint] {
        guard let sex = baby.sex else { return [] }
        let start = baby.birthDate
        let end = Date()
        guard start < end else { return [] }
        let step = max(1, (end.timeIntervalSince(start) / 86_400 / 40).rounded())
        var result: [CurvePoint] = []
        var date = start
        while date <= end {
            let age = GrowthStandards.ageDays(birthDate: baby.birthDate, on: date)
            if let lms = GrowthStandards.lms(measure, sex: sex, ageDays: age) {
                for curve in Self.curves {
                    result.append(CurvePoint(name: curve.name, date: date, value: shown(lms.value(z: curve.z))))
                }
            }
            date = date.addingTimeInterval(step * 86_400)
        }
        return result
    }

    private func percentileText(_ point: Point) -> String? {
        guard let sex = baby.sex,
              let p = GrowthStandards.percentile(measure, sex: sex, birthDate: baby.birthDate, on: point.entry.timestamp, value: point.value)
        else { return nil }
        return "\(GrowthStandards.ordinal(p)) percentile"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(Theme.weightAnimal) Growth").font(.headline).foregroundStyle(Theme.canopy)
                Text(unitLabel).font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            Picker("Measurement", selection: $measure) {
                ForEach(GrowthMeasure.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            let points = self.points
            if let point = selected ?? points.last {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(text(point.value)).font(.system(.title2, design: .rounded).weight(.heavy))
                        Text(point.entry.timestamp.formatted(.dateTime.month(.abbreviated).day().year()))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let percentile = percentileText(point) {
                        Text(percentile)
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Theme.weight.opacity(0.15), in: Capsule())
                            .foregroundStyle(Theme.weight)
                    }
                }
                if let index = points.firstIndex(where: { $0.id == point.id }), index > 0 {
                    HStack(spacing: 16) {
                        WeightChange(title: "Since previous", from: points[index - 1].value, to: point.value)
                        if index > 1 {
                            WeightChange(title: "Since first", from: points[0].value, to: point.value)
                        }
                    }
                }
            }

            if points.isEmpty {
                Text("Log a \(measure.label.lowercased()) to see growth over time.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                Chart {
                    ForEach(curvePoints) { curve in
                        LineMark(x: .value("Date", curve.date), y: .value("WHO", curve.value), series: .value("Curve", curve.name))
                            .lineStyle(StrokeStyle(lineWidth: curve.name == "50th" ? 1.5 : 1, dash: [4, 4]))
                            .foregroundStyle(Color.secondary.opacity(curve.name == "50th" ? 0.6 : 0.35))
                    }
                    ForEach(points) { point in
                        LineMark(x: .value("Date", point.entry.timestamp), y: .value(measure.label, shown(point.value)), series: .value("Curve", "Baby"))
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                            .foregroundStyle(Theme.weight)
                        PointMark(x: .value("Date", point.entry.timestamp), y: .value(measure.label, shown(point.value)))
                            .symbolSize(70)
                            .foregroundStyle(Theme.weight)
                    }
                    if let selected {
                        RuleMark(x: .value("Selected", selected.entry.timestamp))
                            .foregroundStyle(.secondary.opacity(0.4))
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXSelection(value: $selectedDate)
                .frame(height: 200)
            }

            if baby.sex == nil {
                Text("Set boy or girl in \(baby.name)'s profile (Family tab) to compare with the WHO growth curves.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if !curvePoints.isEmpty {
                Text("Dashed lines are the WHO 3rd, 15th, 50th, 85th and 97th percentiles.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .jungleCard(padding: 16)
    }
}

/// Percent gained or lost between two weigh-ins.
struct WeightChange: View {
    let title: String
    let from: Double?
    let to: Double?

    private var percent: Double? {
        guard let from, let to, from > 0 else { return nil }
        return (to - from) / from * 100
    }

    var body: some View {
        if let percent {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Label(text(percent), systemImage: symbol(percent))
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    private func text(_ percent: Double) -> String {
        let amount = String(format: "%.1f%%", abs(percent))
        if amount == "0.0%" { return "No change" }
        return percent > 0 ? "Gained \(amount)" : "Lost \(amount)"
    }

    private func symbol(_ percent: Double) -> String {
        if abs(percent) < 0.05 { return "equal.circle" }
        return percent > 0 ? "arrow.up.right.circle" : "arrow.down.right.circle"
    }
}
