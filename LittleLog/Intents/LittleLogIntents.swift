import AppIntents
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore

// Siri and Shortcuts: "Hey Siri, log a diaper in Little Log" and friends.
// These run in the background without opening the app, for the baby picked in the app.

enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case signedOut, noBaby, notSleeping

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .signedOut: return "Open Little Log and sign in first."
        case .noBaby: return "Open Little Log and add your baby first."
        case .notSleeping: return "The baby isn't logged as sleeping."
        }
    }
}

enum IntentBackend {
    struct Context {
        let babyID: String
        let babyName: String
        let uid: String
        let name: String
    }

    static var metric: Bool { UserDefaults.standard.bool(forKey: "useMetric") }

    static func context() async throws -> Context {
        if FirebaseApp.app() == nil { FirebaseApp.configure() }
        guard let user = Auth.auth().currentUser, let email = user.email?.lowercased() else { throw IntentError.signedOut }
        let snapshot = try await Firestore.firestore().collection("babies")
            .whereField("memberEmails", arrayContains: email)
            .getDocuments()
        let babies = snapshot.documents
            .compactMap { try? $0.data(as: Baby.self) }
            .sorted { $0.createdAt < $1.createdAt }
        let selected = UserDefaults.standard.string(forKey: "selectedBabyID")
        guard let baby = babies.first(where: { $0.id == selected }) ?? babies.first else { throw IntentError.noBaby }
        let fullName = user.displayName ?? ""
        let name = fullName.isEmpty ? email : (fullName.components(separatedBy: " ").first ?? fullName)
        return Context(babyID: baby.babyID, babyName: baby.name, uid: user.uid, name: name)
    }

    static func newEntry(_ kind: EntryKind, _ context: Context) -> LogEntry {
        LogEntry(kind: kind, createdByUid: context.uid, createdByName: context.name)
    }

    /// Saves and waits for the server, so the entry isn't lost if the app goes back to sleep.
    static func save(_ entry: LogEntry, _ context: Context) async throws {
        var entry = entry
        entry.summary = entry.makeSummary(metric: entry.metric ?? metric)
        let collection = EntryRepository.entries(for: context.babyID)
        let document = entry.id.map { collection.document($0) } ?? collection.document()
        if entry.id != nil {
            entry.updatedByUid = context.uid
            entry.updatedByName = context.name
            entry.updatedAt = Date()
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                try document.setData(from: entry) { error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    static func recent(_ context: Context, days: Int = 3) async throws -> [LogEntry] {
        let since = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let entries = try await EntryRepository.fetch(babyID: context.babyID, from: since, to: Date().addingTimeInterval(60))
        return entries.sorted { $0.timestamp > $1.timestamp }
    }
}

enum DiaperKind: String, AppEnum {
    case pee, poop, both

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Diaper"
    static let caseDisplayRepresentations: [DiaperKind: DisplayRepresentation] = [
        .pee: "pee (wet)",
        .poop: "poop (dirty)",
        .both: "pee and poop",
    ]
}

enum VolumeUnit: String, AppEnum {
    case ounces, millilitres

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Unit"
    static let caseDisplayRepresentations: [VolumeUnit: DisplayRepresentation] = [
        .ounces: "ounces",
        .millilitres: "milliliters",
    ]
}

enum BottleKind: String, AppEnum {
    case formula, breastMilk

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Bottle contents"
    static let caseDisplayRepresentations: [BottleKind: DisplayRepresentation] = [
        .formula: "formula",
        .breastMilk: "breast milk",
    ]
}

struct LogDiaperIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a diaper"
    static let description = IntentDescription("Logs a diaper change in Little Log.")

    @Parameter(title: "Diaper", requestValueDialog: "Pee, poop, or both?")
    var kind: DiaperKind

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = try await IntentBackend.context()
        var entry = IntentBackend.newEntry(.diaper, context)
        entry.wet = kind != .poop
        entry.dirty = kind != .pee
        try await IntentBackend.save(entry, context)
        let what = kind == .both ? "pee and poop" : kind.rawValue
        return .result(dialog: IntentDialog(stringLiteral: "Logged a \(what) diaper for \(context.babyName). 🐒"))
    }
}

struct LogBottleIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a bottle"
    static let description = IntentDescription("Logs a bottle feed in Little Log.")

    @Parameter(title: "Amount", requestValueDialog: "How much did the baby drink?")
    var amount: Double

