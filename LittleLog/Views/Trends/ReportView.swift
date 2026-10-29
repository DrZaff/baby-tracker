import SwiftUI
import PDFKit

/// Builds a short PDF for the pediatrician: daily averages, milestones, and a feeding and diaper log for the chosen dates.
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
    @State private var span: Span
    @State private var customStart: Date
    @State private var customEnd: Date
    @State private var pdfURL: URL?
    /// Changes on every new report, so the preview reloads even when the file name is the same.
    @State private var version = UUID()
    @State private var isWorking = false
    @State private var errorMessage: String?

    init(baby: Baby, span: Span = .twoWeeks,
         customStart: Date = Calendar.current.date(byAdding: .day, value: -13, to: Date()) ?? Date(),
         customEnd: Date = Date()) {
        self.baby = baby
        _span = State(initialValue: span)
        _customStart = State(initialValue: customStart)
        _customEnd = State(initialValue: customEnd)
    }

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
                    Text("Covers \(range.start.formatted(.dateTime.month(.abbreviated).day())) to \(range.end.formatted(.dateTime.month(.abbreviated).day().year())): daily averages, milestones, and a log of every feed and diaper. Share it by email, Messages or AirDrop, or print it.")
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
                        PDFPreview(url: pdfURL, version: version, page: DesignPreview.scrollTarget == "log" ? 1 : 0)
                            .frame(height: DesignPreview.isOn ? 600 : 460)
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
            .task { if DesignPreview.isOn { await build() } }
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
    var page = 0

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
        let document = PDFDocument(url: url)
        view.document = document
        if page > 0, let target = document?.page(at: page) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { view.go(to: target) }
        }
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
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: end) ?? end
        let entries = entries.filter { $0.timestamp >= start && $0.timestamp < endExclusive }
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

/// Fixed light colors from the chosen theme for the printed report, so it looks the same whatever mode the phone is in.
enum ReportColors {
    static func hex(_ value: UInt32) -> Color {
        Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
    private static var palette: ThemePalette { AppTheme.current.palette }
    static var canopy: Color { hex(palette.canopy.light) }
    static var leaf: Color { hex(palette.leaf.light) }
    static var lime: Color { hex(palette.lime.light) }
    static var sunshine: Color { hex(palette.sunshine.light) }
    static var mango: Color { hex(palette.mango.light) }
    static var hibiscus: Color { hex(palette.hibiscus.light) }
    static var orchid: Color { hex(palette.orchid.light) }
    static var lagoon: Color { hex(palette.lagoon.light) }
    static var river: Color { hex(palette.river.light) }
    static var bark: Color { hex(palette.bark.light) }
    static var sand: Color { hex(palette.backgroundTop.light) }
    static var mint: Color { hex(palette.backgroundBottom.light) }
    static let ink = hex(0x24312A)
    static let muted = hex(0x4F5C54)
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
                    Text("\(Theme.feedAnimal) Little Log · page \(number + 1) of \(pages.count)")
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
            let items = combined(entries)
            rows += items.isEmpty ? [.empty] : items.map { .entry(feed: $0.feed, diaper: $0.diaper) }
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

    /// A diaper changed within this many minutes of a feed shares the feed's row.
    static let sameTimeMinutes = 10.0

    /// Puts each diaper on the same row as a feed logged at about the same time.
    static func combined(_ entries: [LogEntry]) -> [(feed: LogEntry?, diaper: LogEntry?)] {
        var items: [(feed: LogEntry?, diaper: LogEntry?)] = entries.filter { $0.kind == .feed }.map { ($0, nil) }
        for diaper in entries where diaper.kind == .diaper {
            let match = items.indices
                .filter { items[$0].diaper == nil && items[$0].feed != nil }
                .map { ($0, abs(items[$0].feed!.timestamp.timeIntervalSince(diaper.timestamp))) }
                .filter { $0.1 <= sameTimeMinutes * 60 }
                .min { $0.1 < $1.1 }
            if let match {
                items[match.0].diaper = diaper
            } else {
                items.append((nil, diaper))
            }
        }
        func time(_ item: (feed: LogEntry?, diaper: LogEntry?)) -> Date {
            min(item.feed?.timestamp ?? .distantFuture, item.diaper?.timestamp ?? .distantFuture)
        }
        return items.sorted { time($0) < time($1) }
    }
}

enum ReportLogRow {
    case day(ReportData.Day)
    case entry(feed: LogEntry?, diaper: LogEntry?)
    case empty
}

/// Warm sand paper with a few soft leaves in the corners.
private struct ReportPageBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [ReportColors.sand, ReportColors.mint], startPoint: .top, endPoint: .bottom)
            // Same decorations as the app's backgrounds, softened for paper.
            ThemeDecorations(size: ReportPDF.pageSize).opacity(0.7)
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

