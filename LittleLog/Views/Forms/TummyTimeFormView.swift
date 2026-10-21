import SwiftUI

/// One session of tummy time. Log as many as you like each day.
struct TummyTimeFormView: View {
    @Environment(AuthService.self) private var auth
    @AppStorage("useMetric") private var useMetric = false

    let babyID: String
    let existing: LogEntry?

    @State private var start: Date
    @State private var timer: SideTimer
    @State private var notes: String

    init(babyID: String, existing: LogEntry?, defaultDate: Date) {
        self.babyID = babyID
        self.existing = existing
        _start = State(initialValue: existing?.timestamp ?? defaultDate)
        _timer = State(initialValue: SideTimer(seconds: existing?.tummySeconds))
        _notes = State(initialValue: existing?.notes ?? "")
    }

    var body: some View {
        Form {
            Section {
                DatePicker("Started", selection: $start)
                SideTimerRow(label: "Time", tint: Theme.tummy, timer: $timer) {
                    // Starting the timer from zero means the session starts now.
                    if timer.seconds == 0 && existing == nil { start = Date() }
                }
            } header: {
                Text("\(Theme.tummyAnimal) Tummy time")
            } footer: {
                Text("Tap play to time it, use − / + to change it a minute at a time, or tap the time to type it.")
            }
            Section("Notes") {
                TextField("Optional, like \"lifted head\"", text: $notes, axis: .vertical)
            }
            if let existing {
                DeleteEntrySection(entry: existing, babyID: babyID)
            }
        }
        .entryFormToolbar(existing == nil ? "Log tummy time" : "Edit tummy time", canSave: timer.seconds > 0, save: save)
        .onChange(of: timer) { updateLiveActivity() }
        .onDisappear { LiveActivities.shared.endFeedTimer() }
    }

    private func updateLiveActivity() {
        if timer.isRunning {
            LiveActivities.shared.showFeedTimer(
                title: "Tummy time", animal: Theme.tummyAnimal, color: 0x5DB563,
                startedAt: Date().addingTimeInterval(-timer.elapsed())
            )
        } else {
            LiveActivities.shared.endFeedTimer()
        }
    }

    private func save() throws {
        var entry = existing ?? LogEntry(kind: .tummy, createdByUid: auth.uid, createdByName: auth.displayName)
        entry.timestamp = start
        entry.tummySeconds = timer.seconds
        entry.notes = notes.trimmedOrNil
        try EntryRepository.save(entry, babyID: babyID, auth: auth, metric: useMetric)
    }
}
