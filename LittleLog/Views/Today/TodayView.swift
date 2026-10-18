import SwiftUI
import Combine

struct TodayView: View {
    let baby: Baby

    @AppStorage("useMetric") private var useMetric = false
    @State private var day = Calendar.current.startOfDay(for: Date())
    @State private var dayEntries = EntriesListener()
    @State private var recent = EntriesListener()
    @State private var sheet: EntrySheet?

    private var calendar: Calendar { Calendar.current }
    private var isToday: Bool { calendar.isDateInToday(day) }
    private var dayEnd: Date { calendar.date(byAdding: .day, value: 1, to: day) ?? day }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DayPicker(day: $day)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                if isToday {
                    Section {
                        SinceLastView(entries: recent.entries)
                    }
                }

                Section("Daily report") {
                    DailyReportGrid(summary: DaySummary(entries: dayEntries.entries), metric: useMetric)
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                }

                Section("Log") {
                    QuickAddGrid { template in sheet = .new(template) }
                        .listRowInsets(EdgeInsets(top: 12, leading: 8, bottom: 12, trailing: 8))
                }

                Section(dayEntries.entries.isEmpty ? "Timeline" : "Timeline · \(dayEntries.entries.count)") {
                    if dayEntries.hasLoaded && dayEntries.entries.isEmpty {
                        Text(isToday ? "Nothing logged yet today." : "Nothing logged this day.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(dayEntries.entries) { entry in
                        Button {
                            sheet = .edit(entry)
                        } label: {
                            EntryRow(entry: entry, metric: useMetric)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button(role: .destructive) {
                                EntryRepository.delete(entry, babyID: baby.babyID)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .listSectionSpacing(.compact)
            .navigationTitle(baby.name)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text(baby.ageDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .topBarTrailing) { BabySwitcher() }
            }
            .sheet(item: $sheet) { sheet in
                EntryEditor(babyID: baby.babyID, sheet: sheet, defaultDate: defaultEntryDate(for: day))
            }
            .task(id: "\(baby.babyID)|\(day.timeIntervalSince1970)") {
                dayEntries.listen(babyID: baby.babyID, from: day, to: dayEnd)
            }
            .task(id: baby.babyID) {
                let since = calendar.date(byAdding: .day, value: -3, to: Date()) ?? Date()
                recent.listen(babyID: baby.babyID, from: since)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                // Roll over to the new day at midnight if we were showing "today".
                if !isToday, calendar.isDate(day, inSameDayAs: Date().addingTimeInterval(-86_400)) {
                    day = calendar.startOfDay(for: Date())
                }
            }
        }
    }
}

struct DayPicker: View {
    @Binding var day: Date
    private var calendar: Calendar { Calendar.current }

    private var label: String {
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    var body: some View {
        HStack {
            Button { shift(-1) } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 36)
            }
            Spacer()
            VStack(spacing: 2) {
                Text(label).font(.headline)
                if !calendar.isDateInToday(day) {
                    Button("Jump to today") { day = calendar.startOfDay(for: Date()) }
                        .font(.caption)
                }
            }
            Spacer()
            Button { shift(1) } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 36)
            }
            .disabled(calendar.isDateInToday(day))
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 4)
    }

    private func shift(_ days: Int) {
        if let next = calendar.date(byAdding: .day, value: days, to: day) { day = next }
    }
}

/// "Last feed 2h 10m ago", "Next side: Left", "Last diaper 45m ago".
struct SinceLastView: View {
    let entries: [LogEntry]

    var body: some View {
        let lastFeed = entries.first { $0.isFeeding }
        let lastBreast = entries.first { $0.kind == .feed && $0.breastLastSide != nil }
        let lastDiaper = entries.first { $0.kind == .diaper }
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(spacing: 0) {
                stat(title: "Last feed", value: lastFeed.map { Units.ago($0.timestamp, now: context.date) } ?? "—", tint: Theme.feed)
                Divider()
                stat(title: "Next side", value: lastBreast?.breastLastSide.map { $0 == .left ? "Right" : "Left" } ?? "—", tint: Theme.feed)
                Divider()
                stat(title: "Last diaper", value: lastDiaper.map { Units.ago($0.timestamp, now: context.date) } ?? "—", tint: Theme.diaper)
            }
        }
        .padding(.vertical, 4)
    }

    private func stat(title: String, value: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}

