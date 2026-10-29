import SwiftUI

/// Colors and animals for the current look (jungle by default; see AppTheme).
/// Everything reads the chosen theme, and RootView redraws the app when it changes.
enum Theme {
    private static var palette: ThemePalette { AppTheme.current.palette }
    private static var art: ThemeArt { AppTheme.current.art }

    // Palette. Each color has a lighter variant for dark mode.
    static var canopy: Color { dynamic(palette.canopy) }    // the app's tint
    static var leaf: Color { dynamic(palette.leaf) }
    static var lime: Color { dynamic(palette.lime) }
    static var sunshine: Color { dynamic(palette.sunshine) }
    static var mango: Color { dynamic(palette.mango) }
    static var hibiscus: Color { dynamic(palette.hibiscus) }
    static var orchid: Color { dynamic(palette.orchid) }
    static var lagoon: Color { dynamic(palette.lagoon) }
    static var river: Color { dynamic(palette.river) }
    static var dusk: Color { dynamic(palette.dusk) }
    static var bark: Color { dynamic(palette.bark) }

    /// Page background gradient.
    static var sandTop: Color { dynamic(palette.backgroundTop) }
    static var sandBottom: Color { dynamic(palette.backgroundBottom) }
    /// The light line down the middle of background leaves; faint at night.
    static let leafVein = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 1, alpha: 0.08)
        : UIColor(white: 1, alpha: 0.35) })
    /// Card surface on top of the background.
    static var card: Color {
        let night = palette.nightCard
        return Color(UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(hex: night).withAlphaComponent(0.92)
            : UIColor(white: 1, alpha: 0.88) })
    }

    // What each kind of entry uses.
    static var feed: Color { hibiscus }
    static var bottle: Color { mango }
    static var pump: Color { orchid }
    static var sleep: Color { dusk }
    static var tummy: Color { leaf }
    static var diaper: Color { lagoon }
    static var weight: Color { river }
    static var milestone: Color { sunshine }
    static var daycare: Color { leaf }
    static var vaccine: Color { orchid }

    // Animal friends (or rockets, dinosaurs, unicorns…).
    static var feedAnimal: String { art.feed }
    static var bottleAnimal: String { art.bottle }
    static var pumpAnimal: String { art.pump }
    static var sleepAnimal: String { art.sleep }
    static var tummyAnimal: String { art.tummy }
    static var diaperAnimal: String { art.diaper }
    static var weightAnimal: String { art.weight }
    static var lengthAnimal: String { art.length }
    static var headAnimal: String { art.head }
    static var milestoneAnimal: String { art.milestone }
    static var daycareAnimal: String { art.daycare }
    static var pickUpAnimal: String { art.pickUp }
    static var vaccineAnimal: String { art.vaccine }
    static var appointmentAnimal: String { art.appointment }

    /// Little decorations: section icons, mascots and so on.
    static var decor: ThemeArt { art }

    private static func dynamic(_ color: ThemeColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: color.dark) : UIColor(hex: color.light) })
    }
}

extension UIColor {
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

/// The page backdrop: the theme's gradient with its decorations around the edges
/// (leaves, bubbles and waves, stars and a planet, ferns and a volcano, or hearts and sparkles).
struct JungleBackground: View {
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [Theme.sandTop, Theme.sandBottom], startPoint: .top, endPoint: .bottom)
                ThemeDecorations(size: geo.size)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Just the decorations, sized to fit; also drawn on the doctor report's pages.
struct ThemeDecorations: View {
    let size: CGSize

    var body: some View {
        switch AppTheme.current {
        case .jungle: JungleLeaves(size: size)
        case .ocean: OceanDecor(size: size)
        case .space: SpaceDecor(size: size)
        case .dinosaur: DinoDecor(size: size)
        case .princess: PrincessDecor(size: size)
        }
    }
}

private struct JungleLeaves: View {
    let size: CGSize

