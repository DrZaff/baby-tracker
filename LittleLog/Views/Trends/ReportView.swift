import SwiftUI
import PDFKit

/// Builds a short PDF for the pediatrician: daily averages, growth with WHO percentiles,
/// milestones, and a feeding and diaper log for the chosen dates.
struct ReportView: View {
    let baby: Baby

    enum Span: String, CaseIterable, Identifiable {
        case week = "7 days", twoWeeks = "14 days", month = "30 days", custom = "Custom"
        var id: String { rawValue }
        var days: Int? {
            switch self {
            case .week: return 7
            case .twoWeeks: return 14
            case .month: return 30
            case .custom: return nil
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @AppStorage("useMetric") private var useMetric = false
    @State private var span: Span = .twoWeeks
    @State private var customStart = Calendar.current.date(byAdding: .day, value: -13, to: Date()) ?? Date()
    @State private var customEnd = Date()
    @State private var pdfURL: URL?
    /// Changes on every new report, so the preview reloads even when the file name is the same.
    @State private var version = UUID()
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var calendar: Calendar { Calendar.current }

    private var range: (start: Date, end: Date) {
        let today = calendar.startOfDay(for: Date())
        if let days = span.days {
            let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
            return (start, today)
        }
        let start = calendar.startOfDay(for: min(customStart, customEnd))
        return (start, calendar.startOfDay(for: max(customStart, customEnd)))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Covering", selection: $span) {
                        ForEach(Span.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if span == .custom {
                        DatePicker("From", selection: $customStart, in: baby.birthDate...Date(), displayedComponents: .date)
                        DatePicker("To", selection: $customEnd, in: baby.birthDate...Date(), displayedComponents: .date)
                    }
                } header: {
                    JungleHeader(title: "Report for \(baby.name)", icon: "🩺")
                } footer: {
                    Text("Covers \(range.start.formatted(.dateTime.month(.abbreviated).day())) to \(range.end.formatted(.dateTime.month(.abbreviated).day().year())): daily averages, growth with WHO percentiles, milestones, and a log of every feed and diaper. Share it by email, Messages or AirDrop, or print it.")
                }

                Section {
                    Button {
                        Task { await build() }
                    } label: {
                        HStack {
                            if isWorking { ProgressView() }
                            Text(pdfURL == nil ? "Create report" : "Create again")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(isWorking)
                    if let pdfURL {
                        ShareLink(item: pdfURL) {
                            Label("Share or print PDF", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    if let errorMessage {
                        Text(errorMessage).font(.footnote).foregroundStyle(.red)
                    }
                }

                if let pdfURL {
                    Section("Preview") {
                        PDFPreview(url: pdfURL, version: version)
                            .frame(height: 460)
                            .listRowInsets(EdgeInsets())
                    }
                }
            }
            .jungleBackground()
            .navigationTitle("Doctor report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .onChange(of: span) { pdfURL = nil }
            .onChange(of: customStart) { pdfURL = nil }
            .onChange(of: customEnd) { pdfURL = nil }
        }
    }

    private func build() async {
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil
        let range = self.range
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: range.end) ?? range.end
        do {
            let entries = try await EntryRepository.fetch(babyID: baby.babyID, from: range.start, to: endExclusive)
            let growth = try await EntryRepository.fetchGrowth(babyID: baby.babyID)
            let data = ReportData(baby: baby, start: range.start, end: range.end, entries: entries, growth: growth, metric: useMetric)
            pdfURL = try ReportPDF.render(data)
            version = UUID()
        } catch {
            errorMessage = "Couldn't create the report: \(error.localizedDescription)"
        }
    }
}

struct PDFPreview: UIViewRepresentable {
    let url: URL
    let version: UUID

    final class Coordinator { var shown: UUID? }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .secondarySystemBackground
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        guard context.coordinator.shown != version else { return }
        context.coordinator.shown = version
        view.document = PDFDocument(url: url)
    }
}

/// Everything the report shows, computed once.
struct ReportData {
    struct Day: Identifiable {
        let date: Date
        let summary: DaySummary
        var id: Date { date }
    }

    let baby: Baby
    let start: Date
    let end: Date
    let days: [Day]
    let total: DaySummary
    let growth: [LogEntry]
    let milestones: [LogEntry]
    /// Every feed, pump and diaper in the period, oldest first.
    let log: [LogEntry]
    let metric: Bool
    let created = Date()

    init(baby: Baby, start: Date, end: Date, entries: [LogEntry], growth: [LogEntry], metric: Bool) {
        let calendar = Calendar.current
        self.baby = baby
        self.start = start
        self.end = end
        self.metric = metric
        self.growth = growth
        self.milestones = entries.filter { $0.kind == .milestone }.sorted { $0.timestamp < $1.timestamp }
        self.total = DaySummary(entries: entries)
        self.log = entries
            .filter { ($0.kind == .feed && ($0.isFeeding || $0.hasPump)) || $0.kind == .diaper }
            .sorted { $0.timestamp < $1.timestamp }
        var days: [Day] = []
        var cursor = start
        while cursor <= end {
            let next = calendar.date(byAdding: .day, value: 1, to: cursor) ?? end.addingTimeInterval(86_400)
            days.append(Day(date: cursor, summary: DaySummary(entries: entries.filter { $0.timestamp >= cursor && $0.timestamp < next })))
            cursor = next
        }
        self.days = days
    }

    var dayCount: Double { Double(max(1, days.count)) }

    func percentile(_ measure: GrowthMeasure, value: Double, on date: Date) -> String {
        guard let sex = baby.sex,
              let p = GrowthStandards.percentile(measure, sex: sex, birthDate: baby.birthDate, on: date, value: value)
        else { return "" }
        return GrowthStandards.ordinal(p)
    }
}

/// Fixed light jungle colors for the printed report, so it looks the same whatever mode the phone is in.
enum ReportColors {
    static func hex(_ value: UInt32) -> Color {
        Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
    static let canopy = hex(0x2E6B4A)
    static let leaf = hex(0x5DB563)
    static let lime = hex(0xB8E07E)
    static let sunshine = hex(0xF7B731)
    static let mango = hex(0xF28C38)
    static let hibiscus = hex(0xE8566C)
    static let orchid = hex(0x9B6BD3)
    static let lagoon = hex(0x23A6A6)
    static let river = hex(0x3F7FD0)
    static let bark = hex(0x6B4A2E)
    static let sand = hex(0xFFF7E6)
    static let mint = hex(0xEAF6DF)
    static let ink = hex(0x24312A)
    static let muted = hex(0x6F7D74)
}

enum ReportPDF {
    static let pageSize = CGSize(width: 612, height: 792) // US Letter
    static let logRowsPerPage = 26

    @MainActor
    static func render(_ data: ReportData) throws -> URL {
        let safeName = data.baby.name.replacingOccurrences(of: "/", with: "-")
        let dates = "\(data.start.formatted(.dateTime.month(.abbreviated).day())) to \(data.end.formatted(.dateTime.month(.abbreviated).day()))"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeName) report, \(dates).pdf")
        try? FileManager.default.removeItem(at: url)
        var box = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }

        var pages: [AnyView] = [AnyView(ReportSummaryPage(data: data))]
        let chunks = logPages(data)
        for (index, rows) in chunks.enumerated() {
            pages.append(AnyView(ReportLogPage(data: data, rows: rows, part: index + 1, of: chunks.count)))
        }

        for (number, page) in pages.enumerated() {
            let view = page
                .frame(width: pageSize.width, height: pageSize.height, alignment: .top)
                .background(ReportPageBackground())
                .overlay(alignment: .bottom) {
                    Text("🐘 Little Log · page \(number + 1) of \(pages.count)")
                        .font(.system(size: 8, design: .rounded))
                        .foregroundStyle(ReportColors.muted)
                        .padding(.bottom, 16)
                }
                .environment(\.colorScheme, .light)
            let renderer = ImageRenderer(content: view)
            renderer.proposedSize = ProposedViewSize(pageSize)
            renderer.render { _, draw in
                context.beginPDFPage(nil)
                draw(context)
                context.endPDFPage()
            }
        }
        context.closePDF()
        return url
    }

    /// The log as rows: a heading row for each day, then that day's feeds and diapers.
    /// A day never starts at the bottom of a page.
    static func logPages(_ data: ReportData) -> [[ReportLogRow]] {
        let calendar = Calendar.current
        var pages: [[ReportLogRow]] = []
        var page: [ReportLogRow] = []
        for day in data.days {
            let next = calendar.date(byAdding: .day, value: 1, to: day.date) ?? day.date
            let entries = data.log.filter { $0.timestamp >= day.date && $0.timestamp < next }
            var rows: [ReportLogRow] = [.day(day)]
            rows += entries.isEmpty ? [.empty] : entries.map { .entry($0) }
            for (index, row) in rows.enumerated() {
                let needsRoom = index == 0 ? 3 : 1
                if page.count + needsRoom > logRowsPerPage {
                    pages.append(page)
                    page = index == 0 ? [] : [.day(day)]
                }
                page.append(row)
            }
        }
        if !page.isEmpty { pages.append(page) }
        return pages
    }
}

enum ReportLogRow {
    case day(ReportData.Day)
    case entry(LogEntry)
    case empty
}

/// Warm sand paper with a few soft leaves in the corners.
private struct ReportPageBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [ReportColors.sand, ReportColors.mint], startPoint: .top, endPoint: .bottom)
            Leaf(color: ReportColors.leaf.opacity(0.16), width: 120, angle: 125).position(x: 6, y: 6)
            Leaf(color: ReportColors.lime.opacity(0.28), width: 96, angle: -130).position(x: 606, y: 10)
            Leaf(color: ReportColors.leaf.opacity(0.12), width: 130, angle: 35).position(x: 0, y: 760)
            Leaf(color: ReportColors.lime.opacity(0.22), width: 110, angle: -40).position(x: 612, y: 770)
        }
    }
}

