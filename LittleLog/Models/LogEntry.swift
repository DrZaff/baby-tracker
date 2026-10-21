import Foundation
import FirebaseFirestore

enum EntryKind: String, Codable, CaseIterable {
    case feed, sleep, tummy, diaper, weight, milestone, daycare
}

enum BottleContent: String, Codable, CaseIterable, Identifiable {
    case formula, breastMilk, mix
    var id: String { rawValue }
    var label: String {
        switch self {
        case .formula: return "Formula"
        case .breastMilk: return "Breast milk"
        case .mix: return "Mix"
        }
    }
}

enum DaycareEvent: String, Codable, CaseIterable, Identifiable {
    case dropOff, pickUp
    var id: String { rawValue }
    var label: String { self == .dropOff ? "Drop-off" : "Pick-up" }
}

enum BreastSide: String, Codable {
    case left, right
    var label: String { self == .left ? "Left" : "Right" }
}

/// One thing that happened: a feed (breast, bottle and/or pump), a sleep, a diaper, a growth check, a milestone
/// or a daycare drop-off/pick-up. Stored at babies/{babyId}/entries/{entryId}.
/// Volumes are millilitres, weights grams and lengths centimetres; the UI converts.
struct LogEntry: Identifiable, Codable, Equatable {
    @DocumentID var id: String? = nil
    var kind: EntryKind
    var timestamp: Date
    var notes: String?
    /// Short human-readable text, also used by the notification function.
    var summary: String?
    var createdByUid: String
    var createdByName: String
    var updatedByUid: String?
    var updatedByName: String?
    var updatedAt: Date?
    /// Units the amounts were entered in (true = ml/kg, false = oz/lb). Nil uses the app setting.
    var metric: Bool?

    // Feed
    var breastLeftSeconds: Int?
    var breastRightSeconds: Int?
    var breastLastSide: BreastSide?
    var bottleML: Double?
    var bottleContent: BottleContent?
    /// For a mixed bottle, how much of bottleML was formula and how much breast milk.
    var bottleFormulaML: Double?
    var bottleBreastMilkML: Double?
    var pumpLeftSeconds: Int?
    var pumpRightSeconds: Int?
    var pumpedML: Double?
    /// Daily vitamin D drops, logged with a feed.
    var vitaminD: Bool?

    // Diaper
    var wet: Bool?
    var dirty: Bool?
    var stoolColor: String?
    var stoolConsistency: String?

    // Tummy time: timestamp is when it started.
    var tummySeconds: Int?

    // Sleep (no longer logged, kept for older entries): timestamp is when it started. No end means the baby is still asleep.
    var sleepEnd: Date?

    // Growth (kind .weight): any of weight, length and head circumference.
    var weightGrams: Double?
    var lengthCm: Double?
    var headCm: Double?
    /// Units length and head size were entered in, when different from `metric`.
    var lengthMetric: Bool?
    var headMetric: Bool?

    // Milestone
    var title: String?

    // Daycare
    var daycareEvent: DaycareEvent?
    var daycarePerson: String?

    init(kind: EntryKind, timestamp: Date = Date(), createdByUid: String, createdByName: String) {
        self.kind = kind
        self.timestamp = timestamp
        self.createdByUid = createdByUid
        self.createdByName = createdByName
    }
}

extension LogEntry {
    var breastSeconds: Int { (breastLeftSeconds ?? 0) + (breastRightSeconds ?? 0) }
    var pumpSeconds: Int { (pumpLeftSeconds ?? 0) + (pumpRightSeconds ?? 0) }
    var hasBreast: Bool { breastSeconds > 0 }
    var hasBottle: Bool { (bottleML ?? 0) > 0 }
    var hasPump: Bool { pumpSeconds > 0 || (pumpedML ?? 0) > 0 }
    /// A feed that fed the baby (pump-only sessions don't count).
    var isFeeding: Bool { kind == .feed && (hasBreast || hasBottle) }
    var isPumpOnly: Bool { kind == .feed && hasPump && !hasBreast && !hasBottle }
    var isSleeping: Bool { kind == .sleep && sleepEnd == nil }

    func sleepSeconds(now: Date = Date()) -> Int {
        guard kind == .sleep else { return 0 }
        return max(0, Int((sleepEnd ?? now).timeIntervalSince(timestamp)))
    }

    var measurementCount: Int { [weightGrams, lengthCm, headCm].compactMap { $0 }.count }