    var body: some View {
        let w = size.width, h = size.height
        ZStack(alignment: .topLeading) {
            // Top-left cluster
            Leaf(color: Theme.leaf.opacity(0.28), width: w * 0.30, angle: 125).position(x: w * 0.02, y: 10)
            Leaf(color: Theme.canopy.opacity(0.18), width: w * 0.24, angle: 160).position(x: w * 0.16, y: -10)
            // Top-right cluster
            Leaf(color: Theme.lime.opacity(0.35), width: w * 0.28, angle: -130).position(x: w * 0.98, y: 20)
            Leaf(color: Theme.leaf.opacity(0.2), width: w * 0.2, angle: -165).position(x: w * 0.84, y: -6)
            // Bottom corners
            Leaf(color: Theme.leaf.opacity(0.22), width: w * 0.34, angle: 35).position(x: w * 0.0, y: h * 0.9)
            Leaf(color: Theme.lime.opacity(0.3), width: w * 0.3, angle: -40).position(x: w * 1.0, y: h * 0.94)
            Leaf(color: Theme.canopy.opacity(0.14), width: w * 0.22, angle: 10).position(x: w * 0.88, y: h * 0.86)
        }
    }
}

/// A gentle wave across the bottom.
struct WaveShape: Shape {
    var crests: Double = 2

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.35))
        let steps = 60
        for step in 0...steps {
            let x = rect.minX + rect.width * Double(step) / Double(steps)
            let y = rect.minY + rect.height * (0.35 + 0.25 * sin(Double(step) / Double(steps) * crests * 2 * .pi))
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct OceanDecor: View {
    let size: CGSize

    var body: some View {
        let w = size.width, h = size.height
        ZStack(alignment: .topLeading) {
            // Bubbles rising in the top corners.
            ForEach(Array([(0.06, 0.05, 0.11), (0.17, 0.11, 0.06), (0.08, 0.17, 0.04), (0.9, 0.06, 0.09), (0.8, 0.13, 0.05), (0.95, 0.19, 0.035)].enumerated()), id: \.offset) { _, b in
                Circle()
                    .fill(Theme.lime.opacity(0.25))
                    .overlay(Circle().strokeBorder(Theme.lagoon.opacity(0.35), lineWidth: 1.5))
                    .overlay(alignment: .topLeading) {
                        Circle().fill(.white.opacity(0.55)).frame(width: w * b.2 * 0.28).offset(x: w * b.2 * 0.18, y: w * b.2 * 0.16)
                    }
                    .frame(width: w * b.2, height: w * b.2)
                    .position(x: w * b.0, y: h * b.1)
            }
            // Waves along the bottom.
            WaveShape(crests: 1.5).fill(Theme.lagoon.opacity(0.14)).frame(width: w, height: h * 0.16).position(x: w / 2, y: h * 0.93)
            WaveShape(crests: 2).fill(Theme.river.opacity(0.12)).frame(width: w, height: h * 0.12).position(x: w / 2, y: h * 0.96)
        }
    }
}

private struct SpaceDecor: View {
    let size: CGSize

    private static let stars: [(Double, Double, Double)] = [
        (0.05, 0.04, 3), (0.22, 0.09, 2), (0.36, 0.03, 2.5), (0.62, 0.06, 2), (0.12, 0.2, 2), (0.93, 0.25, 2.5),
        (0.04, 0.42, 2), (0.97, 0.5, 2), (0.08, 0.66, 2.5), (0.9, 0.72, 2), (0.3, 0.92, 2), (0.55, 0.97, 2.5), (0.72, 0.9, 2),
    ]

    var body: some View {
        let w = size.width, h = size.height
        ZStack(alignment: .topLeading) {
            ForEach(Array(Self.stars.enumerated()), id: \.offset) { _, s in
                Circle().fill(Theme.sunshine.opacity(0.55)).frame(width: s.2 * 2, height: s.2 * 2).position(x: w * s.0, y: h * s.1)
            }
            Image(systemName: "sparkle").font(.system(size: w * 0.07)).foregroundStyle(Theme.sunshine.opacity(0.45)).position(x: w * 0.12, y: h * 0.1)
            Image(systemName: "sparkle").font(.system(size: w * 0.045)).foregroundStyle(Theme.orchid.opacity(0.4)).position(x: w * 0.84, y: h * 0.86)
            // A ringed planet peeking in at the top right.
            ZStack {
                Circle().fill(LinearGradient(colors: [Theme.orchid.opacity(0.35), Theme.river.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
                Ellipse().stroke(Theme.sunshine.opacity(0.35), lineWidth: w * 0.012).frame(width: w * 0.5, height: w * 0.12).rotationEffect(.degrees(-18))
            }
            .frame(width: w * 0.3, height: w * 0.3)
            .position(x: w * 0.93, y: h * 0.06)
            // A crescent moon at the bottom left.
            Image(systemName: "moon.fill").font(.system(size: w * 0.22)).foregroundStyle(Theme.lime.opacity(0.5)).rotationEffect(.degrees(-20)).position(x: w * 0.05, y: h * 0.93)
        }
    }
}

/// A rounded volcano for the dinosaur theme.
struct VolcanoShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.minY + rect.height * 0.12), control: CGPoint(x: rect.minX + rect.width * 0.3, y: rect.maxY * 0.6))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.62, y: rect.minY + rect.height * 0.12))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: rect.minX + rect.width * 0.7, y: rect.maxY * 0.6))
        path.closeSubpath()
        return path
    }
}