/// A white rounded card with a colored title, like the app's sections.
private struct ReportCard<Content: View>: View {
    let title: String
    let icon: String
    var tint: Color = ReportColors.canopy
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Text(icon)
                Text(title)
            }
            .font(.system(size: 13, weight: .heavy, design: .rounded))
            .foregroundStyle(tint)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(ReportColors.leaf.opacity(0.25), lineWidth: 0.8))
    }
}

/// A small colored tile, like the daily report tiles in the app.
private struct ReportStat: View {
    let title: String
    let value: String
    let detail: String?
    let animal: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 7.5, weight: .heavy, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(ReportColors.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let detail {
                Text(detail)
                    .font(.system(size: 7.5, design: .rounded))
                    .foregroundStyle(ReportColors.muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
        .background(alignment: .topTrailing) {
            Text(animal).font(.system(size: 15)).padding(6)
        }
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(LinearGradient(colors: [tint.opacity(0.2), tint.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .background(Color.white, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(tint.opacity(0.3), lineWidth: 0.8))
    }
}

private struct ReportHeader: View {
    let data: ReportData
    let subtitle: String

    private var df: Date.FormatStyle { .dateTime.month(.abbreviated).day().year() }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(subtitle)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(ReportColors.bark)
                Text(data.baby.name)
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(ReportColors.canopy)
                Text("\(data.start.formatted(df)) to \(data.end.formatted(df))")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(ReportColors.ink)
                Text(details)
                    .font(.system(size: 8.5, design: .rounded))
                    .foregroundStyle(ReportColors.muted)
            }
            Spacer()
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [ReportColors.lime, ReportColors.leaf.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 58, height: 58)
                Text("🐘").font(.system(size: 32))
                Text("🌺").font(.system(size: 13)).offset(x: 22, y: -22)
            }
        }
    }

    private var details: String {
        var parts = ["Born \(data.baby.birthDate.formatted(df))", data.baby.ageDescription]
        if let sex = data.baby.sex { parts.append(sex.label) }
        parts.append("Report created \(data.created.formatted(df))")
        return parts.joined(separator: " · ")
    }
}

private struct ReportSummaryPage: View {
    let data: ReportData

