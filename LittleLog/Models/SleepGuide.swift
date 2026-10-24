import Foundation

/// Choices for how a baby fell asleep and where, shown on the sleep form.
enum SleepHow: String, CaseIterable, Identifiable {
    case onOwn = "On own"
    case nursing = "Nursing"
    case bottle = "Bottle"
    case held = "Rocked or held"
    case pacifier = "Pacifier"
    case motion = "Stroller or car"
    var id: String { rawValue }
}

enum SleepPlace: String, CaseIterable, Identifiable {
    case crib = "Crib"
    case bassinet = "Bassinet"
    case arms = "In arms"
    case carrier = "Carrier"
    case stroller = "Stroller"
    case car = "Car seat"
    var id: String { rawValue }
}

/// Typical awake time between sleeps by age, used to suggest when the next nap might go well.
/// These are common pediatric sleep ranges, not rules; every baby is different.
enum SleepGuide {
    static func wakeWindow(birthDate: Date, on date: Date = Date()) -> ClosedRange<TimeInterval> {
        let weeks = max(0, date.timeIntervalSince(birthDate) / (7 * 86_400))
        let minutes: ClosedRange<Double>
        switch weeks {
        case ..<4: minutes = 35...60
        case ..<12: minutes = 60...90
        case ..<20: minutes = 75...120
        case ..<28: minutes = 120...150
        case ..<36: minutes = 150...180
        case ..<52: minutes = 180...240
        case ..<78: minutes = 240...300
        default: minutes = 300...360
        }
        return (minutes.lowerBound * 60)...(minutes.upperBound * 60)
    }

    /// When the baby last woke, from the most recent finished sleep (entries newest first).
    static func lastWake(in entries: [LogEntry]) -> Date? {
        entries.first { $0.kind == .sleep && $0.sleepEnd != nil }?.sleepEnd
    }
}