private struct DinoDecor: View {
    let size: CGSize

    var body: some View {
        let w = size.width, h = size.height
        ZStack(alignment: .topLeading) {
            // Palm and fern fronds in the top corners.
            Leaf(color: Theme.leaf.opacity(0.26), width: w * 0.2, angle: 120).position(x: w * 0.02, y: 6)
            Leaf(color: Theme.canopy.opacity(0.16), width: w * 0.16, angle: 150).position(x: w * 0.12, y: -8)
            Leaf(color: Theme.lime.opacity(0.4), width: w * 0.2, angle: -125).position(x: w * 0.98, y: 14)
            Leaf(color: Theme.leaf.opacity(0.18), width: w * 0.15, angle: -160).position(x: w * 0.88, y: -6)
            // A friendly volcano with a little puff of smoke, bottom right.
            VolcanoShape().fill(Theme.bark.opacity(0.16)).frame(width: w * 0.55, height: h * 0.16).position(x: w * 0.86, y: h * 0.93)
            Capsule().fill(Theme.hibiscus.opacity(0.22)).frame(width: w * 0.1, height: w * 0.03).position(x: w * 0.86, y: h * 0.86)
            Circle().fill(Theme.bark.opacity(0.08)).frame(width: w * 0.08).position(x: w * 0.83, y: h * 0.82)
            Circle().fill(Theme.bark.opacity(0.06)).frame(width: w * 0.1).position(x: w * 0.88, y: h * 0.79)
            // A fern at the bottom left.
            Leaf(color: Theme.leaf.opacity(0.24), width: w * 0.26, angle: 30).position(x: w * 0.0, y: h * 0.92)
            Leaf(color: Theme.lime.opacity(0.35), width: w * 0.18, angle: 60).position(x: w * 0.04, y: h * 0.96)
        }
    }
}

private struct PrincessDecor: View {
    let size: CGSize

    var body: some View {
        let w = size.width, h = size.height
        ZStack(alignment: .topLeading) {
            symbol("heart.fill", Theme.hibiscus.opacity(0.18), w * 0.2, x: w * 0.06, y: h * 0.05, angle: -18)
            symbol("heart.fill", Theme.orchid.opacity(0.16), w * 0.09, x: w * 0.2, y: h * 0.12, angle: 12)
            symbol("sparkle", Theme.sunshine.opacity(0.5), w * 0.06, x: w * 0.3, y: h * 0.05, angle: 0)
            symbol("crown.fill", Theme.sunshine.opacity(0.28), w * 0.18, x: w * 0.9, y: h * 0.06, angle: 14)
            symbol("sparkle", Theme.orchid.opacity(0.35), w * 0.05, x: w * 0.78, y: h * 0.13, angle: 0)
            symbol("heart.fill", Theme.hibiscus.opacity(0.14), w * 0.24, x: w * 0.04, y: h * 0.93, angle: 16)
            symbol("sparkle", Theme.sunshine.opacity(0.45), w * 0.07, x: w * 0.22, y: h * 0.88, angle: 0)
            symbol("heart.fill", Theme.orchid.opacity(0.16), w * 0.16, x: w * 0.94, y: h * 0.92, angle: -14)
        }
    }

    private func symbol(_ name: String, _ color: Color, _ size: CGFloat, x: CGFloat, y: CGFloat, angle: Double) -> some View {
        Image(systemName: name)
            .font(.system(size: size))
            .foregroundStyle(color)
            .rotationEffect(.degrees(angle))
            .position(x: x, y: y)
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