    private var df: Date.FormatStyle { .dateTime.month(.abbreviated).day().year() }
    private var t: DaySummary { data.total }
    private func perDay(_ value: Double) -> Double { value / data.dayCount }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ReportHeader(data: data, subtitle: "🩺 Care report for the pediatrician")

            ReportCard(title: "Daily averages", icon: "🌿") {
                let columns = Array(repeating: GridItem(.flexible(), spacing: 7), count: 4)
                LazyVGrid(columns: columns, alignment: .leading, spacing: 7) {
                    ReportStat(title: "Feeds", value: String(format: "%.1f / day", perDay(Double(t.feedCount))), detail: "\(t.feedCount) in total", animal: Theme.feedAnimal, tint: ReportColors.hibiscus)
                    if t.breastSeconds > 0 {
                        ReportStat(title: "Breastfeeding", value: "\(Units.duration(Int(perDay(Double(t.breastSeconds))))) / day",
                                   detail: "Left \(Units.duration(t.breastLeftSeconds)) · right \(Units.duration(t.breastRightSeconds)) total", animal: "🤱", tint: ReportColors.hibiscus)
                    }
                    if t.bottleML > 0 {
                        ReportStat(title: "Bottle", value: "\(Units.volume(perDay(t.bottleML), metric: data.metric)) / day",
                                   detail: "Formula \(Units.volume(t.formulaML, metric: data.metric)) · breast milk \(Units.volume(t.breastMilkML, metric: data.metric)) total", animal: Theme.bottleAnimal, tint: ReportColors.mango)
                    }
                    if t.pumpedML > 0 {
                        ReportStat(title: "Pumped", value: "\(Units.volume(perDay(t.pumpedML), metric: data.metric)) / day", detail: nil, animal: Theme.pumpAnimal, tint: ReportColors.orchid)
                    }
                    ReportStat(title: "Wet diapers", value: String(format: "%.1f / day", perDay(Double(t.wetCount))), detail: "\(t.wetCount) in total", animal: Theme.diaperAnimal, tint: ReportColors.lagoon)
                    ReportStat(title: "Dirty diapers", value: String(format: "%.1f / day", perDay(Double(t.dirtyCount))), detail: "\(t.dirtyCount) in total", animal: "💩", tint: ReportColors.bark)
                    if t.tummySeconds > 0 {
                        ReportStat(title: "Tummy time", value: "\(Units.duration(Int(perDay(Double(t.tummySeconds))))) / day", detail: "\(t.tummyCount) sessions", animal: Theme.tummyAnimal, tint: ReportColors.leaf)
                    }
                    if t.sleepSeconds > 0 {
                        ReportStat(title: "Sleep", value: "\(Units.duration(Int(perDay(Double(t.sleepSeconds))))) / day", detail: nil, animal: Theme.sleepAnimal, tint: ReportColors.river)
                    }
                }
            }

