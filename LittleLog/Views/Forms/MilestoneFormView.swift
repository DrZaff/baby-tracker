import SwiftUI

struct MilestoneFormView: View {
    @Environment(AuthService.self) private var auth
    @AppStorage("useMetric") private var useMetric = false

    static let suggestions = [
        "First smile", "First laugh", "Held head up", "Rolled over", "Slept through the night",
        "First tooth", "Sat up", "First solid food", "Crawled", "Pulled to stand",
        "First word", "First steps", "First bath", "First outing",
    ]

    let babyID: String
    let existing: LogEntry?

    @State private var time: Date
    @State private var title: String
    @State private var notes: String

    init(babyID: String, existing: LogEntry?, defaultDate: Date) {
        self.babyID = babyID
        self.existing = existing
        _time = State(initialValue: existing?.timestamp ?? defaultDate)
        _title = State(initialValue: existing?.title ?? "")
        _notes = State(initialValue: existing?.notes ?? "")
    }

    var body: some View {
        Form {
            Section {
                TextField("What happened?", text: $title)
                    .font(.title3)
                DatePicker("When", selection: $time)
            }
            Section("Ideas") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(Self.suggestions, id: \.self) { suggestion in
                            Button { title = suggestion } label: {
                                Text(suggestion)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.bark)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Theme.milestone.opacity(0.25), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            Section("Notes") {
                TextField("Optional", text: $notes, axis: .vertical)
            }
            if let existing {
                DeleteEntrySection(entry: existing, babyID: babyID)
            }
        }
        .entryFormToolbar(existing == nil ? "New milestone" : "Edit milestone", canSave: title.trimmedOrNil != nil, save: save)
    }

    private func save() throws {
        var entry = existing ?? LogEntry(kind: .milestone, createdByUid: auth.uid, createdByName: auth.displayName)
        entry.timestamp = time
        entry.title = title.trimmedOrNil
        entry.notes = notes.trimmedOrNil
        try EntryRepository.save(entry, babyID: babyID, auth: auth, metric: useMetric)
        if existing == nil {
            NotificationCenter.default.post(name: .milestoneLogged, object: nil)
        }
    }
}
