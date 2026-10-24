import SwiftUI
import EventKit
import EventKitUI

/// Which calendar an appointment is added to on this phone.
enum CalendarChoice: String, CaseIterable, Identifiable {
    case none, apple, google, outlook
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "None"
        case .apple: return "Apple"
        case .google: return "Google"
        case .outlook: return "Outlook"
        }
    }
}

extension Appointment {
    /// A new calendar event for this appointment, for the system add-event screen.
    func calendarEvent(in store: EKEventStore, babyName: String) -> EKEvent {
        let event = EKEvent(eventStore: store)
        event.title = "\(babyName): \(displayTitle)"
        event.startDate = start
        event.endDate = end
        event.location = location?.trimmedOrNil
        var details = "\(babyName): \(kind.label)"
        if let notes = notes?.trimmedOrNil { details += "\n\n\(notes)" }
        event.notes = details + "\n\nAdded from Little Log"
        event.addAlarm(EKAlarm(relativeOffset: -3600))
        return event
    }
}

/// The iPhone's own "New Event" screen, filled in. People pick any calendar on the phone
/// (iCloud, Google, Outlook…) and tap Add. No calendar permission is needed for this.
struct AppleCalendarSheet: UIViewControllerRepresentable {
    let appointment: Appointment
    let babyName: String
    let onDone: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let controller = EKEventEditViewController()
        controller.eventStore = store
        controller.event = appointment.calendarEvent(in: store, babyName: babyName)
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let onDone: () -> Void
        init(onDone: @escaping () -> Void) { self.onDone = onDone }

        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            onDone()
        }
    }
}
