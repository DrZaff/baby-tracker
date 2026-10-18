import SwiftUI

enum FeedComponent { case breast, bottle, pump }

struct FeedFormView: View {
    @Environment(AuthService.self) private var auth

    let babyID: String
    let existing: LogEntry?

    @State private var time: Date
    @State private var metric: Bool
    @State private var includeBreast: Bool
    @State private var includeBottle: Bool
    @State private var includePump: Bool
    @State private var breastLeft: SideTimer
    @State private var breastRight: SideTimer
    @State private var bottleAmount: Double?
    @State private var bottleContent: BottleContent
    @State private var pumpLeft: SideTimer
    @State private var pumpRight: SideTimer
    @State private var pumpedAmount: Double?
    @State private var notes: String

    init(babyID: String, existing: LogEntry?, start: FeedComponent, defaultDate: Date) {
        self.babyID = babyID
        self.existing = existing
        let metric = existing?.metric ?? UserDefaults.standard.bool(forKey: "useMetric")
        _metric = State(initialValue: metric)
        _time = State(initialValue: existing?.timestamp ?? defaultDate)
        if let e = existing {
            _includeBreast = State(initialValue: e.hasBreast)
            _includeBottle = State(initialValue: e.hasBottle)
            _includePump = State(initialValue: e.hasPump)
        } else {
            _includeBreast = State(initialValue: start == .breast)
            _includeBottle = State(initialValue: start == .bottle)
            _includePump = State(initialValue: start == .pump)
        }
        _breastLeft = State(initialValue: SideTimer(seconds: existing?.breastLeftSeconds))
        _breastRight = State(initialValue: SideTimer(seconds: existing?.breastRightSeconds))
        _bottleAmount = State(initialValue: existing?.bottleML.map { Units.volumeValue($0, metric: metric) })
        _bottleContent = State(initialValue: existing?.bottleContent ?? .formula)
        _pumpLeft = State(initialValue: SideTimer(seconds: existing?.pumpLeftSeconds))
        _pumpRight = State(initialValue: SideTimer(seconds: existing?.pumpRightSeconds))
        _pumpedAmount = State(initialValue: existing?.pumpedML.map { Units.volumeValue($0, metric: metric) })
        _notes = State(initialValue: existing?.notes ?? "")
    }

    private var unit: String { Units.volumeUnit(metric: metric) }

    private var hasContent: Bool {
        (includeBreast && (breastLeft.elapsed() > 0 || breastRight.elapsed() > 0 || breastLeft.isRunning || breastRight.isRunning))
            || (includeBottle && (bottleAmount ?? 0) > 0)
            || (includePump && (pumpLeft.elapsed() > 0 || pumpRight.elapsed() > 0 || pumpLeft.isRunning || pumpRight.isRunning || (pumpedAmount ?? 0) > 0))
    }

