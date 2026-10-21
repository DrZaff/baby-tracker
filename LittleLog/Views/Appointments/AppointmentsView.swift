import SwiftUI

/// Every appointment for the baby on a month calendar, shared with all caregivers.
struct AppointmentsView: View {
    let baby: Baby

    @Environment(\.dismiss) private var dismiss
    @State private var month = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var listener = AppointmentsListener()
    @State private var editing: Appointment?
    @State private var adding = false

    private var calendar: Calendar { Calendar.current }

    private var interval: DateInterval {
        calendar.dateInterval(of: .month, for: month) ?? DateInterval(start: month, duration: 86_400 * 31)
    }

    private var selectedAppointments: [Appointment] {
        listener.appointments.filter { calendar.isDate($0.start, inSameDayAs: selectedDay) }
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
                        HStack {
                            Button { shift(-1) } label: { Image(systemName: "chevron.left.circle.fill").font(.title2) }
                            Spacer()
                            VStack(spacing: 2) {
                                Text(interval.start.formatted(.dateTime.month(.wide).year())).font(.headline)
                                if !interval.contains(Date()) {
                                    Button("Back to today") { goToToday() }
                                        .font(.caption.weight(.semibold))
                                }
                            }
                            Spacer()
                            Button { shift(1) } label: { Image(systemName: "chevron.right.circle.fill").font(.title2) }
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Theme.canopy)
                        MonthGrid(
                            month: interval,
                            appointments: listener.appointments,
                            selectedDay: $selectedDay
                        )
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 30).onEnded { drag in
                            guard abs(drag.translation.width) > abs(drag.translation.height) else { return }
                            shift(drag.translation.width < 0 ? 1 : -1)
                        }
                    )
                }
                .listRowBackground(Theme.card)

                Section {
                    if selectedAppointments.isEmpty {
                        HStack(spacing: 12) {
                            Text("🦉").font(.largeTitle)
                            Text(listener.hasLoaded ? "Nothing on this day. Tap + to add an appointment." : "Loading…")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                    ForEach(selectedAppointments) { appointment in
                        Button { editing = appointment } label: {
                            AppointmentRow(appointment: appointment)
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
                    JungleHeader(title: dayTitle(selectedDay), icon: calendar.isDateInToday(selectedDay) ? "⭐️" : "🍃")
                }
                .listRowBackground(Theme.card)
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
            .task(id: "\(baby.babyID)|\(interval.start.timeIntervalSince1970)") {
                listener.listen(babyID: baby.babyID, from: interval.start, to: interval.end)
            }
        }
    }

    /// New appointments go on the selected day at 9:00, or the next hour if that has passed.
    private var defaultDate: Date {
        let nine = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: selectedDay) ?? selectedDay
        guard nine < Date() else { return nine }
        let nextHour = calendar.dateInterval(of: .hour, for: Date())?.end ?? Date()
        return calendar.isDate(nextHour, inSameDayAs: selectedDay) ? nextHour : nine
    }

    private func shift(_ amount: Int) {
        guard let next = calendar.date(byAdding: .month, value: amount, to: interval.start) else { return }
        withAnimation(.snappy) {
            month = next
            // Keep today selected when coming back to this month, otherwise pick the 1st.
            selectedDay = calendar.isDate(Date(), equalTo: next, toGranularity: .month)
                ? calendar.startOfDay(for: Date())
                : next
        }
    }

    private func goToToday() {
        withAnimation(.snappy) {
            month = calendar.dateInterval(of: .month, for: Date())?.start ?? Date()
            selectedDay = calendar.startOfDay(for: Date())
        }
    }
}

/// A traditional month calendar. Days with appointments show their emoji.
struct MonthGrid: View {
    let month: DateInterval
    let appointments: [Appointment]
    @Binding var selectedDay: Date

    private struct Cell: Identifiable {
        let id: Int
        let date: Date?
    }

    private struct Weekday: Identifiable {
        let id: Int
        let symbol: String
    }

    private var calendar: Calendar { Calendar.current }

    private var weekdays: [Weekday] {
        let symbols = calendar.veryShortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return (0..<7).map { Weekday(id: $0, symbol: symbols[(first + $0) % 7]) }
    }

