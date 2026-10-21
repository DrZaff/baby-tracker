import SwiftUI

/// Every appointment for the baby, by week, month or year, shared with all caregivers.
struct AppointmentsView: View {
    let baby: Baby

    enum Period: String, CaseIterable, Identifiable {
        case week = "Week", month = "Month", year = "Year"
        var id: String { rawValue }
        var component: Calendar.Component {
            switch self {
            case .week: return .weekOfYear
            case .month: return .month
            case .year: return .year
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var period: Period = .month
    @State private var anchor = Date()
    @State private var listener = AppointmentsListener()
    @State private var editing: Appointment?
    @State private var adding = false

    private var calendar: Calendar { Calendar.current }

    private var interval: DateInterval {
        calendar.dateInterval(of: period.component, for: anchor) ?? DateInterval(start: anchor, duration: 86_400)
    }

    private var periodLabel: String {
        let interval = self.interval
        switch period {
        case .week:
            let last = interval.end.addingTimeInterval(-1)
            return "\(interval.start.formatted(.dateTime.month(.abbreviated).day())) – \(last.formatted(.dateTime.month(.abbreviated).day()))"
        case .month: return interval.start.formatted(.dateTime.month(.wide).year())
        case .year: return interval.start.formatted(.dateTime.year())
        }
    }

    private struct Group: Identifiable {
        let title: String
        var items: [Appointment]
        var id: String { title }
    }

    /// Appointments grouped by day (week and month) or by month (year).
    private var groups: [Group] {
        var result: [Group] = []
        for appointment in listener.appointments {
            let title = period == .year
                ? appointment.start.formatted(.dateTime.month(.wide))
                : dayTitle(appointment.start)
            if result.last?.title == title {
                result[result.count - 1].items.append(appointment)
            } else {
                result.append(Group(title: title, items: [appointment]))
            }
        }
        return result
    }

    private func dayTitle(_ date: Date) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 12) {
                        Picker("Period", selection: $period) {
                            ForEach(Period.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        HStack {
                            Button { shift(-1) } label: { Image(systemName: "chevron.left.circle.fill").font(.title2) }
                            Spacer()
                            VStack(spacing: 2) {
                                Text(periodLabel).font(.headline)
                                if !interval.contains(Date()) {
                                    Button("Back to now") { withAnimation(.snappy) { anchor = Date() } }
                                        .font(.caption.weight(.semibold))
                                }
                            }
                            Spacer()
                            Button { shift(1) } label: { Image(systemName: "chevron.right.circle.fill").font(.title2) }
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Theme.canopy)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))

                if listener.hasLoaded && listener.appointments.isEmpty {
                    Section {
                        HStack(spacing: 12) {
                            Text("🦉").font(.largeTitle)
                            Text("No appointments this \(period.rawValue.lowercased()). Tap + to add one.")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                    .listRowBackground(Theme.card)
                }

                ForEach(groups) { group in
                    Section {
                        ForEach(group.items) { appointment in
                            Button { editing = appointment } label: {
                                AppointmentRow(appointment: appointment, showDate: period == .year)
                            }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button(role: .destructive) {
                                    AppointmentRepository.delete(appointment, babyID: baby.babyID)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .contextMenu {
                                if let url = appointment.googleCalendarURL(babyName: baby.name) {
                                    Link(destination: url) {
                                        Label("Add to Google Calendar", systemImage: "calendar.badge.plus")
                                    }
                                }
                            }
                        }
                    } header: {
                        JungleHeader(title: group.title, icon: group.title == "Today" ? "⭐️" : "🍃")
                    }
                    .listRowBackground(Theme.card)
                }
            }
            .listSectionSpacing(.compact)
            .jungleBackground()
            .navigationTitle("🦉 Appointments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { adding = true } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                        .accessibilityLabel("Add appointment")
                }
            }
            .sheet(isPresented: $adding) {
                NavigationStack {
                    AppointmentFormView(baby: baby, existing: nil, defaultDate: defaultDate)
                }
            }
            .sheet(item: $editing) { appointment in
                NavigationStack {
                    AppointmentFormView(baby: baby, existing: appointment, defaultDate: appointment.start)
                }
            }
            .task(id: "\(baby.babyID)|\(interval.start.timeIntervalSince1970)|\(period.rawValue)") {
                listener.listen(babyID: baby.babyID, from: interval.start, to: interval.end)
            }
        }
    }

    /// New appointments start tomorrow at 9:00, or inside the period being viewed.
    private var defaultDate: Date {
        let base = interval.contains(Date())
            ? (calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date())
            : interval.start
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: base) ?? base
    }

