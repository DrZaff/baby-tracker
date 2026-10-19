import Foundation

enum Units {
    static let mlPerOunce = 29.5735
    static let gramsPerPound = 453.592
    static let gramsPerOunce = 28.3495

    static func volume(_ ml: Double, metric: Bool) -> String {
        if metric { return "\(Int(ml.rounded())) ml" }
        return "\(trimmed(ml / mlPerOunce)) oz"
    }

    /// Value shown in an amount field for the chosen unit.
    static func volumeValue(_ ml: Double, metric: Bool) -> Double {
        metric ? ml.rounded() : (ml / mlPerOunce * 10).rounded() / 10
    }

    static func millilitres(from value: Double, metric: Bool) -> Double {
        metric ? value : value * mlPerOunce
    }

    static func volumeUnit(metric: Bool) -> String { metric ? "ml" : "oz" }

    static func weight(_ grams: Double, metric: Bool) -> String {
        if metric { return String(format: "%.2f kg", grams / 1000) }
        let (lb, oz) = poundsAndOunces(grams)
        return "\(lb) lb \(trimmed(oz)) oz"
    }

    static func poundsAndOunces(_ grams: Double) -> (Int, Double) {
        let totalOz = (grams / gramsPerOunce * 10).rounded() / 10
        let lb = Int(totalOz / 16)
        return (lb, ((totalOz - Double(lb) * 16) * 10).rounded() / 10)
    }

    static let cmPerInch = 2.54

    static func length(_ cm: Double, metric: Bool) -> String {
        metric ? "\(trimmed(cm)) cm" : "\(trimmed(cm / cmPerInch)) in"
    }

    /// Value shown in a length field for the chosen unit.
    static func lengthValue(_ cm: Double, metric: Bool) -> Double {
        ((metric ? cm : cm / cmPerInch) * 10).rounded() / 10
    }

    static func centimetres(from value: Double, metric: Bool) -> Double {
        metric ? value : value * cmPerInch
    }

    static func duration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let minutes = Int((Double(seconds) / 60).rounded())
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    /// "2 hours 10 minutes", for Siri to read out.
    static func spoken(_ seconds: Int) -> String {
        let minutes = max(0, seconds / 60)
        let hours = minutes / 60, rest = minutes % 60
        func plural(_ n: Int, _ unit: String) -> String { "\(n) \(unit)\(n == 1 ? "" : "s")" }
        if hours == 0 { return minutes == 0 ? "less than a minute" : plural(minutes, "minute") }
        return rest == 0 ? plural(hours, "hour") : "\(plural(hours, "hour")) \(plural(rest, "minute"))"
    }

    static func clock(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    static func ago(_ date: Date, now: Date = Date()) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h \(minutes % 60)m ago" }
        return "\(hours / 24)d ago"
    }

    private static func trimmed(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
    }
}