            ReportCard(title: "Growth", icon: Theme.weightAnimal, tint: ReportColors.river) {
                if data.growth.isEmpty {
                    Text("No measurements logged yet.").font(.system(size: 10)).foregroundStyle(ReportColors.muted)
                } else {
                    Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                        GridRow {
                            headerCell("Date"); headerCell("Weight"); headerCell("Length"); headerCell("Head")
                        }
                        ForEach(Array(data.growth.suffix(12).enumerated()), id: \.offset) { index, entry in
                            GridRow {
                                bodyCell(entry.timestamp.formatted(df), index)
                                bodyCell(cell(entry.weightGrams.map { Units.weight($0, metric: data.metric) },
                                              entry.weightGrams.map { data.percentile(.weight, value: $0 / 1000, on: entry.timestamp) }), index)
                                bodyCell(cell(entry.lengthCm.map { Units.length($0, metric: data.metric) },
                                              entry.lengthCm.map { data.percentile(.length, value: $0, on: entry.timestamp) }), index)
                                bodyCell(cell(entry.headCm.map { Units.length($0, metric: data.metric) },
                                              entry.headCm.map { data.percentile(.head, value: $0, on: entry.timestamp) }), index)
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    if data.baby.sex != nil {
                        Text("Percentiles in brackets are from the WHO Child Growth Standards.")
                            .font(.system(size: 7.5)).foregroundStyle(ReportColors.muted)
                    }
                }
            }

            ReportCard(title: "Milestones", icon: Theme.milestoneAnimal, tint: ReportColors.mango) {
                if data.milestones.isEmpty {
                    Text("None logged in this period.").font(.system(size: 10)).foregroundStyle(ReportColors.muted)
                } else {
                    ForEach(Array(data.milestones.prefix(10).enumerated()), id: \.offset) { _, milestone in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("⭐️").font(.system(size: 8))
                            Text(milestone.timestamp.formatted(df)).fontWeight(.semibold).foregroundStyle(ReportColors.bark)
                            Text(milestone.displayTitle).foregroundStyle(ReportColors.ink)
                        }
                        .font(.system(size: 10, design: .rounded))
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 36)
        .padding(.top, 34)
    }

    private func headerCell(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .heavy, design: .rounded))
            .foregroundStyle(ReportColors.ink)
            .padding(.vertical, 5)
            .padding(.horizontal, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ReportColors.river.opacity(0.22))
    }