struct DailyReportGrid: View {
    let summary: DaySummary
    let metric: Bool

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ReportTile(
                title: "Feeds", value: "\(summary.feedCount)", symbol: "heart.fill", tint: Theme.feed,
                lines: feedLines
            )
            ReportTile(
                title: "Diapers", value: "\(summary.diaperCount)", symbol: "humidity.fill", tint: Theme.diaper,
                lines: ["\(summary.wetCount) wet · \(summary.dirtyCount) dirty"]
            )
            if summary.pumpCount > 0 {
                ReportTile(
                    title: "Pumped", value: Units.volume(summary.pumpedML, metric: metric), symbol: "drop.circle", tint: Theme.pump,
                    lines: ["\(summary.pumpCount) session\(summary.pumpCount == 1 ? "" : "s") · \(Units.duration(summary.pumpSeconds))"]
                )
            }
            if summary.dropOff != nil || summary.pickUp != nil {
                ReportTile(
                    title: "Daycare", value: daycareValue, symbol: "building.2.fill", tint: Theme.daycare,
                    lines: daycareLines
                )
            }
            if let grams = summary.latestWeightGrams {
                ReportTile(title: "Weight", value: Units.weight(grams, metric: metric), symbol: "scalemass.fill", tint: Theme.weight, lines: [])
            }
            ForEach(summary.milestones, id: \.self) { milestone in
                ReportTile(title: "Milestone", value: milestone, symbol: "star.fill", tint: Theme.milestone, lines: [])
            }
        }
    }

    private var feedLines: [String] {
        var lines: [String] = []
        if summary.breastSeconds > 0 {
            lines.append("Breast \(Units.duration(summary.breastSeconds)) (L \(Units.duration(summary.breastLeftSeconds)) · R \(Units.duration(summary.breastRightSeconds)))")
        }
        if summary.bottleML > 0 {
            lines.append("Bottle \(Units.volume(summary.bottleML, metric: metric))")
        }
        return lines.isEmpty ? ["None yet"] : lines
    }

    private var daycareValue: String {
        if summary.pickUp != nil { return "Picked up" }
        return "At daycare"
    }

    private var daycareLines: [String] {
        var lines: [String] = []
        if let d = summary.dropOff { lines.append("Drop-off \(d.formatted(date: .omitted, time: .shortened))") }
        if let p = summary.pickUp { lines.append("Pick-up \(p.formatted(date: .omitted, time: .shortened))") }
        return lines
    }
}

struct ReportTile: View {
    let title: String
    let value: String
    let symbol: String
    let tint: Color
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.title2.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
        .padding(12)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct QuickAddGrid: View {
    let onSelect: (EntryTemplate) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 14) {
            ForEach(EntryTemplate.allCases) { template in
                Button {
                    onSelect(template)
                } label: {
                    VStack(spacing: 6) {
                        IconBadge(symbol: template.symbol, tint: template.tint, size: 48)
                        Text(template.label)
                            .font(.caption)
                            .foregroundStyle(.primary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct EntryRow: View {
    let entry: LogEntry
    let metric: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconBadge(symbol: entry.symbol, tint: entry.tint)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(entry.displayTitle).font(.body.weight(.semibold))
                    Spacer()
                    Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                let detail = entry.detailText(metric: entry.metric ?? metric)
                if !detail.isEmpty {
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                }
                if let notes = entry.notes {
                    Text(notes).font(.footnote).foregroundStyle(.secondary).italic()
                }
                Text(entry.authorName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }
}
