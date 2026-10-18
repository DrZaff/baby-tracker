import SwiftUI

struct FamilyView: View {
    let baby: Baby

    @Environment(AuthService.self) private var auth
    @Environment(BabyStore.self) private var store
    @AppStorage("useMetric") private var useMetric = false

    @State private var editingBaby = false
    @State private var addingBaby = false
    @State private var inviting = false
    @State private var inviteEmail = ""
    @State private var confirmingLeave = false

    private var isOwner: Bool { baby.ownerUid == auth.uid }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Text(String(baby.name.prefix(1)).uppercased())
                            .font(.title.bold())
                            .foregroundStyle(.white)
                            .frame(width: 60, height: 60)
                            .background(Theme.feed.gradient, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(baby.name).font(.title3.bold())
                            Text(baby.ageDescription).foregroundStyle(.secondary)
                            Text("Born \(baby.birthDate.formatted(date: .long, time: .omitted))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Edit") { editingBaby = true }
                            .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    ForEach(baby.memberEmails, id: \.self) { email in
                        HStack {
                            Image(systemName: "person.crop.circle")
                                .foregroundStyle(.secondary)
                            Text(email)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            if email == baby.ownerEmail {
                                Text("Owner").font(.caption).foregroundStyle(.secondary)
                            } else if email == auth.email {
                                Text("You").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            if email != baby.ownerEmail && email != auth.email {
                                Button("Remove", role: .destructive) {
                                    store.removeCaregiver(email: email, from: baby)
                                }
                            }
                        }
                    }
                    Button {
                        inviteEmail = ""
                        inviting = true
                    } label: {
                        Label("Invite a caregiver", systemImage: "person.badge.plus")
                    }
                } header: {
                    Text("Caregivers")
                } footer: {
                    Text("Anyone listed here can sign in with that Google account to see and log everything for \(baby.name), and gets a notification when something new is logged.")
                }

                Section("Babies") {
                    ForEach(store.babies) { other in
                        Button {
                            store.select(other)
                        } label: {
                            HStack {
                                Text(other.name).foregroundStyle(.primary)
                                Spacer()
                                if other.id == baby.id {
                                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                    Button {
                        addingBaby = true
                    } label: {
                        Label("Add another baby", systemImage: "plus")
                    }
                }

                Section("Settings") {
                    Toggle("Metric by default (ml, kg)", isOn: $useMetric)
                    Button("Notification settings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }

                Section {
                    if let email = auth.email {
                        LabeledContent("Signed in as", value: email)
                    }
                    if !isOwner {
                        Button("Leave \(baby.name)'s log", role: .destructive) { confirmingLeave = true }
                    }
                    Button("Sign out", role: .destructive) {
                        Task { await auth.signOut() }
                    }
                }
            }
            .navigationTitle("Family")
            .sheet(isPresented: $editingBaby) {
                NavigationStack { BabyFormView(mode: .edit(baby)) }
            }
            .sheet(isPresented: $addingBaby) {
                NavigationStack { BabyFormView(mode: .create) }
            }
            .alert("Invite a caregiver", isPresented: $inviting) {
                TextField("their.gmail@gmail.com", text: $inviteEmail)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Invite") { store.addCaregiver(email: inviteEmail, to: baby) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Enter the Google account email they'll sign in with. Then send them the app.")
            }
            .confirmationDialog("Stop seeing \(baby.name)'s log?", isPresented: $confirmingLeave, titleVisibility: .visible) {
                Button("Leave", role: .destructive) {
                    if let email = auth.email { store.removeCaregiver(email: email, from: baby) }
                }
            }
        }
    }
}
