import SwiftUI

struct WeightFormView: View {
    @Environment(AuthService.self) private var auth

    let babyID: String
    let existing: LogEntry?

    @State private var time: Date
    @State private var metric: Bool
    @State private var pounds: Int?
    @State private var ounces: Double?
    @State private var kilograms: Double?
    @State private var notes: String

    init(babyID: String, existing: LogEntry?, defaultDate: Date) {
        self.babyID = babyID
        self.existing = existing
        _time = State(initialValue: existing?.timestamp ?? defaultDate)
        _metric = State(initialValue: existing?.metric ?? UserDefaults.standard.bool(forKey: "useMetric"))
        if let grams = existing?.weightGrams {
            let (lb, oz) = Units.poundsAndOunces(grams)
            _pounds = State(initialValue: lb)
            _ounces = State(initialValue: oz)
            _kilograms = State(initialValue: (grams / 10).rounded() / 100)
        }
        _notes = State(initialValue: existing?.notes ?? "")
    }

    private var grams: Double? { grams(metric: metric) }

    private func grams(metric: Bool) -> Double? {
        if metric {
            guard let kg = kilograms, kg > 0 else { return nil }
            return kg * 1000
        }
        let total = Double(pounds ?? 0) * Units.gramsPerPound + (ounces ?? 0) * Units.gramsPerOunce
        return total > 0 ? total : nil
    }

    var body: some View {
        Form {
            Section {
                DatePicker("Date", selection: $time)
            }
            Section("Weight") {
                Picker("Units", selection: $metric) {
                    Text("lb & oz").tag(false)
                    Text("kg").tag(true)
                }
                .pickerStyle(.segmented)
                if metric {
                    HStack {
                        TextField("0.00", value: $kilograms, format: .number)
                            .keyboardType(.decimalPad)
                            .font(.title2)
                        Text("kg").foregroundStyle(.secondary)
                    }
                } else {
                    HStack {
                        TextField("0", value: $pounds, format: .number)
                            .keyboardType(.numberPad)
                            .font(.title2)
                        Text("lb").foregroundStyle(.secondary)
                        TextField("0", value: $ounces, format: .number)
                            .keyboardType(.decimalPad)
                            .font(.title2)
                        Text("oz").foregroundStyle(.secondary)
                    }
                }
            }
            Section("Notes") {
                TextField("Optional, like \"pediatrician visit\"", text: $notes, axis: .vertical)
            }
            if let existing {
                DeleteEntrySection(entry: existing, babyID: babyID)
            }
        }
        .entryFormToolbar(existing == nil ? "Log weight" : "Edit weight", canSave: grams != nil, save: save)
        .onChange(of: metric) { old, _ in
            // Carry the weight over to the other units.
            guard let g = grams(metric: old) else { return }
            let (lb, oz) = Units.poundsAndOunces(g)
            pounds = lb
            ounces = oz
            kilograms = (g / 10).rounded() / 100
        }
    }

    private func save() throws {
        var entry = existing ?? LogEntry(kind: .weight, createdByUid: auth.uid, createdByName: auth.displayName)
        entry.timestamp = time
        entry.weightGrams = grams
        entry.metric = metric
        entry.notes = notes.trimmedOrNil
        try EntryRepository.save(entry, babyID: babyID, auth: auth, metric: metric)
    }
}
