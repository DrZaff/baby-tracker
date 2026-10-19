import SwiftUI

struct SleepFormView: View {
    @Environment(AuthService.self) private var auth
    @AppStorage("useMetric") private var useMetric = false

    let babyID: String
    let existing: LogEntry?

    @State private var start: Date
    @State private var stillAsleep: Bool
    @State private var end: Date
    @State private var notes: String

    init(babyID: String, existing: LogEntry?, defaultDate: Date) {
        self.babyID = babyID
        self.existing = existing
        _start = State(initialValue: existing?.timestamp ?? defaultDate)
        // A new sleep starts now and is still going; edits keep what was logged.
        _stillAsleep = State(initialValue: existing.map { $0.sleepEnd == nil } ?? true)
        _end = State(initialValue: existing?.sleepEnd ?? max(Date(), defaultDate))
        _notes = State(initialValue: existing?.notes ?? "")
    }

    private var isValid: Bool { stillAsleep || end > start }

    var body: some View {
        Form {
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
            } footer: {
                if stillAsleep {
                    Text("Save now and tap Wake up on the Today screen when the baby wakes.")
                }
            }
            Section("Notes") {
                TextField("Optional, like \"in the crib\"", text: $notes, axis: .vertical)
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
        entry.notes = notes.trimmedOrNil
        try EntryRepository.save(entry, babyID: babyID, auth: auth, metric: useMetric)
        if stillAsleep {
            LiveActivities.shared.showSleep(since: start)
        } else {
            LiveActivities.shared.endSleep()
        }
    }
}
