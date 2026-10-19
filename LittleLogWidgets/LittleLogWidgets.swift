import ActivityKit
import SwiftUI
import WidgetKit

@main
struct LittleLogWidgets: WidgetBundle {
    var body: some Widget {
        StatusWidget()
        TimerLiveActivity()
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    static let canopy = Color(hex: 0x2E6B4A)
    static let sandTop = Color(hex: 0xFFF7E6)
    static let mint = Color(hex: 0xE3F4D6)
    static let hibiscus = Color(hex: 0xE8566C)
    static let lagoon = Color(hex: 0x23A6A6)
    static let dusk = Color(hex: 0x5B5FC7)
}

// MARK: - Home screen widget

struct StatusEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct StatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatusEntry {
        StatusEntry(date: Date(), snapshot: WidgetSnapshot(
            babyName: "Baby", lastFeed: Date().addingTimeInterval(-5400), lastFeedDetail: "Breast",
            nextSide: "Left", lastDiaper: Date().addingTimeInterval(-2400), lastDiaperDetail: "Pee",
            sleepingSince: nil, updated: Date()
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (StatusEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : StatusEntry(date: Date(), snapshot: WidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        let entry = StatusEntry(date: Date(), snapshot: WidgetSnapshot.load())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
    }
}

struct StatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LittleLogStatus", provider: StatusProvider()) { entry in
            StatusWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [.sandTop, .mint], startPoint: .top, endPoint: .bottom)
                }
        }
        .configurationDisplayName("Little Log")
        .description("Last feed, next side, last diaper and sleep at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct StatusWidgetView: View {
    let entry: StatusEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let snapshot = entry.snapshot {
            switch family {
            case .accessoryRectangular: lockScreen(snapshot)
            case .systemMedium: medium(snapshot)
            default: small(snapshot)
            }
        } else {
            VStack(spacing: 6) {
                Text("🐘").font(.largeTitle)
                Text("Open Little Log to get started").font(.caption).multilineTextAlignment(.center)
            }
        }
    }

    private func ago(_ date: Date?) -> Text {
        guard let date else { return Text("—") }
        return Text(date, style: .relative)
    }

    private func small(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(s.babyName).font(.system(.headline, design: .rounded).weight(.heavy)).foregroundStyle(Color.canopy)
            if let since = s.sleepingSince {
                row("🐨", Text("Asleep ") + Text(since, style: .relative), tint: .dusk)
            }
            row("🐘", ago(s.lastFeed) + Text(" ago"), tint: .hibiscus)
            if let side = s.nextSide { row("🤱", Text("Next: \(side)"), tint: .hibiscus) }
            row("🐒", ago(s.lastDiaper) + Text(" ago"), tint: .lagoon)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func medium(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(s.babyName).font(.system(.title3, design: .rounded).weight(.heavy)).foregroundStyle(Color.canopy)
                Spacer()
                if let since = s.sleepingSince {
                    (Text("🐨 Asleep ") + Text(since, style: .timer))
                        .font(.caption.weight(.bold)).foregroundStyle(Color.dusk)
                }
            }
            HStack(spacing: 8) {
                tile("🐘", "Last feed", ago(s.lastFeed), tint: .hibiscus)
                tile("🤱", "Next side", Text(s.nextSide ?? "—"), tint: .hibiscus)
                tile("🐒", "Last diaper", ago(s.lastDiaper), tint: .lagoon)
            }
        }
    }

    private func lockScreen(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(s.babyName).font(.headline)
            (Text("Fed ") + ago(s.lastFeed) + Text(" ago")).font(.caption)
            if let side = s.nextSide { Text("Next side: \(side)").font(.caption) }
        }
    }

    private func row(_ animal: String, _ text: Text, tint: Color) -> some View {
        HStack(spacing: 6) {
            Text(animal)
            text.font(.caption.weight(.semibold)).foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    private func tile(_ animal: String, _ title: String, _ value: Text, tint: Color) -> some View {
        VStack(spacing: 3) {
            Text(animal).font(.title3)
            value.font(.caption.weight(.bold)).foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.6)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Live Activity

struct TimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerActivityAttributes.self) { context in
            let tint = Color(hex: context.state.color)
            HStack(spacing: 14) {
                Text(context.state.animal).font(.system(size: 40))
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.babyName).font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    Text(context.state.title).font(.headline)
                }
                Spacer()
                Text(timerInterval: context.state.startedAt...Date.distantFuture, countsDown: false)
                    .font(.system(.title, design: .rounded).weight(.heavy).monospacedDigit())
                    .foregroundStyle(tint)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120, alignment: .trailing)
            }
            .padding(16)
            .activityBackgroundTint(Color.sandTop)
            .activitySystemActionForegroundColor(Color.canopy)
        } dynamicIsland: { context in
            let tint = Color(hex: context.state.color)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.animal).font(.largeTitle)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.title).font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: context.state.startedAt...Date.distantFuture, countsDown: false)
                        .font(.title3.monospacedDigit().weight(.bold))
                        .foregroundStyle(tint)
                        .frame(maxWidth: 80)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.attributes.babyName).font(.caption).foregroundStyle(.secondary)
                }
            } compactLeading: {
                Text(context.state.animal)
            } compactTrailing: {
                Text(timerInterval: context.state.startedAt...Date.distantFuture, countsDown: false)
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .frame(maxWidth: 56)
            } minimal: {
                Text(context.state.animal)
            }
            .keylineTint(tint)
        }
    }
}
