import SwiftUI

enum Theme {
    static let feed = Color(red: 0.95, green: 0.55, blue: 0.45)
    static let bottle = Color(red: 0.98, green: 0.70, blue: 0.35)
    static let pump = Color(red: 0.62, green: 0.50, blue: 0.85)
    static let diaper = Color(red: 0.30, green: 0.70, blue: 0.70)
    static let weight = Color(red: 0.40, green: 0.52, blue: 0.90)
    static let milestone = Color(red: 0.95, green: 0.75, blue: 0.20)
    static let daycare = Color(red: 0.40, green: 0.72, blue: 0.45)
}

extension LogEntry {
    var symbol: String {
        switch kind {
        case .feed: return isPumpOnly ? "drop.circle" : (hasBreast ? "heart.fill" : "drop.fill")
        case .diaper: return "humidity.fill"
        case .weight: return "scalemass.fill"
        case .milestone: return "star.fill"
        case .daycare: return daycareEvent == .pickUp ? "house.fill" : "building.2.fill"
        }
    }

    var tint: Color {
        switch kind {
        case .feed: return isPumpOnly ? Theme.pump : (hasBreast ? Theme.feed : Theme.bottle)
        case .diaper: return Theme.diaper
        case .weight: return Theme.weight
        case .milestone: return Theme.milestone
        case .daycare: return Theme.daycare
        }
    }
}

struct IconBadge: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.15), in: Circle())
    }
}

struct BabySwitcher: View {
    @Environment(BabyStore.self) private var store

    var body: some View {
        if store.babies.count > 1 {
            Menu {
                ForEach(store.babies) { baby in
                    Button {
                        store.select(baby)
                    } label: {
                        if baby.id == store.selectedBaby?.id {
                            Label(baby.name, systemImage: "checkmark")
                        } else {
                            Text(baby.name)
                        }
                    }
                }
            } label: {
                Image(systemName: "person.crop.circle.badge.checkmark")
            }
        }
    }
}

extension String {
    var trimmedOrNil: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
