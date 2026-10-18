import SwiftUI

struct BabyFormView: View {
    enum Mode {
        case create
        case edit(Baby)
    }

    @Environment(AuthService.self) private var auth
    @Environment(BabyStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    var isFirstBaby = false

    @State private var name = ""
    @State private var birthDate = Date()
    @State private var sex: BabySex?
    @State private var errorMessage: String?

    init(mode: Mode, isFirstBaby: Bool = false) {
        self.mode = mode
        self.isFirstBaby = isFirstBaby
        if case .edit(let baby) = mode {
            _name = State(initialValue: baby.name)
            _birthDate = State(initialValue: baby.birthDate)
            _sex = State(initialValue: baby.sex)
        }
    }

    var body: some View {
        Form {
            if isFirstBaby {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Welcome, \(auth.displayName)")
                            .font(.title2.bold())
                        Text("Add your baby to start logging. If someone already added your baby, ask them to invite \(auth.email ?? "your email") from the Family tab.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            Section("Baby") {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.words)
                DatePicker("Birthday", selection: $birthDate, displayedComponents: [.date, .hourAndMinute])
                Picker("Sex", selection: $sex) {
                    Text("Not set").tag(BabySex?.none)
                    ForEach(BabySex.allCases) { Text($0.label).tag(BabySex?.some($0)) }
                }
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
            if isFirstBaby {
                Section {
                    Button("Sign out", role: .destructive) {
                        Task { await auth.signOut() }
                    }
                }
            }
        }
        .navigationTitle(isEditing ? "Edit profile" : "Add baby")
        .toolbar {
            if !isFirstBaby {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .fontWeight(.semibold)
                    .disabled(name.trimmedOrNil == nil)
            }
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private func save() {
        guard let trimmed = name.trimmedOrNil else { return }
        switch mode {
        case .create:
            guard let email = auth.email else { return }
            do {
                try store.createBaby(name: trimmed, birthDate: birthDate, sex: sex, ownerUid: auth.uid, ownerEmail: email)
                if !isFirstBaby { dismiss() }
            } catch {
                errorMessage = error.localizedDescription
            }
        case .edit(let baby):
            store.updateBaby(baby, name: trimmed, birthDate: birthDate, sex: sex)
            dismiss()
        }
    }
}
