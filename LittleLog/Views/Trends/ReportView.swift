import SwiftUI
import PDFKit

/// Builds a short PDF for the pediatrician: daily averages, a day-by-day table,
/// growth with WHO percentiles, and milestones.
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
                    Text("Includes daily feeds, tummy time and diapers, growth with WHO percentiles, and milestones. Share it by email, Messages or AirDrop, or print it.")
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
                        PDFPreview(url: pdfURL)
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
        } catch {
            errorMessage = "Couldn't create the report: \(error.localizedDescription)"
        }
    }
}

struct PDFPreview: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .secondarySystemBackground
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url { view.document = PDFDocument(url: url) }
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

enum ReportPDF {
    static let pageSize = CGSize(width: 612, height: 792) // US Letter
    static let rowsPerPage = 30

    @MainActor
    static func render(_ data: ReportData) throws -> URL {
        let safeName = data.baby.name.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeName) report.pdf")
        var box = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }

        var pages: [AnyView] = [AnyView(ReportSummaryPage(data: data))]
        let chunks = stride(from: 0, to: data.days.count, by: rowsPerPage).map {
            Array(data.days[$0..<min($0 + rowsPerPage, data.days.count)])
        }
        for (index, chunk) in chunks.enumerated() {
            pages.append(AnyView(ReportDaysPage(data: data, days: chunk, part: index + 1, of: chunks.count)))
        }

        for (number, page) in pages.enumerated() {
            let view = page
                .frame(width: pageSize.width, height: pageSize.height, alignment: .top)
                .overlay(alignment: .bottom) {
                    Text("Little Log · page \(number + 1) of \(pages.count)")
                        .font(.system(size: 8))
                        .foregroundStyle(.gray)
                        .padding(.bottom, 18)
                }
                .background(Color.white)
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
}

private struct ReportSummaryPage: View {
    let data: ReportData

    private var df: Date.FormatStyle { .dateTime.month(.abbreviated).day().year() }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(data.baby.name)'s care report").font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("\(data.start.formatted(df)) to \(data.end.formatted(df))").font(.system(size: 11))
                    Text(details).font(.system(size: 10)).foregroundStyle(.gray)
                }
                Spacer()
                Text("🐘").font(.system(size: 34))
            }
            Divider()

            sectionTitle("Daily averages")
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 5) {
                row("Feeds", String(format: "%.1f per day", Double(data.total.feedCount) / data.dayCount))
                if data.total.breastSeconds > 0 {
                    row("Breastfeeding", "\(Units.duration(Int(Double(data.total.breastSeconds) / data.dayCount))) per day (left \(Units.duration(data.total.breastLeftSeconds)), right \(Units.duration(data.total.breastRightSeconds)) total)")
                }
                if data.total.bottleML > 0 {
                    row("Bottle", "\(Units.volume(data.total.bottleML / data.dayCount, metric: data.metric)) per day (formula \(Units.volume(data.total.formulaML, metric: data.metric)), breast milk \(Units.volume(data.total.breastMilkML, metric: data.metric)) total)")
                }
                if data.total.pumpedML > 0 {
                    row("Pumped", "\(Units.volume(data.total.pumpedML / data.dayCount, metric: data.metric)) per day")
                }
                if data.total.tummySeconds > 0 {
                    row("Tummy time", "\(Units.duration(Int(Double(data.total.tummySeconds) / data.dayCount))) per day")
                }
                if data.total.sleepSeconds > 0 {
                    row("Sleep", "\(Units.duration(Int(Double(data.total.sleepSeconds) / data.dayCount))) per day")
                }
                row("Wet diapers", String(format: "%.1f per day", Double(data.total.wetCount) / data.dayCount))
                row("Dirty diapers", String(format: "%.1f per day", Double(data.total.dirtyCount) / data.dayCount))
            }
            .font(.system(size: 11))

            sectionTitle("Growth")
            if data.growth.isEmpty {
                Text("No measurements logged yet.").font(.system(size: 11)).foregroundStyle(.gray)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 4) {
                    GridRow {
                        Text("Date"); Text("Weight"); Text("Length"); Text("Head")
                    }
                    .font(.system(size: 10, weight: .semibold))
                    ForEach(Array(data.growth.suffix(14).enumerated()), id: \.offset) { _, entry in
                        GridRow {
                            Text(entry.timestamp.formatted(df))
                            Text(cell(entry.weightGrams.map { Units.weight($0, metric: data.metric) },
                                      entry.weightGrams.map { data.percentile(.weight, value: $0 / 1000, on: entry.timestamp) }))
                            Text(cell(entry.lengthCm.map { Units.length($0, metric: data.metric) },
                                      entry.lengthCm.map { data.percentile(.length, value: $0, on: entry.timestamp) }))
                            Text(cell(entry.headCm.map { Units.length($0, metric: data.metric) },
                                      entry.headCm.map { data.percentile(.head, value: $0, on: entry.timestamp) }))
                        }
                        .font(.system(size: 10))
                    }
                }
                if data.baby.sex != nil {
                    Text("Percentiles are from the WHO Child Growth Standards.").font(.system(size: 8)).foregroundStyle(.gray)
                }
            }

            sectionTitle("Milestones")
            if data.milestones.isEmpty {
                Text("None logged in this period.").font(.system(size: 11)).foregroundStyle(.gray)
            } else {
                ForEach(Array(data.milestones.prefix(12).enumerated()), id: \.offset) { _, milestone in
                    Text("\(milestone.timestamp.formatted(df)): \(milestone.displayTitle)").font(.system(size: 11))
                }
            }
            Spacer()
        }
        .padding(40)
        .foregroundStyle(.black)
    }

    private var details: String {
        var parts = ["Born \(data.baby.birthDate.formatted(df))", data.baby.ageDescription]
        if let sex = data.baby.sex { parts.append(sex.label) }
        parts.append("Created \(data.created.formatted(df))")
        return parts.joined(separator: " · ")
    }

    private func cell(_ value: String?, _ percentile: String?) -> String {
        guard let value else { return "—" }
        guard let percentile, !percentile.isEmpty else { return value }
        return "\(value) (\(percentile))"
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.system(size: 13, weight: .bold)).padding(.top, 4)
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).fontWeight(.semibold)
            Text(value)
        }
    }
}

private struct ReportDaysPage: View {
    let data: ReportData
    let days: [ReportData.Day]
    let part: Int
    let of: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Day by day\(of > 1 ? " (\(part) of \(of))" : "")").font(.system(size: 15, weight: .bold))
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
                GridRow {
                    Text("Date"); Text("Feeds"); Text("Breast"); Text("Bottle"); Text("Pumped"); Text("Tummy"); Text("Wet"); Text("Dirty")
                }
                .font(.system(size: 9, weight: .semibold))
                Divider().gridCellUnsizedAxes(.horizontal)
                ForEach(days) { day in
                    let s = day.summary
                    GridRow {
                        Text(day.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                        Text("\(s.feedCount)")
                        Text(s.breastSeconds > 0 ? Units.duration(s.breastSeconds) : "—")
                        Text(s.bottleML > 0 ? Units.volume(s.bottleML, metric: data.metric) : "—")
                        Text(s.pumpedML > 0 ? Units.volume(s.pumpedML, metric: data.metric) : "—")
                        Text(s.tummySeconds > 0 ? Units.duration(s.tummySeconds) : "—")
                        Text("\(s.wetCount)")
                        Text("\(s.dirtyCount)")
                    }
                    .font(.system(size: 9))
                }
            }
            Spacer()
        }
        .padding(40)
        .foregroundStyle(.black)
    }
}