    private func shift(_ amount: Int) {
        if let next = calendar.date(byAdding: period.component, value: amount, to: anchor) {
            withAnimation(.snappy) { anchor = next }
        }
    }
}

struct AppointmentRow: View {
    let appointment: Appointment
    var showDate = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            MascotBadge(animal: appointment.kind.emoji, tint: Theme.river)
            VStack(alignment: .leading, spacing: 2) {
                Text(appointment.displayTitle).font(.body.weight(.bold))
                Text(showDate
                     ? "\(appointment.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) · \(appointment.timeText)"
                     : appointment.timeText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let location = appointment.location?.trimmedOrNil {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let notes = appointment.notes?.trimmedOrNil {
                    Text(notes).font(.footnote).foregroundStyle(.secondary).italic().lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }
}

struct AppointmentFormView: View {
    let baby: Baby
    let existing: Appointment?

    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var kind: AppointmentKind
    @State private var title: String
    @State private var start: Date
    @State private var duration: Int
    @State private var location: String
    @State private var notes: String
    @State private var confirmingDelete = false
    @State private var errorMessage: String?

    private static let durations = [15, 30, 45, 60, 90, 120]

    init(baby: Baby, existing: Appointment?, defaultDate: Date) {
        self.baby = baby
        self.existing = existing
        _kind = State(initialValue: existing?.kind ?? .wellChild)
        _title = State(initialValue: existing?.title ?? "")
        _start = State(initialValue: existing?.start ?? defaultDate)
        _duration = State(initialValue: existing?.durationMinutes ?? 30)
        _location = State(initialValue: existing?.location ?? "")
        _notes = State(initialValue: existing?.notes ?? "")
    }

    private var draft: Appointment {
        var appointment = existing ?? Appointment(
            kind: kind, start: start, durationMinutes: duration,
            createdByUid: auth.uid, createdByName: auth.displayName
        )
        appointment.kind = kind
        appointment.title = title.trimmedOrNil
        appointment.start = start
        appointment.durationMinutes = duration
        appointment.location = location.trimmedOrNil
        appointment.notes = notes.trimmedOrNil
        return appointment
    }

    var body: some View {
        Form {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(AppointmentKind.allCases) { option in
                            Button {
                                kind = option
                            } label: {
                                Text("\(option.emoji) \(option.label)")
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(kind == option ? Theme.river.opacity(0.25) : Color.secondary.opacity(0.1), in: Capsule())
                                    .overlay(Capsule().strokeBorder(kind == option ? Theme.river : .clear, lineWidth: 1.5))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                TextField("Name (optional), like \"2-month checkup\"", text: $title)
            } header: {
                Text("What kind")
            }

            Section("When") {
                DatePicker("Starts", selection: $start)
                Picker("Length", selection: $duration) {
                    ForEach(Self.durations, id: \.self) { minutes in
                        Text(minutes < 60 ? "\(minutes) min" : minutes % 60 == 0 ? "\(minutes / 60) hr" : "1½ hr").tag(minutes)
                    }
                }
            }

            Section("Details") {
                TextField("Where, like \"Dr. Lee, Sunnyvale Pediatrics\"", text: $location)
                TextField("Notes, like questions to ask", text: $notes, axis: .vertical)
            }

            Section {
                Button {
                    if let url = draft.googleCalendarURL(babyName: baby.name) { openURL(url) }
                } label: {
                    Label("Add to Google Calendar", systemImage: "calendar.badge.plus")
                }
            } footer: {
                Text("Opens Google Calendar with the appointment filled in, so you can save it to your own calendar.")
            }

            if existing != nil {
                Section {
                    Button("Delete appointment", role: .destructive) { confirmingDelete = true }
                        .frame(maxWidth: .infinity)
                } footer: {
                    if let existing {
                        Text("Added by \(existing.createdByName)" + (existing.updatedByName.map { ", last edited by \($0)" } ?? ""))
                    }
                }
            }
        }
        .jungleBackground()
        .navigationTitle(existing == nil ? "New appointment" : "Edit appointment")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    do {
                        try AppointmentRepository.save(draft, babyID: baby.babyID, auth: auth)
                        dismiss()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                .fontWeight(.semibold)
            }
        }
        .confirmationDialog("Delete this appointment for everyone?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let existing { AppointmentRepository.delete(existing, babyID: baby.babyID) }
                dismiss()
            }
        }
        .alert("Couldn't save", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }
}

/// Today's appointments, shown compactly at the top of the Today screen.
struct TodayAppointmentsCard: View {
    let appointments: [Appointment]
    let openAll: () -> Void

    var body: some View {
        Button(action: openAll) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("🦉 Today's appointments").font(.caption.weight(.heavy)).foregroundStyle(Theme.river)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                }
                ForEach(appointments) { appointment in
                    HStack(spacing: 8) {
                        Text(appointment.kind.emoji)
                        Text(appointment.start.formatted(date: .omitted, time: .shortened))
                            .font(.subheadline.weight(.bold).monospacedDigit())
                        Text(appointment.displayTitle).font(.subheadline).lineLimit(1)
                        if let location = appointment.location?.trimmedOrNil {
                            Text("· \(location)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.river.opacity(0.2), Theme.lagoon.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.river.opacity(0.25)))
        }
        .buttonStyle(BouncyButtonStyle())
    }
}
