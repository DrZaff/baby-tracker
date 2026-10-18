import Foundation

/// Totals for a set of entries, used by the daily report and the charts.
struct DaySummary {
    var feedCount = 0
    var breastLeftSeconds = 0
    var breastRightSeconds = 0
    var formulaML = 0.0
    var breastMilkML = 0.0
    var pumpCount = 0
    var pumpSeconds = 0
    var pumpedML = 0.0
    var diaperCount = 0
    var wetCount = 0
    var dirtyCount = 0
    var dropOff: Date?
    var pickUp: Date?
    var latestWeightGrams: Double?
    var milestones: [String] = []

    var breastSeconds: Int { breastLeftSeconds + breastRightSeconds }
    var bottleML: Double { formulaML + breastMilkML }

    init(entries: [LogEntry]) {
        for entry in entries.sorted(by: { $0.timestamp < $1.timestamp }) {
            switch entry.kind {
            case .feed:
                if entry.isFeeding { feedCount += 1 }
                breastLeftSeconds += entry.breastLeftSeconds ?? 0
                breastRightSeconds += entry.breastRightSeconds ?? 0
                if let ml = entry.bottleML {
                    if entry.bottleContent == .breastMilk { breastMilkML += ml } else { formulaML += ml }
                }
                if entry.hasPump {
                    pumpCount += 1
                    pumpSeconds += entry.pumpSeconds
                    pumpedML += entry.pumpedML ?? 0
                }
            case .diaper:
                diaperCount += 1
                if entry.wet == true { wetCount += 1 }
                if entry.dirty == true { dirtyCount += 1 }
            case .weight:
                latestWeightGrams = entry.weightGrams ?? latestWeightGrams
            case .milestone:
                milestones.append(entry.displayTitle)
            case .daycare:
                if entry.daycareEvent == .dropOff { dropOff = entry.timestamp }
                if entry.daycareEvent == .pickUp { pickUp = entry.timestamp }
            }
        }
    }
}
