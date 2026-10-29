import SwiftUI

/// Every appointment for the baby on a month calendar, shared with all caregivers.
struct AppointmentsView: View {
    let baby: Baby

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(BabyStore.self) private var store
    @State private var choosingSubscription = false
    @State private var month = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var listener = AppointmentsListener()
    @State private var editing: Appointment?
    @State private var adding = false
    @State private var appleEvent: Appointment?

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
                            Button { appleEvent = appointment } label: {
                                Label("Add to Apple Calendar", systemImage: "calendar.badge.plus")
                            }
                            if let url = appointment.googleCalendarURL(babyName: baby.name) {
                                Link(destination: url) {
                                    Label("Add to Google Calendar", systemImage: "calendar.badge.plus")
                                }
                            }
                            if let url = appointment.outlookCalendarURL(babyName: baby.name) {
                                Link(destination: url) {
                                    Label("Add to Outlook", systemImage: "calendar.badge.plus")
                                }
                            }
                        }
                    }
                } header: {
                    JungleHeader(title: dayTitle(selectedDay), icon: calendar.isDateInToday(selectedDay) ? "⭐️" : "🍃")
                }
                .listRowBackground(Theme.card)

                Section {
                    Button { choosingSubscription = true } label: {
                        HStack(spacing: 12) {
                            MascotBadge(animal: "📆", tint: Theme.river)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Subscribe in my calendar").font(.body.weight(.bold)).foregroundStyle(.primary)
                                Text("Every appointment shows up in your Apple, Google or Outlook calendar and stays up to date.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                } footer: {
                    Text("Each caregiver subscribes once on their own phone. Apple Calendar picks up changes within about an hour; Google and Outlook can take up to a day.")
                }
                .listRowBackground(Theme.card)
            }
            .listSectionSpacing(.compact)
            .jungleBackground()
            .navigationTitle("\(Theme.appointmentAnimal) Appointments")
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
            .sheet(item: $appleEvent) { appointment in
                AppleCalendarSheet(appointment: appointment, babyName: baby.name) { appleEvent = nil }
                    .ignoresSafeArea()
            }
            .confirmationDialog("Subscribe to \(baby.name)'s appointments", isPresented: $choosingSubscription, titleVisibility: .visible) {
                Button("Apple Calendar") { subscribe(AppLinks.appleCalendarFeed) }
                Button("Google Calendar") { subscribe(AppLinks.googleCalendarFeed) }
                Button("Outlook") { subscribe(AppLinks.outlookCalendarFeed) }
            } message: {
                Text("Pick the calendar app you use. You only need to do this once.")
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

    private func subscribe(_ link: (String, String) -> URL?) {
        let current = store.babies.first { $0.id == baby.id } ?? baby
        if let url = link(baby.babyID, store.calendarKey(for: current)) { openURL(url) }
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
    @AppStorage("appointmentCalendar") private var savedChoice = CalendarChoice.none.rawValue
    @State private var calendarChoice: CalendarChoice = .none
    @State private var appleEvent: Appointment?
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
        // Remember the calendar picked last time for new appointments.
        let saved = CalendarChoice(rawValue: UserDefaults.standard.string(forKey: "appointmentCalendar") ?? "") ?? .none
        _calendarChoice = State(initialValue: existing == nil ? saved : .none)
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
                TextField("Name (optional)", text: $title)
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
                TextField("Where", text: $location)
                TextField("Notes or questions to ask", text: $notes, axis: .vertical)
            }

            Section {
                Picker("Add to my calendar", selection: $calendarChoice) {
                    ForEach(CalendarChoice.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.vertical, 4)
            } header: {
                Text("Add to my calendar")
            } footer: {
                switch calendarChoice {
                case .none: Text("It's saved in Little Log for everyone either way. To have every appointment show up in your calendar automatically, use Subscribe on the Appointments screen.")
                case .apple: Text("After you tap Save, the iPhone's calendar opens so you can pick which calendar to add it to.")
                case .google: Text("After you tap Save, Google Calendar opens with the appointment filled in.")
                case .outlook: Text("After you tap Save, Outlook opens with the appointment filled in. Sign in with your Outlook.com account if asked.")
                }
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
                        if existing == nil { savedChoice = calendarChoice.rawValue }
                        if calendarChoice == .apple {
                            appleEvent = appointment
                        } else {
                            finish(appointment)
                        }
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                .fontWeight(.semibold)
            }
        }
        .sheet(item: $appleEvent) { appointment in
            AppleCalendarSheet(appointment: appointment, babyName: baby.name) {
                appleEvent = nil
                finish(appointment)
            }
            .ignoresSafeArea()
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

    /// Opens Google Calendar or Outlook when it was picked, then closes the form.
    private func finish(_ appointment: Appointment) {
        if calendarChoice == .google, let url = appointment.googleCalendarURL(babyName: baby.name) {
            openURL(url)
        } else if calendarChoice == .outlook, let url = appointment.outlookCalendarURL(babyName: baby.name) {
            openURL(url)
        }
        dismiss()
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
                    Text("\(Theme.appointmentAnimal) Today's appointments").font(.caption.weight(.heavy)).foregroundStyle(Theme.river)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                }
                ForEach(appointments) { appointment in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(appointment.kind.emoji)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(appointment.start.formatted(date: .omitted, time: .shortened))
                                    .font(.subheadline.weight(.bold).monospacedDigit())
                                    .fixedSize()
                                Text(appointment.displayTitle)
                                    .font(.subheadline)
                                    .lineLimit(1)
                            }
                            if let location = appointment.location?.trimmedOrNil {
                                Text(location).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
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
