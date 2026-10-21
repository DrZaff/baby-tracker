import SwiftUI

/// A sample-data mode for checking the design without signing in.
/// Debug builds only: launch with `-designPreview -screen today` (see the "Screenshots" workflow).
enum DesignPreview {
    static let isOn: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-designPreview")
        #else
        return false
        #endif
    }()

    static var screen: String {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-screen"), index + 1 < args.count else { return "today" }
        return args[index + 1]
    }

    static let babyID = "preview-baby"
}

enum DemoData {
    static let baby: Baby = {
        var baby = Baby(
            name: "Theo",
            birthDate: Calendar.current.date(byAdding: .day, value: -74, to: Date()) ?? Date(),
            sex: .boy,
            ownerUid: "brandon",
            ownerEmail: "brandon@gmail.com",
            memberEmails: ["brandon@gmail.com", "danielle@gmail.com", "grandma.sue@gmail.com"],
            createdAt: Date(),
            feedReminderHours: 3,
            vitaminDReminder: true
        )
        baby.id = DesignPreview.babyID
        return baby
    }()

    private static func at(_ daysAgo: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        let day = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    private static func entry(_ kind: EntryKind, _ date: Date, by name: String, _ fill: (inout LogEntry) -> Void) -> LogEntry {
        var entry = LogEntry(kind: kind, timestamp: date, createdByUid: name.lowercased(), createdByName: name)
        entry.id = "\(kind.rawValue)-\(Int(date.timeIntervalSince1970))"
        fill(&entry)
        return entry
    }

    /// Several weeks of realistic entries, newest first. Today's entries stop before the current time.
    static let entries: [LogEntry] = {
        var list: [LogEntry] = []
        let now = Date()
        for day in 0..<45 {
            let who = day % 2 == 0 ? "Danielle" : "Brandon"
            for (index, hour) in [1, 4, 7, 10, 13, 16, 19, 22].enumerated() {
                let time = at(day, hour, (day * 7 + index * 11) % 50)
                list.append(entry(.feed, time, by: index % 3 == 0 ? "Brandon" : "Danielle") { e in
                    if index % 2 == 0 {
                        e.breastLeftSeconds = 540 + (day * 13 + index * 29) % 300
                        e.breastRightSeconds = 480 + (day * 17 + index * 23) % 300
                        e.breastLastSide = index % 4 == 0 ? .right : .left
                    } else {
                        e.bottleML = 90 + Double((day * 3 + index * 5) % 40)
                        e.bottleContent = index == 3 ? .mix : (index == 5 ? .breastMilk : .formula)
                        if e.bottleContent == .mix {
                            e.bottleFormulaML = 60
                            e.bottleBreastMilkML = (e.bottleML ?? 90) - 60
                        }
                    }
                    if index == 2 { e.vitaminD = true }
                })
                list.append(entry(.diaper, time.addingTimeInterval(1500), by: who) { e in
                    e.wet = true
                    e.dirty = index % 3 == 1
                })
            }
            for (index, hour) in [9, 15].enumerated() {
                list.append(entry(.tummy, at(day, hour, 20), by: who) { e in
                    e.tummySeconds = 240 + (day * 31 + index * 47) % 420
                })
            }
            if day % 3 == 0 {
                list.append(entry(.feed, at(day, 11, 30), by: "Danielle") { e in
                    e.pumpLeftSeconds = 720
                    e.pumpRightSeconds = 660
                    e.pumpedML = 110
                })
            }
        }
        for (index, week) in [0, 2, 4, 6, 8, 10].enumerated() {
            let daysAgo = 74 - week * 7
            guard daysAgo >= 0 else { continue }
            list.append(entry(.weight, at(daysAgo, 10), by: "Brandon") { e in
                e.weightGrams = 3400 + Double(index) * 420
                e.lengthCm = 50 + Double(index) * 1.6
                e.headCm = 34.5 + Double(index) * 0.7
                e.metric = false
            })
        }
        list.append(entry(.milestone, at(0, 8, 15), by: "Danielle") { e in e.title = "First real smile" })
        list.append(entry(.milestone, at(12, 17), by: "Brandon") { e in e.title = "Held head up" })
        return list.filter { $0.timestamp <= now }.sorted { $0.timestamp > $1.timestamp }
    }()

    static func entries(from start: Date, to end: Date?) -> [LogEntry] {
        entries.filter { $0.timestamp >= start && (end == nil || $0.timestamp < end!) }
    }

    static let appointments: [Appointment] = {
        let calendar = Calendar.current
        let month = calendar.dateInterval(of: .month, for: Date())?.start ?? Date()
        func on(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let date = calendar.date(byAdding: .day, value: day - 1, to: month) ?? month
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
        }
        let today = calendar.component(.day, from: Date())
        let items: [(AppointmentKind, String?, Date, String?)] = [
            (.wellChild, "2-month checkup", on(4, 9, 30), "Sunnyvale Pediatrics"),
            (.vaccines, nil, on(4, 10, 15), "Sunnyvale Pediatrics"),
            (.lactation, nil, on(today, 14), "Mothers' Milk Center"),
            (.dentist, nil, on(min(today + 3, 28), 11), nil),
            (.specialist, "Hip ultrasound", on(min(today + 8, 28), 8, 45), "Children's Hospital"),
            (.other, "Newborn photos", on(min(today + 8, 28), 15), nil),
            (.sick, nil, on(min(today + 8, 28), 17), nil),
        ]
        return items.enumerated().map { index, item in
            var appointment = Appointment(
                kind: item.0, title: item.1, start: item.2, durationMinutes: 30, location: item.3,
                createdByUid: "danielle", createdByName: "Danielle"
            )
            appointment.id = "appt-\(index)"
            return appointment
        }.sorted { $0.start < $1.start }
    }()
}

/// Shows one screen filled with sample data, for design checks and screenshots.
struct DesignPreviewRoot: View {
    @State private var auth = AuthService()
    @State private var babyStore = BabyStore()

    var body: some View {
        content
            .environment(auth)
            .environment(babyStore)
            .tint(Theme.canopy)
            .fontDesign(.rounded)
            .onAppear { babyStore.showDemo() }
    }

    @ViewBuilder private var content: some View {
        let baby = DemoData.baby
        switch DesignPreview.screen {
        case "signin": SignInView()
        case "feed": NavigationStack { FeedFormView(babyID: baby.babyID, existing: nil, defaultDate: Date()) }
        case "tummy": NavigationStack { TummyTimeFormView(babyID: baby.babyID, existing: nil, defaultDate: Date()) }
        case "diaper": NavigationStack { DiaperFormView(babyID: baby.babyID, existing: nil, defaultDate: Date()) }
        case "growth": NavigationStack { WeightFormView(babyID: baby.babyID, existing: nil, defaultDate: Date()) }
        case "milestone": NavigationStack { MilestoneFormView(babyID: baby.babyID, existing: nil, defaultDate: Date()) }
        case "appointments": AppointmentsView(baby: baby)
        case "newAppointment": NavigationStack { AppointmentFormView(baby: baby, existing: nil, defaultDate: Date()) }
        case "babyForm": NavigationStack { BabyFormView(mode: .create, isFirstBaby: true) }
        default: MainTabView()
        }
    }
}
