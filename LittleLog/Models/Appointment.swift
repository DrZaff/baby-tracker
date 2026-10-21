import Foundation
import FirebaseFirestore

enum AppointmentKind: String, Codable, CaseIterable, Identifiable {
    case wellChild, lactation, vaccines, sick, specialist, dentist, other
    var id: String { rawValue }

    var label: String {
        switch self {
        case .wellChild: return "Well-child check"
        case .lactation: return "Lactation specialist"
        case .vaccines: return "Vaccines"
        case .sick: return "Sick visit"
        case .specialist: return "Specialist"
        case .dentist: return "Dentist"
        case .other: return "Other"
        }
    }

    var emoji: String {
        switch self {
        case .wellChild: return "🩺"
        case .lactation: return "🤱"
        case .vaccines: return "💉"
        case .sick: return "🤒"
        case .specialist: return "👩‍⚕️"
        case .dentist: return "🦷"
        case .other: return "📅"
        }
    }
}

/// A scheduled visit, shared with every caregiver. Stored at babies/{babyId}/appointments/{id}.
struct Appointment: Identifiable, Codable, Equatable {
    @DocumentID var id: String? = nil
    var kind: AppointmentKind
    /// Optional custom name; the kind's label is used when empty.
    var title: String?
    var start: Date
    var durationMinutes: Int
    var location: String?
    var notes: String?
    /// Caregivers sent a Google Calendar invite for this appointment.
    var invitedEmails: [String]?
    /// Read after a name in notifications, e.g. "Sam added an appointment: Vaccines on Tue, Oct 28 at 9:30 AM".
    var summary: String?
    var createdByUid: String
    var createdByName: String
    var updatedByUid: String?
    var updatedByName: String?

    var displayTitle: String { title?.trimmedOrNil ?? kind.label }
    var end: Date { start.addingTimeInterval(TimeInterval(durationMinutes * 60)) }

    var timeText: String {
        "\(start.formatted(date: .omitted, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))"
    }

    /// Opens Google Calendar with this appointment filled in, ready to save.
    /// Guests get an invite at their Gmail once it's saved.
    func googleCalendarURL(babyName: String, guests: [String] = []) -> URL? {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = TimeZone(identifier: "UTC")
        format.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        var components = URLComponents(string: "https://calendar.google.com/calendar/render")
        var details = "\(babyName): \(kind.label)"
        if let notes = notes?.trimmedOrNil { details += "\n\n\(notes)" }
        details += "\n\nAdded from Little Log"
        components?.queryItems = [
            URLQueryItem(name: "action", value: "TEMPLATE"),
            URLQueryItem(name: "text", value: "\(babyName): \(displayTitle)"),
            URLQueryItem(name: "dates", value: "\(format.string(from: start))/\(format.string(from: end))"),
            URLQueryItem(name: "details", value: details),
            URLQueryItem(name: "location", value: location?.trimmedOrNil ?? ""),
        ]
        if !guests.isEmpty {
            components?.queryItems?.append(URLQueryItem(name: "add", value: guests.joined(separator: ",")))
        }
        return components?.url
    }
}

enum AppointmentRepository {
    static func collection(_ babyID: String) -> CollectionReference {
        Firestore.firestore().collection("babies").document(babyID).collection("appointments")
    }

    static func save(_ appointment: Appointment, babyID: String, auth: AuthService) throws {
        var appointment = appointment
        let when = appointment.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        appointment.summary = "an appointment: \(appointment.displayTitle) on \(when) at \(appointment.start.formatted(date: .omitted, time: .shortened))"
        if let id = appointment.id {
            appointment.updatedByUid = auth.uid
            appointment.updatedByName = auth.displayName
            try collection(babyID).document(id).setData(from: appointment)
        } else {
            _ = try collection(babyID).addDocument(from: appointment)
        }
    }

    static func delete(_ appointment: Appointment, babyID: String) {
        guard let id = appointment.id else { return }
        collection(babyID).document(id).delete()
    }
}

/// Live list of a baby's appointments between two dates, soonest first.
@Observable
final class AppointmentsListener {
    private(set) var appointments: [Appointment] = []
    private(set) var hasLoaded = false

    @ObservationIgnored private var listener: ListenerRegistration?

    func listen(babyID: String, from start: Date, to end: Date) {
        stop()
        listener = AppointmentRepository.collection(babyID)
            .whereField("start", isGreaterThanOrEqualTo: start)
            .whereField("start", isLessThan: end)
            .order(by: "start")
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self else { return }
                self.appointments = snapshot?.documents.compactMap { try? $0.data(as: Appointment.self) } ?? []
                self.hasLoaded = true
            }
    }

    func stop() {
        listener?.remove()
        listener = nil
    }

    deinit { listener?.remove() }
}
