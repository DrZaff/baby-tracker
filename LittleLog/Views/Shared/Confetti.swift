import SwiftUI

extension Notification.Name {
    /// Posted after a new milestone is saved, to throw some confetti.
    static let milestoneLogged = Notification.Name("milestoneLogged")
}

/// A burst of confetti, leaves and flowers falling across the screen for a few seconds.
struct ConfettiView: View {
    private struct Piece {
        let x: Double
        let delay: Double
        let speed: Double
        let drift: Double
        let spin: Double
        let size: Double
        let symbol: String?
        let color: Color
    }

    private static let colors: [Color] = [Theme.hibiscus, Theme.sunshine, Theme.leaf, Theme.lagoon, Theme.mango, Theme.orchid]
    private static let symbols = ["🎉", "🌺", "🍃", "⭐️", "🦁", "🌼"]

    private let pieces: [Piece] = (0..<90).map { i in
        Piece(
            x: .random(in: 0...1),
            delay: .random(in: 0...0.8),
            speed: .random(in: 0.35...0.6),
            drift: .random(in: -40...40),
            spin: .random(in: -540...540),
            size: .random(in: 7...13),
            symbol: i % 6 == 0 ? ConfettiView.symbols.randomElement() : nil,
            color: ConfettiView.colors[i % ConfettiView.colors.count]
        )
    }
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { context in
            Canvas { canvas, size in
                let t = context.date.timeIntervalSince(start)
                for piece in pieces {
                    let progress = (t - piece.delay) * piece.speed
                    guard progress > 0, progress < 1.3 else { continue }
                    let x = piece.x * size.width + sin(progress * 6 + piece.x * 10) * piece.drift
                    let y = -20 + progress * (size.height + 40)
                    var layer = canvas
                    layer.translateBy(x: x, y: y)
                    layer.rotate(by: .degrees(piece.spin * progress))
                    layer.opacity = progress > 1 ? max(0, 1.3 - progress) / 0.3 : 1
                    if let symbol = piece.symbol {
                        layer.draw(Text(symbol).font(.system(size: piece.size * 2.2)), at: .zero)
                    } else {
                        let rect = CGRect(x: -piece.size / 2, y: -piece.size / 4, width: piece.size, height: piece.size / 2)
                        layer.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(piece.color))
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Shows confetti whenever a milestone is logged.
struct MilestoneCelebration: ViewModifier {
    @State private var showing: UUID?
    @State private var celebrations = 0

    func body(content: Content) -> some View {
        content
            .overlay {
                if let id = showing {
                    ConfettiView().id(id)
                }
            }
            .sensoryFeedback(.success, trigger: celebrations)
            .onReceive(NotificationCenter.default.publisher(for: .milestoneLogged)) { _ in
                let id = UUID()
                showing = id
                celebrations += 1
                Task {
                    try? await Task.sleep(for: .seconds(4))
                    if showing == id { showing = nil }
                }
            }
    }
}

extension View {
    func celebratesMilestones() -> some View { modifier(MilestoneCelebration()) }
}
