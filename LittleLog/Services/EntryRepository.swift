import Foundation
import FirebaseFirestore

enum EntryRepository {
    static func entries(for babyID: String) -> CollectionReference {
        Firestore.firestore().collection("babies").document(babyID).collection("entries")
    }

    /// Creates or updates an entry. Writes are queued offline and sync when back online.
    static func save(_ entry: LogEntry, babyID: String, auth: AuthService, metric: Bool) throws {
        var entry = entry
        entry.summary = entry.makeSummary(metric: entry.metric ?? metric)
        let collection = entries(for: babyID)
        if let id = entry.id {
            entry.updatedByUid = auth.uid
            entry.updatedByName = auth.displayName
            entry.updatedAt = Date()
            try collection.document(id).setData(from: entry)
        } else {
            _ = try collection.addDocument(from: entry)
        }
    }

    static func delete(_ entry: LogEntry, babyID: String) {
        guard let id = entry.id else { return }
        entries(for: babyID).document(id).delete()
    }

    static func fetch(babyID: String, from start: Date, to end: Date) async throws -> [LogEntry] {
        let snapshot = try await entries(for: babyID)
            .whereField("timestamp", isGreaterThanOrEqualTo: start)
            .whereField("timestamp", isLessThan: end)
            .order(by: "timestamp")
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: LogEntry.self) }
    }

    /// Every weight, length and head size ever logged, oldest first.
    static func fetchGrowth(babyID: String) async throws -> [LogEntry] {
        let snapshot = try await entries(for: babyID)
            .whereField("kind", isEqualTo: EntryKind.weight.rawValue)
            .getDocuments()
        return snapshot.documents
            .compactMap { try? $0.data(as: LogEntry.self) }
            .sorted { $0.timestamp < $1.timestamp }
    }
}

/// Live list of a baby's entries within a time window, newest first.
@Observable
final class EntriesListener {
    private(set) var entries: [LogEntry] = []
    private(set) var hasLoaded = false

    @ObservationIgnored private var listener: ListenerRegistration?

    func listen(babyID: String, from start: Date, to end: Date? = nil) {
        stop()
        var query: Query = EntryRepository.entries(for: babyID)
            .whereField("timestamp", isGreaterThanOrEqualTo: start)
        if let end { query = query.whereField("timestamp", isLessThan: end) }
        listener = query
            .order(by: "timestamp", descending: true)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self else { return }
                self.entries = snapshot?.documents.compactMap { try? $0.data(as: LogEntry.self) } ?? []
                self.hasLoaded = true
            }
    }

    func stop() {
        listener?.remove()
        listener = nil
    }

    deinit { listener?.remove() }
}