    /// Blank cells before the 1st so each day lands under its weekday, then every day of the month.
    private var cells: [Cell] {
        let leading = (calendar.component(.weekday, from: month.start) - calendar.firstWeekday + 7) % 7
        let days = calendar.range(of: .day, in: .month, for: month.start)?.count ?? 30
        var result = (0..<leading).map { Cell(id: $0, date: nil) }
        for day in 0..<days {
            result.append(Cell(id: leading + day, date: calendar.date(byAdding: .day, value: day, to: month.start)))
        }
        return result
    }

    private var byDay: [Date: [Appointment]] {
        Dictionary(grouping: appointments) { calendar.startOfDay(for: $0.start) }
    }

    var body: some View {
        let byDay = self.byDay
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(weekdays) { weekday in
                Text(weekday.symbol)
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(.secondary)
            }
            ForEach(cells) { cell in
                if let date = cell.date {
                    DayCell(
                        date: date,
                        appointments: byDay[date] ?? [],
                        isSelected: calendar.isDate(date, inSameDayAs: selectedDay),
                        isToday: calendar.isDateInToday(date)
                    )
                    .onTapGesture {
                        withAnimation(.snappy) { selectedDay = date }
                    }
                } else {
                    Color.clear.frame(height: 52)
                }
            }
        }
    }
}

private struct DayCell: View {
    let date: Date
    let appointments: [Appointment]
    let isSelected: Bool
    let isToday: Bool

    var body: some View {
        VStack(spacing: 2) {
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.subheadline.weight(isToday || isSelected ? .heavy : .medium).monospacedDigit())
                .foregroundStyle(isSelected ? .white : isToday ? Theme.river : .primary)
                .frame(width: 28, height: 28)
                .background {
                    if isSelected {
                        Circle().fill(Theme.river)
                    } else if isToday {
                        Circle().strokeBorder(Theme.river, lineWidth: 1.5)
                    }
                }
            HStack(spacing: 0) {
                ForEach(appointments.prefix(2)) { appointment in
                    Text(appointment.kind.emoji).font(.system(size: 11))
                }
                if appointments.count > 2 {
                    Text("+\(appointments.count - 2)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 14)
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(appointments.isEmpty ? Color.clear : Theme.river.opacity(0.1))
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
        .accessibilityValue(appointments.isEmpty ? "No appointments" : appointments.map(\.displayTitle).joined(separator: ", "))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
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
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.and.ellipse")
                        Text(location).lineLimit(1)
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
    @State private var addToMyCalendar = false
    @State private var invited: Set<String> = []
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
        let everInvited = Set(existing?.invitedEmails ?? []).union(invited)
        appointment.invitedEmails = everInvited.isEmpty ? nil : everInvited.sorted()
        return appointment
    }

    /// Everyone else who shares this baby.
    private var otherCaregivers: [String] {
        baby.memberEmails.filter { $0.lowercased() != auth.email }.sorted()
    }

    private var opensCalendar: Bool { addToMyCalendar || !invited.isEmpty }

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
                CheckRow(title: "Add to my Google Calendar", subtitle: nil, isOn: $addToMyCalendar)
                ForEach(otherCaregivers, id: \.self) { email in
                    CheckRow(
                        title: "Invite \(email)",
                        subtitle: existing?.invitedEmails?.contains(email) == true ? "Already invited" : nil,
                        isOn: Binding(
                            get: { invited.contains(email) },
                            set: { checked in
                                if checked { invited.insert(email) } else { invited.remove(email) }
                                if checked { addToMyCalendar = true }
                            }
                        )
                    )
                }
            } header: {
                Text("Google Calendar")
            } footer: {
                Text(otherCaregivers.isEmpty
                     ? "Everyone who shares \(baby.name) sees this appointment in Little Log. Invite caregivers from the Family tab to send them calendar invites too."
                     : "Everyone who shares \(baby.name) sees this appointment in Little Log either way. Checked caregivers also get an invite at their Gmail: after you tap Save here, Google Calendar opens with them added, and they're sent the invite when you save it there.")
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
                        let appointment = draft
                        try AppointmentRepository.save(appointment, babyID: baby.babyID, auth: auth)
                        if opensCalendar, let url = appointment.googleCalendarURL(babyName: baby.name, guests: invited.sorted()) {
                            openURL(url)
                        }
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

/// A tappable checkbox row.
private struct CheckRow: View {
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.snappy) { isOn.toggle() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(isOn ? Theme.river : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.8)
                    if let subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
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
