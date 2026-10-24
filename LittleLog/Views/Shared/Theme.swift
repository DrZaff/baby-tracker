import SwiftUI

/// The jungle look: leafy greens, warm sand, sunshine and tropical flower colors,
/// with a friendly animal for each kind of entry.
enum Theme {
    // Jungle palette. Each color has a lighter variant for dark mode ("night jungle").
    static let canopy = dynamic(light: 0x2E6B4A, dark: 0x7FD49B)    // deep leaf green, the app's tint
    static let leaf = dynamic(light: 0x5DB563, dark: 0x6CC774)
    static let lime = dynamic(light: 0xB8E07E, dark: 0x5E8A3E)
    static let sunshine = dynamic(light: 0xF7B731, dark: 0xF9C74F)
    static let mango = dynamic(light: 0xF28C38, dark: 0xF6A05A)
    static let hibiscus = dynamic(light: 0xE8566C, dark: 0xF0798B)
    static let orchid = dynamic(light: 0x9B6BD3, dark: 0xB592E6)
    static let lagoon = dynamic(light: 0x23A6A6, dark: 0x4CC9C4)
    static let river = dynamic(light: 0x3F7FD0, dark: 0x6FA2E8)
    static let dusk = dynamic(light: 0x5B5FC7, dark: 0x9A9DF0)
    static let bark = dynamic(light: 0x6B4A2E, dark: 0xD9B98F)

    /// Page background: warm sand by day, deep jungle by night.
    static let sandTop = dynamic(light: 0xFFF7E6, dark: 0x0F1F17)
    static let sandBottom = dynamic(light: 0xEAF6DF, dark: 0x132A1E)
    /// The light line down the middle of background leaves; faint at night.
    static let leafVein = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 1, alpha: 0.08)
        : UIColor(white: 1, alpha: 0.35) })
    /// Card surface on top of the background.
    static let card = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.12, green: 0.22, blue: 0.16, alpha: 0.92)
        : UIColor(white: 1, alpha: 0.88) })

    // What each kind of entry uses.
    static let feed = hibiscus
    static let bottle = mango
    static let pump = orchid
    static let sleep = dusk
    static let tummy = leaf
    static let diaper = lagoon
    static let weight = river
    static let milestone = sunshine
    static let daycare = leaf
    static let vaccine = orchid

    // Animal friends.
    static let feedAnimal = "🐘"
    static let bottleAnimal = "🦒"
    static let pumpAnimal = "🦩"
    static let sleepAnimal = "🐨"
    static let tummyAnimal = "🐢"
    static let diaperAnimal = "🐒"
    static let weightAnimal = "🦛"
    static let milestoneAnimal = "🦁"
    static let daycareAnimal = "🦜"
    static let pickUpAnimal = "🐯"
    static let vaccineAnimal = "🦔"

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension LogEntry {
    var animal: String {
        switch kind {
        case .feed: return isPumpOnly ? Theme.pumpAnimal : (hasBreast ? Theme.feedAnimal : Theme.bottleAnimal)
        case .sleep: return Theme.sleepAnimal
        case .tummy: return Theme.tummyAnimal
        case .diaper: return Theme.diaperAnimal
        case .weight: return Theme.weightAnimal
        case .milestone: return Theme.milestoneAnimal
        case .daycare: return daycareEvent == .pickUp ? Theme.pickUpAnimal : Theme.daycareAnimal
        }
    }

    var tint: Color {
        switch kind {
        case .feed: return isPumpOnly ? Theme.pump : (hasBreast ? Theme.feed : Theme.bottle)
        case .sleep: return Theme.sleep
        case .tummy: return Theme.tummy
        case .diaper: return Theme.diaper
        case .weight: return Theme.weight
        case .milestone: return Theme.milestone
        case .daycare: return Theme.daycare
        }
    }
}

/// An animal sitting in a soft colored bubble.
struct MascotBadge: View {
    let animal: String
    let tint: Color
    var size: CGFloat = 40

    var body: some View {
        Text(animal)
            .font(.system(size: size * 0.55))
            .frame(width: size, height: size)
            .background(
                Circle().fill(
                    LinearGradient(colors: [tint.opacity(0.32), tint.opacity(0.14)], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            )
            .overlay(Circle().strokeBorder(tint.opacity(0.35), lineWidth: 1.5))
            .accessibilityHidden(true)
    }
}

/// A rounded leaf, pointing up, for decorating backgrounds.
struct LeafShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        path.move(to: CGPoint(x: rect.minX + w * 0.5, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + w * 0.5, y: rect.minY), control: CGPoint(x: rect.minX - w * 0.35, y: rect.minY + h * 0.45))
        path.addQuadCurve(to: CGPoint(x: rect.minX + w * 0.5, y: rect.maxY), control: CGPoint(x: rect.minX + w * 1.35, y: rect.minY + h * 0.45))
        return path
    }
}

/// The center vein of a leaf.
struct LeafVein: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.12))
        return path
    }
}

struct Leaf: View {
    var color: Color
    var width: CGFloat
    var angle: Double

    var body: some View {
        ZStack {
            LeafShape().fill(LinearGradient(colors: [color, color.opacity(0.75)], startPoint: .top, endPoint: .bottom))
            LeafVein().stroke(Theme.leafVein, style: StrokeStyle(lineWidth: max(1, width * 0.03), lineCap: .round))
        }
        .frame(width: width, height: width * 1.6)
        .rotationEffect(.degrees(angle), anchor: .bottom)
    }
}

/// Sand-to-mint backdrop with leaves curling in from the corners.
struct JungleBackground: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [Theme.sandTop, Theme.sandBottom], startPoint: .top, endPoint: .bottom)

                // Top-left cluster
                Leaf(color: Theme.leaf.opacity(0.28), width: w * 0.30, angle: 125)
                    .position(x: w * 0.02, y: 10)
                Leaf(color: Theme.canopy.opacity(0.18), width: w * 0.24, angle: 160)
                    .position(x: w * 0.16, y: -10)
                // Top-right cluster
                Leaf(color: Theme.lime.opacity(0.35), width: w * 0.28, angle: -130)
                    .position(x: w * 0.98, y: 20)
                Leaf(color: Theme.leaf.opacity(0.2), width: w * 0.2, angle: -165)
                    .position(x: w * 0.84, y: -6)
                // Bottom corners
                Leaf(color: Theme.leaf.opacity(0.22), width: w * 0.34, angle: 35)
                    .position(x: w * 0.0, y: geo.size.height * 0.9)
                Leaf(color: Theme.lime.opacity(0.3), width: w * 0.3, angle: -40)
                    .position(x: w * 1.0, y: geo.size.height * 0.94)
                Leaf(color: Theme.canopy.opacity(0.14), width: w * 0.22, angle: 10)
                    .position(x: w * 0.88, y: geo.size.height * 0.86)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Card surface used for sections and charts.
struct JungleCard: ViewModifier {
    var padding: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.leaf.opacity(0.18), lineWidth: 1))
            .shadow(color: Theme.canopy.opacity(0.08), radius: 10, y: 4)
    }
}

/// Section title with a little animal or plant in front.
struct JungleHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 6) {
            Text(icon)
            Text(title)
        }
        .font(.headline)
        .foregroundStyle(Theme.canopy)
        .textCase(nil)
    }
}

/// Buttons that squish a little when pressed.
struct BouncyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

extension View {
    func jungleCard(padding: CGFloat = 14) -> some View { modifier(JungleCard(padding: padding)) }

    /// Jungle backdrop for lists and forms.
    func jungleBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(JungleBackground())
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
