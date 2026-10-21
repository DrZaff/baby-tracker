import SwiftUI

/// Weight, length and head size. Any of them can be filled in.
struct WeightFormView: View {
    @Environment(AuthService.self) private var auth

    let babyID: String
    let existing: LogEntry?

    @State private var time: Date
    @State private var metric: Bool
    @State private var pounds: Int?
    @State private var ounces: Double?
    @State private var kilograms: Double?
    @State private var length: Double?
    @State private var head: Double?
    @State private var lengthMetric: Bool
    @State private var headMetric: Bool
    @State private var notes: String

    init(babyID: String, existing: LogEntry?, defaultDate: Date) {
        self.babyID = babyID
        self.existing = existing
        let metric = existing?.metric ?? UserDefaults.standard.bool(forKey: "useMetric")
        _time = State(initialValue: existing?.timestamp ?? defaultDate)
        _metric = State(initialValue: metric)
        if let grams = existing?.weightGrams {
            let (lb, oz) = Units.poundsAndOunces(grams)
            _pounds = State(initialValue: lb)
            _ounces = State(initialValue: oz)
            _kilograms = State(initialValue: (grams / 10).rounded() / 100)
        }
        let lengthMetric = existing?.lengthMetric ?? metric
        let headMetric = existing?.headMetric ?? metric
        _lengthMetric = State(initialValue: lengthMetric)
        _headMetric = State(initialValue: headMetric)
        _length = State(initialValue: existing?.lengthCm.map { Units.lengthValue($0, metric: lengthMetric) })
        _head = State(initialValue: existing?.headCm.map { Units.lengthValue($0, metric: headMetric) })
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

    private func centimetres(_ value: Double?, metric: Bool) -> Double? {
        guard let value, value > 0 else { return nil }
        return Units.centimetres(from: value, metric: metric)
    }

    private var canSave: Bool { grams != nil || (length ?? 0) > 0 || (head ?? 0) > 0 }

    var body: some View {
        Form {
            Section {
                DatePicker("Date", selection: $time)
            }
            Section {
                HStack(spacing: 6) {
                    Text("Weight")
                    Spacer()
                    if metric {
                        TextField("0.00", value: $kilograms, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 80)
                    } else {
                        TextField("0", value: $pounds, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 36)
                        Text("lb").foregroundStyle(.secondary)
                        TextField("0", value: $ounces, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 44)
                        Text("oz").foregroundStyle(.secondary)
                    }
                    UnitSwitch(options: ["lb", "kg"], metric: $metric)
                        .padding(.leading, 4)
                }
            } header: {
                Text("\(Theme.weightAnimal) Weight")
            }
            Section {
                LengthField(title: "Length", value: $length, metric: $lengthMetric)
                LengthField(title: "Head size", value: $head, metric: $headMetric)
            } header: {
                Text("🦒 Length and head")
            } footer: {
                Text("Fill in whatever you measured. Head size is the distance around the head.")
            }
            Section("Notes") {
                TextField("Optional, like \"pediatrician visit\"", text: $notes, axis: .vertical)
            }
            if let existing {
                DeleteEntrySection(entry: existing, babyID: babyID)
            }
        }
        .entryFormToolbar(existing == nil ? "Log growth" : "Edit growth", canSave: canSave, save: save)
        // Each measurement keeps its value when its own units switch.
        .onChange(of: metric) { old, _ in
            if let g = grams(metric: old) {
                let (lb, oz) = Units.poundsAndOunces(g)
                pounds = lb
                ounces = oz
                kilograms = (g / 10).rounded() / 100
            }
        }
        .onChange(of: lengthMetric) { old, new in
            length = centimetres(length, metric: old).map { Units.lengthValue($0, metric: new) }
        }
        .onChange(of: headMetric) { old, new in
            head = centimetres(head, metric: old).map { Units.lengthValue($0, metric: new) }
        }
    }

    private func save() throws {
        var entry = existing ?? LogEntry(kind: .weight, createdByUid: auth.uid, createdByName: auth.displayName)
        entry.timestamp = time
        entry.weightGrams = grams
        entry.lengthCm = centimetres(length, metric: lengthMetric)
        entry.headCm = centimetres(head, metric: headMetric)
        entry.metric = metric
        entry.lengthMetric = entry.lengthCm == nil ? nil : lengthMetric
        entry.headMetric = entry.headCm == nil ? nil : headMetric
        entry.notes = notes.trimmedOrNil
        try EntryRepository.save(entry, babyID: babyID, auth: auth, metric: metric)
    }
}

/// A length with an in / cm switch beside it.
struct LengthField: View {
    let title: String
    @Binding var value: Double?
    @Binding var metric: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: $value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 80)
            UnitSwitch(options: ["in", "cm"], metric: $metric)
        }
    }
}
