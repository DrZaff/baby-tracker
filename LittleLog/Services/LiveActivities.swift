import ActivityKit
import Foundation
import WidgetKit

/// Lock screen and Dynamic Island timers for feeds and sleep.
@MainActor
final class LiveActivities {
    static let shared = LiveActivities()

    private func activities(_ kind: String) -> [Activity<TimerActivityAttributes>] {
        Activity<TimerActivityAttributes>.activities.filter { $0.attributes.kind == kind }
    }

    private var babyName: String {
        UserDefaults.standard.string(forKey: "selectedBabyName") ?? "Baby"
    }

    private func show(kind: String, state: TimerActivityAttributes.ContentState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let content = ActivityContent(state: state, staleDate: nil)
        if let current = activities(kind).first {
            Task { await current.update(content) }
        } else {
            _ = try? Activity.request(
                attributes: TimerActivityAttributes(kind: kind, babyName: babyName),
                content: content
            )
        }
    }

    private func end(kind: String) {
        for activity in activities(kind) {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    /// A feed or pump timer is running, counting up from `startedAt`.
    func showFeedTimer(title: String, animal: String, color: UInt32, startedAt: Date) {
        show(kind: "feed", state: .init(title: title, animal: animal, startedAt: startedAt, color: color))
    }

    func endFeedTimer() { end(kind: "feed") }

    func showSleep(since: Date) {
        show(kind: "sleep", state: .init(title: "Sleeping", animal: Theme.sleepAnimal, startedAt: since, color: AppTheme.current.palette.dusk.light))
    }

    func endSleep() { end(kind: "sleep") }
}

extension WidgetSnapshot {
    /// Updates the home screen widget from the latest entries (newest first).
    static func publish(babyName: String, entries: [LogEntry]) {
        let lastFeed = entries.first { $0.isFeeding }
        let lastDiaper = entries.first { $0.kind == .diaper }
        let lastSide = entries.first { $0.kind == .feed && $0.breastLastSide != nil }?.breastLastSide
        let snapshot = WidgetSnapshot(
            babyName: babyName,
            lastFeed: lastFeed?.timestamp,
            lastFeedDetail: lastFeed?.displayTitle,
            nextSide: lastSide.map { $0 == .left ? "Right" : "Left" },
            lastDiaper: lastDiaper?.timestamp,
            lastDiaperDetail: lastDiaper?.displayTitle,
            sleepingSince: entries.first { $0.isSleeping }?.timestamp,
            updated: Date()
        )
        snapshot.save()
        UserDefaults.standard.set(babyName, forKey: "selectedBabyName")
        WidgetCenter.shared.reloadAllTimelines()
    }
}
