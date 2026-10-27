import SwiftUI

/// The routine vaccine schedule for the baby's age, with each shot checked off once it's given.
/// Every caregiver sees the same checklist.
struct VaccinesView: View {
    let baby: Baby

    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var auth
    @State private var vaccines = VaccinesListener()
    @State private var editing: VaccineDose?
    @State private var showLater = false

    private var age: Double { VaccineSchedule.ageInMonths(birthDate: baby.birthDate) }

    /// Visits up to about six months ahead; later ones fold away.
    private var soon: [VaccineVisit] { VaccineSchedule.visits.filter { $0.fromMonths <= age + 6 } }
    private var later: [VaccineVisit] { VaccineSchedule.visits.filter { $0.fromMonths > age + 6 } }

    private var dueCount: Int {
        VaccineSchedule.visits
            .filter { $0.fromMonths <= age }
            .flatMap(\.doses)
            .filter { vaccines.given[$0.id] == nil && !VaccineSchedule.optionalIDs.contains($0.id) }
            .count
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VaccineSummaryCard(baby: baby, due: dueCount, given: vaccines.given.count)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

                ForEach(soon) { visit in
                    visitSection(visit)
                }

                if !later.isEmpty {
                    // Later visits fold away, and open as the same age sections as the ones above.
                    Section {
                        Button {
                            withAnimation { showLater.toggle() }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(showLater ? "Hide later vaccines" : "Show later vaccines")
                                        .font(.subheadline.weight(.semibold))
                                    Text(later.map(\.title).joined(separator: ", "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.down")
                                    .font(.subheadline.weight(.semibold))
                                    .rotationEffect(.degrees(showLater ? 180 : 0))
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .listRowBackground(Theme.card)

                    if showLater {
                        ForEach(later) { visit in
                            visitSection(visit)
                        }
                    }
                }

                Section {
                    EmptyView()
                } footer: {
                    Text("Based on the American Academy of Pediatrics' recommended schedule for healthy children. Your pediatrician may adjust timing or brands, so follow their advice. Every caregiver sees the same checklist.")
                }
            }
            .listSectionSpacing(.compact)
            .jungleBackground()
            .navigationTitle("Vaccines")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .task(id: baby.babyID) { vaccines.listen(babyID: baby.babyID) }
            .sheet(item: $editing) { dose in
                VaccineDateSheet(dose: dose, record: vaccines.given[dose.id], birthDate: baby.birthDate) { date in
                    if let date {
                        vaccines.setLocally(dose.id, VaccineRecord(givenOn: date, checkedByUid: auth.uid, checkedByName: auth.displayName))
                        VaccineRepository.markGiven(dose, on: date, babyID: baby.babyID, auth: auth)
                    } else {
                        vaccines.setLocally(dose.id, nil)
                        VaccineRepository.unmark(dose, babyID: baby.babyID)
                    }
                }
                .presentationDetents([.medium])
            }
        }
    }

    private func visitSection(_ visit: VaccineVisit) -> some View {
        Section {
            ForEach(visit.doses) { dose in row(dose) }
        } header: {
            HStack {
                JungleHeader(title: visit.title, icon: "🩹")
                Spacer()
                status(visit)
            }
        }
        .listRowBackground(Theme.card)
    }

    @ViewBuilder
    private func status(_ visit: VaccineVisit) -> some View {
        let required = visit.doses.filter { !VaccineSchedule.optionalIDs.contains($0.id) }
        let done = required.allSatisfy { vaccines.given[$0.id] != nil }
        if done && !required.isEmpty {
            chip("Done ✓", Theme.leaf)
        } else if age >= visit.toMonths {
            chip("Catch up", Theme.mango)
        } else if age >= visit.fromMonths {
            chip("Due now", Theme.hibiscus)
        } else {
            chip("Coming up", Theme.river)
        }
    }

    private func chip(_ text: String, _ tint: Color) -> some View {
        Text(text)
            .font(.caption.weight(.heavy))
            .textCase(nil)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundStyle(tint)
            .background(tint.opacity(0.16), in: Capsule())
    }

    private func row(_ dose: VaccineDose) -> some View {
        let record = vaccines.given[dose.id]
        return Button {
            if record == nil {
                let today = Date()
                vaccines.setLocally(dose.id, VaccineRecord(givenOn: today, checkedByUid: auth.uid, checkedByName: auth.displayName))
                VaccineRepository.markGiven(dose, on: today, babyID: baby.babyID, auth: auth)
            } else {
                editing = dose
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: record == nil ? "circle" : "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(record == nil ? Color.secondary : Theme.leaf)
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(dose.short).font(.body.weight(.bold))
                        Text(dose.dose).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text(dose.protects).font(.subheadline).foregroundStyle(.secondary)
                    if let record {
                        Text("Given \(record.givenOn.formatted(date: .abbreviated, time: .omitted)) · checked by \(record.checkedByName)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.leaf)
                    } else if let note = dose.note {
                        Text(note).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.success, trigger: record != nil)
        .contextMenu {
            Button("Change date…", systemImage: "calendar") { editing = dose }
            if record != nil {
                Button("Uncheck", systemImage: "xmark.circle", role: .destructive) {
                    vaccines.setLocally(dose.id, nil)
                    VaccineRepository.unmark(dose, babyID: baby.babyID)
                }
            }
        }
    }
}

private struct VaccineSummaryCard: View {
    let baby: Baby
    let due: Int
    let given: Int

    var body: some View {
        HStack(spacing: 14) {
            MascotBadge(animal: Theme.vaccineAnimal, tint: Theme.vaccine, size: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(baby.ageDescription).font(.caption.weight(.heavy)).foregroundStyle(.secondary)
                Text(due == 0 ? "All caught up 🎉" : "\(due) shot\(due == 1 ? "" : "s") due for \(baby.name)")
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(due == 0 ? Theme.leaf : Theme.vaccine)
                Text("Tap a shot to check it off. \(given) given so far.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [Theme.vaccine.opacity(0.2), Theme.vaccine.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// Change when a shot was given, or uncheck it.
private struct VaccineDateSheet: View {
    let dose: VaccineDose
    let record: VaccineRecord?
    let birthDate: Date
    let onDone: (Date?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var date: Date

    init(dose: VaccineDose, record: VaccineRecord?, birthDate: Date, onDone: @escaping (Date?) -> Void) {
        self.dose = dose
        self.record = record
        self.birthDate = birthDate
        self.onDone = onDone
        _date = State(initialValue: record?.givenOn ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Given on", selection: $date, in: min(birthDate, Date())...Date(), displayedComponents: .date)
                } header: {
                    Text("\(dose.short) · \(dose.dose)")
                }
                if record != nil {
                    Section {
                        Button("Uncheck this shot", role: .destructive) {
                            onDone(nil)
                            dismiss()
                        }
                    }
                }
            }
            .jungleBackground()
            .navigationTitle(dose.short)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onDone(date)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