    private func bodyCell(_ text: String, _ index: Int) -> some View {
        Text(text)
            .font(.system(size: 9, design: .rounded))
            .foregroundStyle(ReportColors.ink)
            .padding(.vertical, 4)
            .padding(.horizontal, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(index % 2 == 0 ? Color.white : ReportColors.river.opacity(0.06))
    }

    private func cell(_ value: String?, _ percentile: String?) -> String {
        guard let value else { return "—" }
        guard let percentile, !percentile.isEmpty else { return value }
        return "\(value) (\(percentile))"
    }
}

/// "Feeding and diaper log": every feed and diaper for the chosen dates, grouped by day.
private struct ReportLogPage: View {
    let data: ReportData
    let rows: [ReportLogRow]
    let part: Int
    let of: Int

    private struct Column {
        let title: String
        let tint: Color
        let width: CGFloat
    }

    // Widths add up to the 540pt between the page margins.
    private let columns = [
        Column(title: "DATE", tint: ReportColors.sunshine, width: 82),
        Column(title: "TIME", tint: ReportColors.river, width: 72),
        Column(title: "FEEDING AMOUNT", tint: ReportColors.hibiscus, width: 140),
        Column(title: "FEEDING TYPE", tint: ReportColors.lagoon, width: 136),
        Column(title: "PEE OR POO", tint: ReportColors.mango, width: 110),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Text("🍼").font(.system(size: 26))
                VStack(alignment: .leading, spacing: 0) {
                    Text("Feeding & diaper log")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(ReportColors.canopy)
                    Text("\(data.baby.name) · \(data.start.formatted(.dateTime.month(.abbreviated).day())) to \(data.end.formatted(.dateTime.month(.abbreviated).day().year()))\(of > 1 ? " · part \(part) of \(of)" : "")")
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(ReportColors.muted)
                }
                Spacer()
                Text("🐘 🐒 ⭐️").font(.system(size: 16))
            }

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(columns.indices, id: \.self) { index in
                        Text(columns[index].title)
                            .font(.system(size: 8.5, weight: .heavy, design: .rounded))
                            .foregroundStyle(ReportColors.ink)
                            .multilineTextAlignment(.center)
                            .frame(width: columns[index].width, height: 26)
                            .background(columns[index].tint.opacity(0.45))
                    }
                }
                ForEach(rows.indices, id: \.self) { index in
                    row(rows[index], shaded: index % 2 == 1)
                    Rectangle().fill(ReportColors.bark.opacity(0.18)).frame(height: 0.6)
                }
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(ReportColors.bark.opacity(0.55), lineWidth: 1))
            Spacer()
        }
        .padding(.horizontal, 36)
        .padding(.top, 34)
    }

    @ViewBuilder
    private func row(_ row: ReportLogRow, shaded: Bool) -> some View {
        switch row {
        case .day(let day):
            HStack {
                Text(day.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(ReportColors.canopy)
                Spacer()
                Text(dayTotals(day.summary))
                    .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(ReportColors.bark)
            }
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(ReportColors.lime.opacity(0.35))
        case .empty:
            Text("Nothing logged")
                .font(.system(size: 8.5, design: .rounded))
                .foregroundStyle(ReportColors.muted)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
        case .entry(let entry):
            HStack(spacing: 0) {
                cell(entry.timestamp.formatted(.dateTime.month(.defaultDigits).day()), 0)
                cell(entry.timestamp.formatted(date: .omitted, time: .shortened), 1)
                cell(amount(entry), 2)
                cell(feedType(entry), 3)
                cell(diaper(entry), 4)
            }
            .frame(height: 19)
            .background(shaded ? ReportColors.sand.opacity(0.7) : Color.white)
        }
    }

    private func cell(_ text: String, _ column: Int) -> some View {
        Text(text)
            .font(.system(size: 8.5, design: .rounded))
            .foregroundStyle(text == "—" ? ReportColors.muted.opacity(0.6) : ReportColors.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: columns[column].width)
            .overlay(alignment: .trailing) {
                if column < columns.count - 1 {
                    Rectangle().fill(ReportColors.bark.opacity(0.18)).frame(width: 0.6)
                }
            }
    }

    private func amount(_ e: LogEntry) -> String {
        guard e.kind == .feed else { return "—" }
        var parts: [String] = []
        if e.hasBreast {
            parts.append("L \(Units.duration(e.breastLeftSeconds ?? 0)) · R \(Units.duration(e.breastRightSeconds ?? 0))")
        }
        if let ml = e.bottleML, ml > 0 { parts.append(Units.volume(ml, metric: e.metric ?? data.metric)) }
        if e.isPumpOnly, let ml = e.pumpedML, ml > 0 { parts.append("\(Units.volume(ml, metric: e.metric ?? data.metric)) pumped") }
        return parts.isEmpty ? "—" : parts.joined(separator: " + ")
    }

    private func feedType(_ e: LogEntry) -> String {
        guard e.kind == .feed else { return "—" }
        var parts: [String] = []
        if e.hasBreast { parts.append("Breast") }
        if e.hasBottle {
            switch e.bottleContent ?? .formula {
            case .formula: parts.append("Formula")
            case .breastMilk: parts.append("Bottle, breast milk")
            case .mix: parts.append("Mix")
            }
        }
        if e.isPumpOnly { parts.append("Pumping") }
        return parts.isEmpty ? "—" : parts.joined(separator: " + ")
    }

    private func diaper(_ e: LogEntry) -> String {
        guard e.kind == .diaper else { return "—" }
        switch (e.wet == true, e.dirty == true) {
        case (true, true): return "Pee + poo"
        case (false, true): return "Poo"
        case (true, false): return "Pee"
        default: return "Dry"
        }
    }

    private func dayTotals(_ s: DaySummary) -> String {
        var parts = ["\(s.feedCount) feed\(s.feedCount == 1 ? "" : "s")"]
        if s.bottleML > 0 { parts.append("\(Units.volume(s.bottleML, metric: data.metric)) bottle") }
        if s.breastSeconds > 0 { parts.append("\(Units.duration(s.breastSeconds)) breast") }
        parts.append("\(s.wetCount) wet · \(s.dirtyCount) dirty")
        return parts.joined(separator: " · ")
    }
}
