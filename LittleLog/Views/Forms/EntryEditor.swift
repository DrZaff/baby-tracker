import SwiftUI

enum EntryTemplate: String, CaseIterable, Identifiable {
    case feed, sleep, diaper, tummy, weight, milestone, vaccines, appointment
    var id: String { rawValue }

    var label: String {
        switch self {
        case .feed: return "Feed"
        case .sleep: return "Sleep"
        case .vaccines: return "Vaccines"
        case .tummy: return "Tummy time"
        case .diaper: return "Diaper"
        case .weight: return "Growth"
        case .milestone: return "Milestone"
        case .appointment: return "Appointments"
        }
    }

    var animal: String {
        switch self {
        case .feed: return Theme.feedAnimal
        case .sleep: return Theme.sleepAnimal
        case .vaccines: return Theme.vaccineAnimal
        case .tummy: return Theme.tummyAnimal
        case .diaper: return Theme.diaperAnimal
        case .weight: return Theme.weightAnimal
        case .milestone: return Theme.milestoneAnimal
        case .appointment: return Theme.appointmentAnimal
        }
    }

    var tint: Color {
        switch self {
        case .feed: return Theme.feed
        case .sleep: return Theme.sleep
        case .vaccines: return Theme.vaccine
        case .tummy: return Theme.tummy
        case .diaper: return Theme.diaper
        case .weight: return Theme.weight
        case .milestone: return Theme.milestone
        case .appointment: return Theme.river
        }
    }
}

enum EntrySheet: Identifiable {
    case new(EntryTemplate)
    case edit(LogEntry)

    var id: String {
        switch self {
        case .new(let template): return "new-\(template.rawValue)"
        case .edit(let entry): return "edit-\(entry.id ?? "")"
        }
    }
}

/// Picks the right form for a new or existing entry.
struct EntryEditor: View {
    let babyID: String
    let sheet: EntrySheet
    var defaultDate: Date = Date()

    var body: some View {
        NavigationStack {
            switch sheet {
            case .new(let template):
                switch template {
                case .feed: FeedFormView(babyID: babyID, existing: nil, defaultDate: defaultDate)
                case .sleep: SleepFormView(babyID: babyID, existing: nil, defaultDate: defaultDate)
                case .tummy: TummyTimeFormView(babyID: babyID, existing: nil, defaultDate: defaultDate)
                case .diaper: DiaperFormView(babyID: babyID, existing: nil, defaultDate: defaultDate)
                case .weight: WeightFormView(babyID: babyID, existing: nil, defaultDate: defaultDate)
                case .milestone: MilestoneFormView(babyID: babyID, existing: nil, defaultDate: defaultDate)
                case .appointment, .vaccines: EmptyView() // These open their own screens instead; see TodayView.
                }
            case .edit(let entry):
                switch entry.kind {
                case .feed: FeedFormView(babyID: babyID, existing: entry, defaultDate: entry.timestamp)
                case .sleep: SleepFormView(babyID: babyID, existing: entry, defaultDate: entry.timestamp)
                case .tummy: TummyTimeFormView(babyID: babyID, existing: entry, defaultDate: entry.timestamp)
                case .diaper: DiaperFormView(babyID: babyID, existing: entry, defaultDate: entry.timestamp)
                case .weight: WeightFormView(babyID: babyID, existing: entry, defaultDate: entry.timestamp)
                case .milestone: MilestoneFormView(babyID: babyID, existing: entry, defaultDate: entry.timestamp)
                case .daycare: DaycareFormView(babyID: babyID, existing: entry, defaultDate: entry.timestamp)
                }
            }
        }
    }
}

/// Shared Cancel / Save toolbar and save handling for entry forms.
struct EntryFormToolbar: ViewModifier {
    let title: String
    let canSave: Bool
    let save: () throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    func body(content: Content) -> some View {
        content
            .jungleBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            try save()
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
            .alert("Couldn't save", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
    }
}

extension View {
    func entryFormToolbar(_ title: String, canSave: Bool = true, save: @escaping () throws -> Void) -> some View {
        modifier(EntryFormToolbar(title: title, canSave: canSave, save: save))
    }
}

/// Date for new entries: now when logging today, otherwise noon on the day being viewed.
func defaultEntryDate(for day: Date) -> Date {
    let calendar = Calendar.current
    if calendar.isDateInToday(day) { return Date() }
    return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
}
