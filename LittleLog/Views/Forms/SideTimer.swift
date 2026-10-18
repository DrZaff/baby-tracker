import SwiftUI

/// A start/pause stopwatch for one breast. Based on dates so it keeps counting if the phone locks.
struct SideTimer: Equatable {
    var accumulated: TimeInterval = 0
    var runningSince: Date?
    var lastStarted: Date?

    var isRunning: Bool { runningSince != nil }

    func elapsed(at now: Date = Date()) -> TimeInterval {
        accumulated + (runningSince.map { now.timeIntervalSince($0) } ?? 0)
    }

    var seconds: Int { Int(elapsed().rounded()) }

    mutating func start() {
        guard runningSince == nil else { return }
        runningSince = Date()
        lastStarted = runningSince
    }

    mutating func pause() {
        guard let since = runningSince else { return }
        accumulated += Date().timeIntervalSince(since)
        runningSince = nil
    }

    mutating func adjust(by delta: TimeInterval) {
        pause()
        accumulated = max(0, accumulated + delta)
    }

    init(seconds: Int? = nil) {
        accumulated = TimeInterval(seconds ?? 0)
    }
}

struct SideTimerRow: View {
    let label: String
    let tint: Color
    @Binding var timer: SideTimer
    var onStart: () -> Void = {}

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.headline)
                .frame(width: 48, alignment: .leading)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(Units.clock(timer.elapsed(at: context.date)))
                    .font(.title2.monospacedDigit().weight(.medium))
                    .foregroundStyle(timer.isRunning ? tint : .primary)
            }
            Spacer()
            Button { timer.adjust(by: -60) } label: {
                Image(systemName: "minus.circle").font(.title3)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            Button { timer.adjust(by: 60) } label: {
                Image(systemName: "plus.circle").font(.title3)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            Button {
                if timer.isRunning {
                    timer.pause()
                } else {
                    onStart()
                    timer.start()
                }
            } label: {
                Image(systemName: timer.isRunning ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(tint)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}
