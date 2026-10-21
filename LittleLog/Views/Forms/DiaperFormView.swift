import SwiftUI

struct DiaperFormView: View {
    @Environment(AuthService.self) private var auth
    @AppStorage("useMetric") private var useMetric = false

    enum Contents: String, CaseIterable, Identifiable {
        case pee = "Pee", poop = "Poop", both = "Both"
        var id: String { rawValue }
    }

    struct StoolColor {
        let name: String
        let color: Color
    }

    static let colors: [StoolColor] = [
        StoolColor(name: "Yellow", color: Color(red: 0.95, green: 0.80, blue: 0.25)),
        StoolColor(name: "Green", color: Color(red: 0.45, green: 0.60, blue: 0.25)),
        StoolColor(name: "Brown", color: Color(red: 0.55, green: 0.35, blue: 0.20)),
        StoolColor(name: "Black", color: Color(white: 0.15)),
        StoolColor(name: "Red", color: Color(red: 0.80, green: 0.20, blue: 0.20)),
        StoolColor(name: "White", color: Color(white: 0.92)),
    ]
    static let consistencies = ["Runny", "Seedy", "Soft", "Formed", "Hard"]

    let babyID: String
    let existing: LogEntry?

    @State private var time: Date
    @State private var contents: Contents
    @State private var stoolColor: String?
    @State private var stoolConsistency: String?
    @State private var notes: String

    init(babyID: String, existing: LogEntry?, defaultDate: Date) {
        self.babyID = babyID
        self.existing = existing
        _time = State(initialValue: existing?.timestamp ?? defaultDate)
        let wet = existing?.wet ?? true
        let dirty = existing?.dirty ?? false
        _contents = State(initialValue: wet && dirty ? .both : (dirty ? .poop : .pee))
        _stoolColor = State(initialValue: existing?.stoolColor)
        _stoolConsistency = State(initialValue: existing?.stoolConsistency)
        _notes = State(initialValue: existing?.notes ?? "")
    }

    var body: some View {
        Form {
            Section {
                DatePicker("Time", selection: $time)
                Picker("Diaper", selection: $contents) {
                    ForEach(Contents.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.vertical, 4)
            }

            if contents != .pee {
                Section("Color") {
                    HStack(spacing: 10) {
                        ForEach(Self.colors, id: \.name) { option in
                            Button {
                                stoolColor = stoolColor == option.name ? nil : option.name
                            } label: {
                                Circle()
                                    .fill(option.color)
                                    .frame(width: 34, height: 34)
                                    .overlay(Circle().stroke(Color.secondary.opacity(0.3)))
                                    .overlay {
                                        if stoolColor == option.name {
                                            Circle().stroke(Theme.diaper, lineWidth: 3).padding(-4)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(option.name)
                        }
                    }
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                }
                Section("Consistency") {
                    Picker("Consistency", selection: $stoolConsistency) {
                        Text("Not noted").tag(String?.none)
                        ForEach(Self.consistencies, id: \.self) { Text($0).tag(String?.some($0)) }
                    }
                }
            }

            Section("Notes") {
                TextField("Optional", text: $notes, axis: .vertical)
            }

            if let existing {
                DeleteEntrySection(entry: existing, babyID: babyID)
            }
        }
        .entryFormToolbar(existing == nil ? "Log diaper" : "Edit diaper", save: save)
    }

    private func save() throws {
        var entry = existing ?? LogEntry(kind: .diaper, createdByUid: auth.uid, createdByName: auth.displayName)
        entry.timestamp = time
        entry.wet = contents != .poop
        entry.dirty = contents != .pee
        entry.stoolColor = entry.dirty == true ? stoolColor : nil
        entry.stoolConsistency = entry.dirty == true ? stoolConsistency : nil
        entry.notes = notes.trimmedOrNil
        try EntryRepository.save(entry, babyID: babyID, auth: auth, metric: useMetric)
    }
}