    var body: some View {
        Form {
            Section {
                DatePicker("Started", selection: $time)
                if includeBottle || includePump {
                    Picker("Units", selection: $metric) {
                        Text("oz").tag(false)
                        Text("ml").tag(true)
                    }
                    .pickerStyle(.segmented)
                }
            }

            Section {
                Toggle(isOn: $includeBreast.animation()) {
                    Label("Breastfeeding", systemImage: "heart.fill").foregroundStyle(Theme.feed)
                }
                .tint(Theme.feed)
                if includeBreast {
                    SideTimerRow(label: "Left", tint: Theme.feed, timer: $breastLeft) { breastRight.pause() }
                    SideTimerRow(label: "Right", tint: Theme.feed, timer: $breastRight) { breastLeft.pause() }
                }
            } footer: {
                if includeBreast { Text("Tap play to time each side, or use − / + to enter minutes.") }
            }

            Section {
                Toggle(isOn: $includeBottle.animation()) {
                    Label("Bottle", systemImage: "drop.fill").foregroundStyle(Theme.bottle)
                }
                .tint(Theme.bottle)
                if includeBottle {
                    Picker("Contents", selection: $bottleContent) {
                        ForEach(BottleContent.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    AmountField(title: "Amount", unit: unit, value: $bottleAmount)
                }
            }

            Section {
                Toggle(isOn: $includePump.animation()) {
                    Label("Pumping", systemImage: "drop.circle").foregroundStyle(Theme.pump)
                }
                .tint(Theme.pump)
                if includePump {
                    SideTimerRow(label: "Left", tint: Theme.pump, timer: $pumpLeft)
                    SideTimerRow(label: "Right", tint: Theme.pump, timer: $pumpRight)
                    AmountField(title: "Amount pumped", unit: unit, value: $pumpedAmount)
                }
            }

            Section("Notes") {
                TextField("Optional", text: $notes, axis: .vertical)
            }

            if let existing {
                DeleteEntrySection(entry: existing, babyID: babyID)
            }
        }
        .entryFormToolbar(existing == nil ? "Log feed" : "Edit feed", canSave: hasContent, save: save)
        .onChange(of: metric) { old, new in
            // Keep the same amount when switching units.
            bottleAmount = bottleAmount.map { Units.volumeValue(Units.millilitres(from: $0, metric: old), metric: new) }
            pumpedAmount = pumpedAmount.map { Units.volumeValue(Units.millilitres(from: $0, metric: old), metric: new) }
        }
    }

    private func save() throws {
        var entry = existing ?? LogEntry(kind: .feed, createdByUid: auth.uid, createdByName: auth.displayName)
        entry.timestamp = time

        let left = includeBreast ? breastLeft.seconds : 0
        let right = includeBreast ? breastRight.seconds : 0
        entry.breastLeftSeconds = left > 0 ? left : nil
        entry.breastRightSeconds = right > 0 ? right : nil
        // Remember which side was used last so the next feed can start on the other one.
        if !includeBreast || left + right == 0 {
            entry.breastLastSide = nil
        } else {
            switch (breastLeft.lastStarted, breastRight.lastStarted) {
            case let (l?, r?): entry.breastLastSide = r > l ? .right : .left
            case (.some, nil): entry.breastLastSide = .left
            case (nil, .some): entry.breastLastSide = .right
            case (nil, nil):
                if left > 0 && right == 0 { entry.breastLastSide = .left }
                else if right > 0 && left == 0 { entry.breastLastSide = .right }
                else { entry.breastLastSide = existing?.breastLastSide }
            }
        }

        if includeBottle, let amount = bottleAmount, amount > 0 {
            entry.bottleML = Units.millilitres(from: amount, metric: metric)
            entry.bottleContent = bottleContent
        } else {
            entry.bottleML = nil
            entry.bottleContent = nil
        }

        let pl = includePump ? pumpLeft.seconds : 0
        let pr = includePump ? pumpRight.seconds : 0
        entry.pumpLeftSeconds = pl > 0 ? pl : nil
        entry.pumpRightSeconds = pr > 0 ? pr : nil
        if includePump, let amount = pumpedAmount, amount > 0 {
            entry.pumpedML = Units.millilitres(from: amount, metric: metric)
        } else {
            entry.pumpedML = nil
        }

        entry.metric = entry.bottleML != nil || entry.pumpedML != nil ? metric : nil
        entry.notes = notes.trimmedOrNil
        try EntryRepository.save(entry, babyID: babyID, auth: auth, metric: metric)
    }
}

struct AmountField: View {
    let title: String
    let unit: String
    @Binding var value: Double?

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: $value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 100)
            Text(unit).foregroundStyle(.secondary)
        }
    }
}

struct DeleteEntrySection: View {
    let entry: LogEntry
    let babyID: String
    @Environment(\.dismiss) private var dismiss
    @State private var confirming = false

    var body: some View {
        Section {
            Button("Delete entry", role: .destructive) { confirming = true }
                .frame(maxWidth: .infinity)
        } footer: {
            Text("Logged by \(entry.createdByName)" + (entry.updatedByName.map { ", last edited by \($0)" } ?? ""))
        }
        .confirmationDialog("Delete this entry for everyone?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                EntryRepository.delete(entry, babyID: babyID)
                dismiss()
            }
        }
    }
}