    @Parameter(title: "Unit", requestValueDialog: "Ounces or milliliters?")
    var unit: VolumeUnit

    @Parameter(title: "Contents", default: .formula)
    var contents: BottleKind

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = try await IntentBackend.context()
        let metric = unit == .millilitres
        var entry = IntentBackend.newEntry(.feed, context)
        entry.bottleML = Units.millilitres(from: amount, metric: metric)
        entry.bottleContent = contents == .breastMilk ? .breastMilk : .formula
        entry.metric = metric
        try await IntentBackend.save(entry, context)
        let volume = Units.volume(entry.bottleML ?? 0, metric: metric)
        return .result(dialog: IntentDialog(stringLiteral: "Logged a \(volume) bottle of \(contents == .formula ? "formula" : "breast milk") for \(context.babyName). 🦒"))
    }
}

struct StartSleepIntent: AppIntent {
    static let title: LocalizedStringResource = "Start a sleep"
    static let description = IntentDescription("Logs that the baby fell asleep.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = try await IntentBackend.context()
        if try await IntentBackend.recent(context).contains(where: { $0.isSleeping }) {
            return .result(dialog: IntentDialog(stringLiteral: "\(context.babyName) is already logged as sleeping."))
        }
        try await IntentBackend.save(IntentBackend.newEntry(.sleep, context), context)
        return .result(dialog: IntentDialog(stringLiteral: "Sweet dreams, \(context.babyName). 🐨"))
    }
}

struct WakeUpIntent: AppIntent {
    static let title: LocalizedStringResource = "Baby woke up"
    static let description = IntentDescription("Ends the current sleep.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = try await IntentBackend.context()
        guard var sleep = try await IntentBackend.recent(context).first(where: { $0.isSleeping }) else {
            throw IntentError.notSleeping
        }
        sleep.sleepEnd = Date()
        try await IntentBackend.save(sleep, context)
        await LiveActivities.shared.endSleep()
        return .result(dialog: IntentDialog(stringLiteral: "Good morning, \(context.babyName)! That was \(Units.spoken(sleep.sleepSeconds())) of sleep. ☀️"))
    }
}

struct LastFeedIntent: AppIntent {
    static let title: LocalizedStringResource = "When was the last feed?"
    static let description = IntentDescription("Says how long ago the baby last ate, and which side is next.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = try await IntentBackend.context()
        let entries = try await IntentBackend.recent(context)
        guard let feed = entries.first(where: { $0.isFeeding }) else {
            return .result(dialog: IntentDialog(stringLiteral: "No feeds logged for \(context.babyName) in the last few days."))
        }
        var text = "\(context.babyName) last ate \(Units.spoken(Int(Date().timeIntervalSince(feed.timestamp)))) ago"
        if let side = entries.first(where: { $0.kind == .feed && $0.breastLastSide != nil })?.breastLastSide {
            text += ". Next side is \(side == .left ? "right" : "left")"
        }
        return .result(dialog: IntentDialog(stringLiteral: text + "."))
    }
}

struct LittleLogShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogDiaperIntent(),
            phrases: [
                "Log a diaper in \(.applicationName)",
                "Log a \(\.$kind) diaper in \(.applicationName)",
                "Diaper change in \(.applicationName)",
            ],
            shortTitle: "Log diaper",
            systemImageName: "humidity.fill"
        )
        AppShortcut(
            intent: LogBottleIntent(),
            phrases: [
                "Log a bottle in \(.applicationName)",
                "Log a \(\.$contents) bottle in \(.applicationName)",
            ],
            shortTitle: "Log bottle",
            systemImageName: "drop.fill"
        )
        AppShortcut(
            intent: StartSleepIntent(),
            phrases: [
                "Start a nap in \(.applicationName)",
                "Baby fell asleep in \(.applicationName)",
            ],
            shortTitle: "Start sleep",
            systemImageName: "moon.zzz.fill"
        )
        AppShortcut(
            intent: WakeUpIntent(),
            phrases: [
                "Baby woke up in \(.applicationName)",
                "End the nap in \(.applicationName)",
            ],
            shortTitle: "Woke up",
            systemImageName: "sun.max.fill"
        )
        AppShortcut(
            intent: LastFeedIntent(),
            phrases: [
                "When was the last feed in \(.applicationName)",
                "Last feed in \(.applicationName)",
            ],
            shortTitle: "Last feed",
            systemImageName: "clock.fill"
        )
    }
}
