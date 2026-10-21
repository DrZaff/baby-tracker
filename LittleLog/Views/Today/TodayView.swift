import SwiftUI
import Combine

struct TodayView: View {
    let baby: Baby

    @Environment(AuthService.self) private var auth
    @AppStorage("useMetric") private var useMetric = false
    @State private var justLogged: String?
    @State private var todaysAppointments = AppointmentsListener()
    @State private var showingAppointments = false
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
                    TodayHeader(baby: baby, day: $day)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 4, trailing: 4))

                if isToday && !todaysAppointments.appointments.isEmpty {
                    Section {
                        TodayAppointmentsCard(appointments: todaysAppointments.appointments) { showingAppointments = true }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }

                if let sleep = recent.entries.first(where: { $0.isSleeping }) {
                    Section {
                        SleepingBanner(entry: sleep) { wakeUp(sleep) }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }

                if isToday {
                    Section {
                        SinceLastView(entries: recent.entries)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }

                Section {
                    QuickAddGrid { template in
                        if template == .appointment { showingAppointments = true } else { sheet = .new(template) }
                    }
                        .padding(.vertical, 6)
                    if isToday, let bottle = recent.entries.first(where: { $0.hasBottle }) {
                        RepeatBottleButton(entry: bottle, justLogged: justLogged) { repeatBottle(bottle) }
                    }
                } header: {
                    JungleHeader(title: "Log something", icon: "🐾")
                }
                .listRowBackground(Theme.card)

                Section {
                    DailyReportGrid(summary: DaySummary(entries: dayEntries.entries), metric: useMetric, baby: baby, day: day)
                } header: {
                    JungleHeader(title: isToday ? "Today's report" : "Daily report", icon: "🌿")
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

                Section {
                    if dayEntries.hasLoaded && dayEntries.entries.isEmpty {
                        HStack(spacing: 12) {
                            Text("🦥").font(.largeTitle)
                            Text(isToday ? "All quiet in the jungle so far today." : "Nothing logged this day.")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
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
                } header: {
                    JungleHeader(
                        title: dayEntries.entries.isEmpty ? "Timeline" : "Timeline · \(dayEntries.entries.count)",
                        icon: "🍃"
                    )
                }
                .listRowBackground(Theme.card)
            }
            .listSectionSpacing(.compact)
            .jungleBackground()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { BabySwitcher() }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(item: $sheet) { sheet in
                EntryEditor(babyID: baby.babyID, sheet: sheet, defaultDate: defaultEntryDate(for: day))
            }
            .sheet(isPresented: $showingAppointments) {
                AppointmentsView(baby: baby)
            }
            .task(id: "\(baby.babyID)|\(calendar.startOfDay(for: Date()).timeIntervalSince1970)") {
                let today = calendar.startOfDay(for: Date())
                todaysAppointments.listen(babyID: baby.babyID, from: today, to: calendar.date(byAdding: .day, value: 1, to: today) ?? today)
            }
            .task(id: "\(baby.babyID)|\(day.timeIntervalSince1970)") {
                dayEntries.listen(babyID: baby.babyID, from: day, to: dayEnd)
            }
            .onChange(of: recent.entries) { _, entries in
                WidgetSnapshot.publish(babyName: baby.name, entries: entries)
                if let sleep = entries.first(where: { $0.isSleeping }) {
                    LiveActivities.shared.showSleep(since: sleep.timestamp)
                } else {
                    LiveActivities.shared.endSleep()
                }
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

    private func wakeUp(_ sleep: LogEntry) {
        var entry = sleep
        entry.sleepEnd = Date()
        try? EntryRepository.save(entry, babyID: baby.babyID, auth: auth, metric: useMetric)
        LiveActivities.shared.endSleep()
    }

    /// Logs another bottle like the last one, right now.
    private func repeatBottle(_ bottle: LogEntry) {
        var entry = LogEntry(kind: .feed, createdByUid: auth.uid, createdByName: auth.displayName)
        entry.bottleML = bottle.bottleML
        entry.bottleContent = bottle.bottleContent
        entry.bottleFormulaML = bottle.bottleFormulaML
        entry.bottleBreastMilkML = bottle.bottleBreastMilkML
        entry.metric = bottle.metric
        try? EntryRepository.save(entry, babyID: baby.babyID, auth: auth, metric: bottle.metric ?? useMetric)
        justLogged = UUID().uuidString
    }
}

/// Big friendly greeting with the baby's name, age and the day being viewed.
struct TodayHeader: View {
    let baby: Baby
    @Binding var day: Date

    private var calendar: Calendar { Calendar.current }

    private var greeting: (String, String) {
        switch calendar.component(.hour, from: Date()) {
        case 5..<12: return ("Good morning", "🌤️")
        case 12..<17: return ("Good afternoon", "☀️")
        case 17..<21: return ("Good evening", "🌅")
        default: return ("Sweet dreams", "🌙")
        }
    }

    private var dayLabel: String {
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(greeting.0) \(greeting.1)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.bark)
                    Text(baby.name)
                        .font(.system(size: 38, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.canopy)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(baby.ageDescription)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Theme.lime.opacity(0.7), Theme.leaf.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 76, height: 76)
                    Text("🐵").font(.system(size: 44))
                    Text("🌺").font(.system(size: 20)).offset(x: 28, y: -28)
                }
                .accessibilityHidden(true)
            }

            HStack {
                Button { shift(-1) } label: {
                    Image(systemName: "chevron.left.circle.fill").font(.title2)
                }
                .accessibilityLabel("Previous day")
                Spacer()
                VStack(spacing: 2) {
                    Text(dayLabel).font(.headline)
                    if !calendar.isDateInToday(day) {
                        Button("Jump to today") { day = calendar.startOfDay(for: Date()) }
                            .font(.caption.weight(.semibold))
                    }
                }
                Spacer()
                Button { shift(1) } label: {
                    Image(systemName: "chevron.right.circle.fill").font(.title2)
                }
                .accessibilityLabel("Next day")
                .disabled(calendar.isDateInToday(day))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Theme.canopy)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Theme.card, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.leaf.opacity(0.18)))
        }
        .padding(.top, 4)
    }

    private func shift(_ days: Int) {
        if let next = calendar.date(byAdding: .day, value: days, to: day) {
            withAnimation(.snappy) { day = next }
        }
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
            HStack(spacing: 10) {
                stat(animal: Theme.feedAnimal, title: "Last feed", value: lastFeed.map { Units.ago($0.timestamp, now: context.date) } ?? "—", tint: Theme.feed)
                stat(animal: "🤱", title: "Next side", value: lastBreast?.breastLastSide.map { $0 == .left ? "Right" : "Left" } ?? "—", tint: Theme.mango)
                stat(animal: Theme.diaperAnimal, title: "Last diaper", value: lastDiaper.map { Units.ago($0.timestamp, now: context.date) } ?? "—", tint: Theme.diaper)
            }
        }
    }

    private func stat(animal: String, title: String, value: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(animal).font(.title2)
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title).font(.caption2.weight(.medium)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [tint.opacity(0.2), tint.opacity(0.07)], startPoint: .top, endPoint: .bottom))
        )
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct DailyReportGrid: View {
    let summary: DaySummary
    let metric: Bool
    let baby: Baby
    let day: Date

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ReportTile(
                title: "Feeds", value: "\(summary.feedCount)", animal: Theme.feedAnimal, tint: Theme.feed,
                lines: feedLines
            )
            ReportTile(
                title: "Diapers", value: "\(summary.diaperCount)", animal: Theme.diaperAnimal, tint: Theme.diaper,
                lines: ["\(summary.wetCount) wet · \(summary.dirtyCount) dirty"]
            )
            if baby.vitaminDReminder == true {
                ReportTile(
                    title: "Vitamin D", value: summary.vitaminD ? "Given ✓" : "Not yet", animal: "☀️", tint: Theme.mango,
                    lines: summary.vitaminD ? [] : ["Check it off when logging a feed"]
                )
            }
            if summary.sleepCount > 0 {
                ReportTile(
                    title: "Sleep", value: Units.duration(summary.sleepSeconds), animal: Theme.sleepAnimal, tint: Theme.sleep,
                    lines: ["\(summary.sleepCount) sleep\(summary.sleepCount == 1 ? "" : "s")"]
                )
            }
            if summary.pumpCount > 0 {
                ReportTile(
                    title: "Pumped", value: Units.volume(summary.pumpedML, metric: metric), animal: Theme.pumpAnimal, tint: Theme.pump,
                    lines: ["\(summary.pumpCount) session\(summary.pumpCount == 1 ? "" : "s") · \(Units.duration(summary.pumpSeconds))"]
                )
            }
            if summary.dropOff != nil || summary.pickUp != nil {
                ReportTile(
                    title: "Daycare", value: daycareValue, animal: summary.pickUp != nil ? Theme.pickUpAnimal : Theme.daycareAnimal, tint: Theme.daycare,
                    lines: daycareLines
                )
            }
            if let grams = summary.latestWeightGrams {
                ReportTile(title: "Weight", value: Units.weight(grams, metric: metric), animal: Theme.weightAnimal, tint: Theme.weight,
                           lines: percentileLine(.weight, grams / 1000))
            }
            if let cm = summary.latestLengthCm {
                ReportTile(title: "Length", value: Units.length(cm, metric: metric), animal: "🦒", tint: Theme.weight,
                           lines: percentileLine(.length, cm))
            }
            if let cm = summary.latestHeadCm {
                ReportTile(title: "Head size", value: Units.length(cm, metric: metric), animal: "🐣", tint: Theme.weight,
                           lines: percentileLine(.head, cm))
            }
            ForEach(summary.milestones, id: \.self) { milestone in
                ReportTile(title: "Milestone", value: milestone, animal: Theme.milestoneAnimal, tint: Theme.milestone, lines: [])
            }
        }
    }

    private func percentileLine(_ measure: GrowthMeasure, _ value: Double) -> [String] {
        guard let sex = baby.sex,
              let p = GrowthStandards.percentile(measure, sex: sex, birthDate: baby.birthDate, on: day, value: value)
        else { return [] }
        return ["\(GrowthStandards.ordinal(p)) percentile"]
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
    let animal: String
    let tint: Color
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.heavy))
                .tracking(0.6)
                .foregroundStyle(tint)
            Text(value)
                .font(.system(.title, design: .rounded).weight(.heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .padding(14)
        .background(alignment: .topTrailing) {
            Text(animal)
                .font(.system(size: 34))
                .rotationEffect(.degrees(12))
                .padding(8)
                .opacity(0.9)
        }
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [tint.opacity(0.22), tint.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(tint.opacity(0.25), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

struct QuickAddGrid: View {
    let onSelect: (EntryTemplate) -> Void
    @State private var tapped = 0

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 14) {
            ForEach(EntryTemplate.allCases) { template in
                Button {
                    tapped += 1
                    onSelect(template)
                } label: {
                    VStack(spacing: 6) {
                        MascotBadge(animal: template.animal, tint: template.tint, size: 56)
                            .shadow(color: template.tint.opacity(0.3), radius: 6, y: 3)
                        Text(template.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(BouncyButtonStyle())
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: tapped)
    }
}

struct EntryRow: View {
    let entry: LogEntry
    let metric: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            MascotBadge(animal: entry.animal, tint: entry.tint)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(entry.displayTitle).font(.body.weight(.bold))
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

/// Shown while the baby is asleep, with a big Wake up button.
struct SleepingBanner: View {
    let entry: LogEntry
    let wakeUp: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Text(Theme.sleepAnimal).font(.system(size: 40))
            VStack(alignment: .leading, spacing: 2) {
                Text("Sleeping").font(.caption.weight(.heavy)).foregroundStyle(.white.opacity(0.85))
                Text(timerInterval: entry.timestamp...Date.distantFuture, countsDown: false)
                    .font(.system(.title, design: .rounded).weight(.heavy).monospacedDigit())
                    .foregroundStyle(.white)
                Text("since \(entry.timestamp.formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(.white.opacity(0.85))
            }
            Spacer()
            Button(action: wakeUp) {
                Text("Wake up ☀️")
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.white, in: Capsule())
                    .foregroundStyle(Theme.sleep)
            }
            .buttonStyle(BouncyButtonStyle())
        }
        .padding(16)
        .background(
            LinearGradient(colors: [Theme.sleep, Theme.orchid], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(alignment: .topTrailing) {
            Text("✨").padding(8).accessibilityHidden(true)
        }
    }
}

/// One tap to log the same bottle again.
struct RepeatBottleButton: View {
    let entry: LogEntry
    let justLogged: String?
    let action: () -> Void

    @AppStorage("useMetric") private var useMetric = false
    @State private var confirmed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(Theme.bottleAnimal).font(.title3)
                VStack(alignment: .leading, spacing: 0) {
                    Text(confirmed ? "Logged!" : "Repeat last bottle").font(.subheadline.weight(.bold))
                    Text(description).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: confirmed ? "checkmark.circle.fill" : "arrow.counterclockwise.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.bottle)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(BouncyButtonStyle())
        .sensoryFeedback(.success, trigger: justLogged)
        .onChange(of: justLogged) {
            withAnimation { confirmed = true }
            Task {
                try? await Task.sleep(for: .seconds(2))
                withAnimation { confirmed = false }
            }
        }
    }

    private var description: String {
        let amount = entry.bottleML.map { Units.volume($0, metric: entry.metric ?? useMetric) } ?? ""
        return "\(amount) \((entry.bottleContent ?? .formula).label.lowercased()) · now"
    }
}
