import SwiftUI

/// A nap or night sleep: start a timer and save it running (the Today screen shows a Wake up button
/// and the lock screen shows the timer), or type in a past sleep. Optional details on how and where.
struct SleepFormView: View {
    @Environment(AuthService.self) private var auth
    @AppStorage("useMetric") private var useMetric = false

    let babyID: String
    let existing: LogEntry?

    @State private var start: Date
    @State private var stillAsleep: Bool
    @State private var end: Date
    @State private var how: String?
    @State private var place: String?
    @State private var notes: String
    /// A new sleep starts as a plain entry; tapping Start makes it a running timer from now.
    @State private var timerStarted: Bool

    init(babyID: String, existing: LogEntry?, defaultDate: Date) {
        self.babyID = babyID
        self.existing = existing
        _start = State(initialValue: existing?.timestamp ?? defaultDate)
        _stillAsleep = State(initialValue: existing.map { $0.sleepEnd == nil } ?? false)
        _end = State(initialValue: existing?.sleepEnd ?? max(Date(), defaultDate))
        _how = State(initialValue: existing?.sleepHow)
        _place = State(initialValue: existing?.sleepPlace)
        _notes = State(initialValue: existing?.notes ?? "")
        _timerStarted = State(initialValue: existing?.isSleeping ?? false)
    }

    private var isValid: Bool { stillAsleep || end > start }

    var body: some View {
        Form {
            Section {
                SleepTimerCard(start: start, running: timerStarted && stillAsleep, stopped: timerStarted && !stillAsleep, end: end) {
                    if timerStarted && stillAsleep {
                        end = Date()
                        withAnimation { stillAsleep = false }
                    } else {
                        start = Date()
                        timerStarted = true
                        withAnimation { stillAsleep = true }
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } footer: {
                if timerStarted && stillAsleep {
                    Text("Tap Save to keep the timer running. The Today screen and lock screen show it until you tap Wake up.")
                }
            }

            Section {
                DatePicker("Fell asleep", selection: $start)
                Toggle(isOn: $stillAsleep.animation()) {
                    Label { Text("Still sleeping").fontWeight(.semibold) } icon: { Text(Theme.sleepAnimal) }
                }
                .tint(Theme.sleep)
                if !stillAsleep {
                    DatePicker("Woke up", selection: $end, in: start...)
                    LabeledContent("Slept", value: Units.duration(max(0, Int(end.timeIntervalSince(start)))))
                }
            } header: {
                Text("Times")
            }

            Section("How they fell asleep") {
                ChoiceChips(options: SleepHow.allCases.map(\.rawValue), selection: $how, tint: Theme.sleep)
            }
            Section("Where") {
                ChoiceChips(options: SleepPlace.allCases.map(\.rawValue), selection: $place, tint: Theme.orchid)
            }
            Section("Notes") {
                TextField("Optional, like \"woke up happy\"", text: $notes, axis: .vertical)
            }
            if let existing {
                DeleteEntrySection(entry: existing, babyID: babyID)
            }
        }
        .entryFormToolbar(existing == nil ? "Log sleep" : "Edit sleep", canSave: isValid, save: save)
    }

    private func save() throws {
        var entry = existing ?? LogEntry(kind: .sleep, createdByUid: auth.uid, createdByName: auth.displayName)
        entry.timestamp = start
        entry.sleepEnd = stillAsleep ? nil : end
        entry.sleepHow = how
        entry.sleepPlace = place
        entry.notes = notes.trimmedOrNil
        try EntryRepository.save(entry, babyID: babyID, auth: auth, metric: useMetric)
        if stillAsleep {
            LiveActivities.shared.showSleep(since: start)
        } else {
            LiveActivities.shared.endSleep()
        }
    }
}

/// Big round Start / Wake up button with the running time, like a stopwatch.
private struct SleepTimerCard: View {
    let start: Date
    let running: Bool
    let stopped: Bool
    let end: Date
    let action: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Group {
                if running {
                    Text(timerInterval: start...Date.distantFuture, countsDown: false)
                } else if stopped {
                    Text(Units.duration(max(0, Int(end.timeIntervalSince(start)))))
                } else {
                    Text("Ready when they are")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                }
            }
            .font(.system(size: 44, weight: .heavy, design: .rounded).monospacedDigit())
            .foregroundStyle(Theme.sleep)
            .contentTransition(.numericText())

            Button(action: action) {
                VStack(spacing: 2) {
                    Text(running ? "☀️" : Theme.sleepAnimal).font(.system(size: 34))
                    Text(running ? "Wake up" : (stopped ? "Start again" : "Start sleep"))
                        .font(.subheadline.weight(.heavy))
                }
                .foregroundStyle(.white)
                .frame(width: 132, height: 132)
                .background(
                    Circle().fill(LinearGradient(
                        colors: running ? [Theme.sunshine, Theme.mango] : [Theme.sleep, Theme.orchid],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                )
                .shadow(color: (running ? Theme.mango : Theme.sleep).opacity(0.35), radius: 10, y: 5)
            }
            .buttonStyle(BouncyButtonStyle())
            .sensoryFeedback(.impact(weight: .medium), trigger: running)

            if running || stopped {
                Text(stopped
                     ? "\(start.formatted(date: .omitted, time: .shortened)) to \(end.formatted(date: .omitted, time: .shortened))"
                     : "Asleep since \(start.formatted(date: .omitted, time: .shortened))")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// A row of tappable capsules; tap again to clear.
struct ChoiceChips: View {
    let options: [String]
    @Binding var selection: String?
    let tint: Color

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(options, id: \.self) { option in
                let selected = selection == option
                Button {
                    selection = selected ? nil : option
                } label: {
                    Text(option)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .foregroundStyle(selected ? .white : tint)
                        .background(selected ? tint : tint.opacity(0.14), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Lays children out left to right, wrapping onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty && rows[rows.count - 1].width + spacing + size.width > width {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}
