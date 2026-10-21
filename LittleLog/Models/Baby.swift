import Foundation
import FirebaseFirestore

enum BabySex: String, Codable, CaseIterable, Identifiable {
    case girl, boy
    var id: String { rawValue }
    var label: String { self == .girl ? "Girl" : "Boy" }
}

struct Baby: Identifiable, Codable, Equatable {
    @DocumentID var id: String? = nil
    var name: String
    var birthDate: Date
    var sex: BabySex?
    var ownerUid: String
    var ownerEmail: String
    /// Lowercased Google account emails of everyone who can see and edit this baby's log.
    var memberEmails: [String]
    var createdAt: Date
    /// Remind every caregiver when this many hours pass without a feed. Nil means off.
    var feedReminderHours: Double?
    /// Shows a daily vitamin D checkbox when logging feeds, and adherence in Trends.
    var vitaminDReminder: Bool?
    /// When the vitamin D reminder was turned on, so adherence only counts from then.
    var vitaminDSince: Date?

    var babyID: String { id ?? "" }

    var ageDescription: String {
        let now = Date()
        guard birthDate <= now else { return "Due \(birthDate.formatted(date: .abbreviated, time: .omitted))" }
        let parts = Calendar.current.dateComponents([.year, .month, .weekOfMonth, .day], from: birthDate, to: now)
        let years = parts.year ?? 0, months = parts.month ?? 0
        let weeks = parts.weekOfMonth ?? 0, days = parts.day ?? 0
        func plural(_ n: Int, _ unit: String) -> String { "\(n) \(unit)\(n == 1 ? "" : "s")" }
        if years > 0 {
            return months > 0 ? "\(plural(years, "year")), \(plural(months, "month")) old" : "\(plural(years, "year")) old"
        }
        if months > 0 {
            return weeks > 0 ? "\(plural(months, "month")), \(plural(weeks, "week")) old" : "\(plural(months, "month")) old"
        }
        if weeks > 0 {
            return days > 0 ? "\(plural(weeks, "week")), \(plural(days, "day")) old" : "\(plural(weeks, "week")) old"
        }
        return days == 0 ? "Born today" : "\(plural(days, "day")) old"
    }
}
