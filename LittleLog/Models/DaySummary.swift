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
    var latestLengthCm: Double?
    var latestHeadCm: Double?
    var vitaminD = false
    var tummyCount = 0
    var tummySeconds = 0
    var sleepCount = 0
    var sleepSeconds = 0
    var milestones: [String] = []

    var breastSeconds: Int { breastLeftSeconds + breastRightSeconds }
    var bottleML: Double { formulaML + breastMilkML }

    init(entries: [LogEntry], now: Date = Date()) {
        for entry in entries.sorted(by: { $0.timestamp < $1.timestamp }) {
            switch entry.kind {
            case .feed:
                if entry.isFeeding { feedCount += 1 }
                breastLeftSeconds += entry.breastLeftSeconds ?? 0
                breastRightSeconds += entry.breastRightSeconds ?? 0
                if let ml = entry.bottleML {
                    switch entry.bottleContent {
                    case .breastMilk: breastMilkML += ml
                    case .mix:
                        formulaML += entry.bottleFormulaML ?? 0
                        breastMilkML += entry.bottleBreastMilkML ?? 0
                    default: formulaML += ml
                    }
                }
                if entry.vitaminD == true { vitaminD = true }
                if entry.hasPump {
                    pumpCount += 1
                    pumpSeconds += entry.pumpSeconds
                    pumpedML += entry.pumpedML ?? 0
                }
            case .diaper:
                diaperCount += 1
                if entry.wet == true { wetCount += 1 }
                if entry.dirty == true { dirtyCount += 1 }
            case .tummy:
                tummyCount += 1
                tummySeconds += entry.tummySeconds ?? 0
            case .sleep:
                sleepCount += 1
                sleepSeconds += entry.sleepSeconds(now: now)
            case .weight:
                latestWeightGrams = entry.weightGrams ?? latestWeightGrams
                latestLengthCm = entry.lengthCm ?? latestLengthCm
                latestHeadCm = entry.headCm ?? latestHeadCm
            case .milestone:
                milestones.append(entry.displayTitle)
            case .daycare:
                if entry.daycareEvent == .dropOff { dropOff = entry.timestamp }
                if entry.daycareEvent == .pickUp { pickUp = entry.timestamp }
            }
        }
    }
}