/// One daily average: a colored animal badge, a clear title, the value and a short detail.
private struct ReportStat: View {
    let title: String
    let value: String
    let detail: String?
    let animal: String
    let tint: Color

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(animal)
                .font(.system(size: 18))
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.22), in: Circle())
                .overlay(Circle().strokeBorder(tint.opacity(0.6), lineWidth: 1))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundStyle(ReportColors.ink)
                Text(value)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(ReportColors.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let detail {
                    Text(detail)
                        .font(.system(size: 8.5, weight: .medium, design: .rounded))
                        .foregroundStyle(ReportColors.muted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 11, bottomLeadingRadius: 11, style: .continuous)
                .fill(tint)
                .frame(width: 5)
        }
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(tint.opacity(0.45), lineWidth: 0.8))
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
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(ReportColors.bark)
                Text(data.baby.name)
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(ReportColors.canopy)
                Text("\(data.start.formatted(df)) to \(data.end.formatted(df))")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(ReportColors.ink)
                Text(details)
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(ReportColors.ink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.92), in: Capsule())
                    .overlay(Capsule().strokeBorder(ReportColors.leaf.opacity(0.35), lineWidth: 0.6))
                    .padding(.top, 3)
            }
            Spacer()
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [ReportColors.lime, ReportColors.leaf.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 58, height: 58)
                Text(Theme.feedAnimal).font(.system(size: 32))
                Text(Theme.decor.accent).font(.system(size: 13)).offset(x: 22, y: -22)
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

            ReportCard(title: "Daily averages", icon: Theme.decor.reportIcon) {
                let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 2)
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ReportStat(title: "Feeds", value: String(format: "%.1f per day", perDay(Double(t.feedCount))), detail: "\(t.feedCount) in total", animal: Theme.feedAnimal, tint: ReportColors.hibiscus)
                    if t.breastSeconds > 0 {
                        ReportStat(title: "Breastfeeding", value: "\(Units.duration(Int(perDay(Double(t.breastSeconds))))) per day",
                                   detail: "Left \(Units.duration(t.breastLeftSeconds)) · right \(Units.duration(t.breastRightSeconds)) total", animal: "🤱", tint: ReportColors.hibiscus)
                    }
                    if t.bottleML > 0 {
                        ReportStat(title: "Bottle", value: "\(Units.volume(perDay(t.bottleML), metric: data.metric)) per day",
                                   detail: "Formula \(Units.volume(t.formulaML, metric: data.metric)) · breast milk \(Units.volume(t.breastMilkML, metric: data.metric)) total", animal: Theme.bottleAnimal, tint: ReportColors.mango)
                    }
                    if t.pumpedML > 0 {
                        ReportStat(title: "Pumped", value: "\(Units.volume(perDay(t.pumpedML), metric: data.metric)) per day", detail: nil, animal: Theme.pumpAnimal, tint: ReportColors.orchid)
                    }
                    ReportStat(title: "Wet diapers", value: String(format: "%.1f per day", perDay(Double(t.wetCount))), detail: "\(t.wetCount) in total", animal: Theme.diaperAnimal, tint: ReportColors.lagoon)
                    ReportStat(title: "Dirty diapers", value: String(format: "%.1f per day", perDay(Double(t.dirtyCount))), detail: "\(t.dirtyCount) in total", animal: "💩", tint: ReportColors.bark)
                    if t.tummySeconds > 0 {
                        ReportStat(title: "Tummy time", value: "\(Units.duration(Int(perDay(Double(t.tummySeconds))))) per day", detail: "\(t.tummyCount) sessions", animal: Theme.tummyAnimal, tint: ReportColors.leaf)
                    }
                    if t.sleepSeconds > 0 {
                        ReportStat(title: "Sleep", value: "\(Units.duration(Int(perDay(Double(t.sleepSeconds))))) per day", detail: nil, animal: Theme.sleepAnimal, tint: ReportColors.river)
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
                Text("\(Theme.feedAnimal) \(Theme.diaperAnimal) ⭐️").font(.system(size: 16))
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
        case .entry(let feed, let diaperEntry):
            let time = feed?.timestamp ?? diaperEntry?.timestamp ?? day0
            HStack(spacing: 0) {
                cell(time.formatted(.dateTime.month(.defaultDigits).day()), 0)
                cell(time.formatted(date: .omitted, time: .shortened), 1)
                cell(feed.map { amount($0) } ?? "—", 2)
                cell(feed.map { feedType($0) } ?? "—", 3)
                cell(diaperEntry.map { diaper($0) } ?? "—", 4)
            }
            .frame(height: 19)
            .background(shaded ? ReportColors.sand.opacity(0.7) : Color.white)
        }
    }

    private var day0: Date { data.start }

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
