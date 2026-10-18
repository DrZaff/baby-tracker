import SwiftUI

struct DaycareFormView: View {
    @Environment(AuthService.self) private var auth
    @AppStorage("useMetric") private var useMetric = false

    let babyID: String
    let existing: LogEntry?

    @State private var time: Date
    @State private var event: DaycareEvent
    @State private var person: String
    @State private var notes: String

    init(babyID: String, existing: LogEntry?, defaultDate: Date) {
        self.babyID = babyID
        self.existing = existing
        _time = State(initialValue: existing?.timestamp ?? defaultDate)
        let hour = Calendar.current.component(.hour, from: defaultDate)
        _event = State(initialValue: existing?.daycareEvent ?? (hour < 12 ? .dropOff : .pickUp))
        _person = State(initialValue: existing?.daycarePerson ?? "")
        _notes = State(initialValue: existing?.notes ?? "")
    }

    var body: some View {
        Form {
            Section {
                Picker("Event", selection: $event) {
                    ForEach(DaycareEvent.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)
                DatePicker("Time", selection: $time)
                TextField("Who (optional)", text: $person)
            }
            Section("Notes") {
                TextField("Optional, like \"bring more diapers\"", text: $notes, axis: .vertical)
            }
            if let existing {
                DeleteEntrySection(entry: existing, babyID: babyID)
            }
        }
        .entryFormToolbar(existing == nil ? "Daycare" : "Edit daycare", save: save)
        .onAppear {
            if existing == nil, person.isEmpty { person = auth.displayName }
        }
    }

    private func save() throws {
        var entry = existing ?? LogEntry(kind: .daycare, createdByUid: auth.uid, createdByName: auth.displayName)
        entry.timestamp = time
        entry.daycareEvent = event
        entry.daycarePerson = person.trimmedOrNil
        entry.notes = notes.trimmedOrNil
        try EntryRepository.save(entry, babyID: babyID, auth: auth, metric: useMetric)
    }
}