    var displayTitle: String {
        switch kind {
        case .feed:
            if isPumpOnly { return "Pump" }
            if !hasBreast && !hasBottle && !hasPump && vitaminD == true { return "Vitamin D" }
            var parts: [String] = []
            if hasBreast { parts.append("Breast") }
            if hasBottle { parts.append("Bottle") }
            if hasPump { parts.append("Pump") }
            return parts.isEmpty ? "Feed" : parts.joined(separator: " + ")
        case .diaper:
            switch (wet ?? false, dirty ?? false) {
            case (true, true): return "Pee + poop"
            case (false, true): return "Poop"
            default: return "Pee"
            }
        case .sleep: return isSleeping ? "Sleeping" : "Sleep"
        case .tummy: return "Tummy time"
        case .weight:
            if measurementCount > 1 { return "Growth check" }
            if lengthCm != nil { return "Length" }
            if headCm != nil { return "Head size" }
            return "Weight"
        case .milestone: return title?.isEmpty == false ? title! : "Milestone"
        case .daycare: return daycareEvent?.label ?? "Daycare"
        }
    }

    func detailText(metric: Bool) -> String {
        var parts: [String] = []
        switch kind {
        case .feed:
            if hasBreast {
                var sides: [String] = []
                if let l = breastLeftSeconds, l > 0 { sides.append("L \(Units.duration(l))") }
                if let r = breastRightSeconds, r > 0 { sides.append("R \(Units.duration(r))") }
                parts.append("Breast " + sides.joined(separator: " · "))
            }
            if let ml = bottleML, ml > 0 {
                if bottleContent == .mix {
                    let f = Units.volume(bottleFormulaML ?? 0, metric: metric)
                    let b = Units.volume(bottleBreastMilkML ?? 0, metric: metric)
                    parts.append("\(Units.volume(ml, metric: metric)) mix (\(f) formula, \(b) breast milk)")
                } else {
                    parts.append("\(Units.volume(ml, metric: metric)) \((bottleContent ?? .formula).label.lowercased())")
                }
            }
            if hasPump {
                var sides: [String] = []
                if let l = pumpLeftSeconds, l > 0 { sides.append("L \(Units.duration(l))") }
                if let r = pumpRightSeconds, r > 0 { sides.append("R \(Units.duration(r))") }
                var text = "Pumped " + sides.joined(separator: " · ")
                if let ml = pumpedML, ml > 0 { text += sides.isEmpty ? Units.volume(ml, metric: metric) : " (\(Units.volume(ml, metric: metric)))" }
                parts.append(text)
            }
            if vitaminD == true { parts.append("☀️ vitamin D") }
        case .diaper:
            if dirty == true {
                let stool = [stoolColor, stoolConsistency].compactMap { $0?.lowercased() }
                if !stool.isEmpty { parts.append(stool.joined(separator: ", ")) }
            }
        case .sleep:
            if let end = sleepEnd {
                parts.append("\(Units.duration(sleepSeconds())) · until \(end.formatted(date: .omitted, time: .shortened))")
            } else {
                parts.append("since \(timestamp.formatted(date: .omitted, time: .shortened))")
            }
        case .tummy:
            if let seconds = tummySeconds, seconds > 0 { parts.append(Units.duration(seconds)) }
        case .weight:
            if let g = weightGrams { parts.append(Units.weight(g, metric: metric)) }
            if let cm = lengthCm { parts.append("\(Units.length(cm, metric: lengthMetric ?? metric)) long") }
            if let cm = headCm { parts.append("head \(Units.length(cm, metric: headMetric ?? metric))") }
        case .milestone:
            break
        case .daycare:
            if let person = daycarePerson, !person.isEmpty { parts.append("by \(person)") }
        }
        return parts.joined(separator: " · ")
    }

    /// Reads after a name in notifications, e.g. "Sam logged a feed (Breast L 12m · R 8m)".
    func makeSummary(metric: Bool) -> String {
        let noun: String
        switch kind {
        case .feed: noun = isPumpOnly ? "a pump session" : "a feed"
        case .diaper: noun = "a diaper, \(displayTitle.lowercased())"
        case .sleep: noun = isSleeping ? "the start of a sleep" : "a sleep"
        case .tummy: noun = "tummy time"
        case .weight: noun = measurementCount > 1 ? "a growth check" : "a \(displayTitle.lowercased())"
        case .milestone: noun = "a milestone: \(displayTitle)"
        case .daycare: noun = daycareEvent == .pickUp ? "a daycare pick-up" : "a daycare drop-off"
        }
        let detail = detailText(metric: metric)
        return detail.isEmpty ? noun : "\(noun) (\(detail))"
    }

    var authorName: String { updatedByName ?? createdByName }
}
