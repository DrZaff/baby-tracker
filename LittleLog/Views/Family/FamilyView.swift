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
    @State private var confirmingDelete = false
    @State private var isDeleting = false
    @State private var deleteError: String?

    private var isOwner: Bool { baby.ownerUid == auth.uid || baby.ownerEmail == auth.email }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [Theme.leaf, Theme.canopy], startPoint: .topLeading, endPoint: .bottomTrailing))
                            Text(String(baby.name.prefix(1)).uppercased())
                                .font(.system(size: 30, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                            Text(Theme.decor.accent).font(.system(size: 20)).offset(x: 24, y: -24)
                        }
                        .frame(width: 64, height: 64)
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
                    JungleHeader(title: "Caregivers", icon: Theme.decor.caregiversIcon)
                } footer: {
                    Text("Anyone listed here can sign in with that email, using Google or Apple, to see and log everything for \(baby.name), and gets a notification when something new is logged.")
                }

                Section {
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
                } header: {
                    JungleHeader(title: "Babies", icon: Theme.decor.babiesIcon)
                }

                Section {
                    ThemePicker()
                        .listRowInsets(EdgeInsets(top: 10, leading: 8, bottom: 10, trailing: 8))
                } header: {
                    JungleHeader(title: "Theme", icon: "🎨")
                } footer: {
                    Text("Changes the colors, animals and pictures on this phone only. Everything works the same in every theme.")
                }

                Section {
                    Toggle("Metric by default (ml, kg)", isOn: $useMetric)
                    Picker(selection: Binding(
                        get: { baby.feedReminderHours ?? 0 },
                        set: { store.setFeedReminder(hours: $0 > 0 ? $0 : nil, for: baby) }
                    )) {
                        Text("Off").tag(0.0)
                        ForEach([2.0, 2.5, 3.0, 3.5, 4.0, 5.0, 6.0], id: \.self) { hours in
                            Text(hours == hours.rounded() ? "After \(Int(hours)) hours" : "After \(String(format: "%.1f", hours)) hours").tag(hours)
                        }
                    } label: {
                        Label { Text("Feed reminder") } icon: { Text("⏰") }
                    }
                    Toggle(isOn: Binding(
                        get: { baby.vitaminDReminder == true },
                        set: { store.setVitaminDReminder($0, for: baby) }
                    )) {
                        Label { Text("Vitamin D reminder") } icon: { Text("☀️") }
                    }
                    .tint(Theme.sunshine)
                    Button("Notification settings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                } header: {
                    JungleHeader(title: "Settings", icon: Theme.decor.settingsIcon)
                } footer: {
                    Text("The feed reminder notifies every caregiver when \(baby.name) hasn't had a breast or bottle feed for that long. The vitamin D reminder adds a daily checkbox when logging a feed, plus a Vitamin D tile on the daily report.")
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
                } footer: {
                    if auth.signedInWithApple {
                        Text("To share a baby with you, a caregiver invites the email above.")
                    }
                }

                Section {
                    Link(destination: AppLinks.privacyPolicy) {
                        Label("Privacy policy", systemImage: "hand.raised")
                    }
                    Link(destination: AppLinks.support) {
                        Label("Help and contact", systemImage: "questionmark.circle")
                    }
                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: {
                        HStack {
                            Label("Delete my account", systemImage: "trash")
                            if isDeleting { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(isDeleting)
                } footer: {
                    Text("Deleting your account removes your sign-in and takes you off every baby's caregiver list. Babies only you can see are deleted with everything logged for them. Babies shared with others stay for them.")
                }
            }
            .jungleBackground()
            .navigationTitle("Family")
            .sheet(isPresented: $editingBaby) {
                NavigationStack { BabyFormView(mode: .edit(baby)) }
            }
            .sheet(isPresented: $addingBaby) {
                NavigationStack { BabyFormView(mode: .create) }
            }
            .alert("Invite a caregiver", isPresented: $inviting) {
                TextField("their.email@gmail.com", text: $inviteEmail)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Invite") { store.addCaregiver(email: inviteEmail, to: baby) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Enter the email they'll sign in with: their Google email, or for Apple sign-in, the email shown in their Family tab. Then send them the app.")
            }
            .confirmationDialog("Delete your Little Log account?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete account", role: .destructive) {
                    isDeleting = true
                    Task {
                        do {
                            try await auth.deleteAccount(babies: store.babies)
                        } catch {
                            deleteError = error.localizedDescription
                        }
                        isDeleting = false
                    }
                }
            } message: {
                Text("This can't be undone. You'll be asked to confirm with Google or Apple first.")
            }
            .alert("Couldn't delete your account", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteError ?? "")
            }
            .confirmationDialog("Stop seeing \(baby.name)'s log?", isPresented: $confirmingLeave, titleVisibility: .visible) {
                Button("Leave", role: .destructive) {
                    if let email = auth.email { store.removeCaregiver(email: email, from: baby) }
                }
            }
        }
    }
}

/// Five little theme cards; tapping one redraws the app in that look.
struct ThemePicker: View {
    @AppStorage(AppTheme.storageKey) private var selected = AppTheme.jungle.rawValue

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AppTheme.allCases) { theme in
                let isOn = selected == theme.rawValue
                let palette = theme.palette
                Button {
                    withAnimation { selected = theme.rawValue }
                } label: {
                    VStack(spacing: 6) {
                        Text(theme.art.feed)
                            .font(.system(size: 26))
                            .frame(width: 50, height: 50)
                            .background(
                                Circle().fill(LinearGradient(
                                    colors: [color(palette.lime.light), color(palette.leaf.light)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ))
                            )
                            .overlay(Circle().strokeBorder(isOn ? color(palette.canopy.light) : .clear, lineWidth: 3))
                        Text(theme.name)
                            .font(.caption2.weight(isOn ? .heavy : .semibold))
                            .foregroundStyle(isOn ? Theme.canopy : .secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(isOn ? Theme.canopy.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(BouncyButtonStyle())
                .accessibilityLabel("\(theme.name) theme")
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selected)
    }

    private func color(_ hex: UInt32) -> Color { Color(uiColor: UIColor(hex: hex)) }
}
