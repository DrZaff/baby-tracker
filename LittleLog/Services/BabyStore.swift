import Foundation
import FirebaseFirestore

/// The babies the signed-in person can see: every baby whose memberEmails contains their email.
@Observable
final class BabyStore {
    private(set) var babies: [Baby] = []
    private(set) var hasLoaded = false
    private(set) var selectedBabyID: String?
    var errorMessage: String?

    @ObservationIgnored private var listener: ListenerRegistration?
    private var db: Firestore { Firestore.firestore() }
    private static let selectionKey = "selectedBabyID"

    init() {
        selectedBabyID = UserDefaults.standard.string(forKey: Self.selectionKey)
    }

    var selectedBaby: Baby? {
        babies.first { $0.id == selectedBabyID } ?? babies.first
    }

    func select(_ baby: Baby) {
        selectedBabyID = baby.id
        UserDefaults.standard.set(baby.id, forKey: Self.selectionKey)
    }

    /// Sample baby for the design preview.
    func showDemo() {
        babies = [DemoData.baby]
        hasLoaded = true
    }

    func start(email: String) {
        guard !DesignPreview.isOn else { return showDemo() }
        stop()
        listener = db.collection("babies")
            .whereField("memberEmails", arrayContains: email)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error { self.errorMessage = error.localizedDescription }
                let list = snapshot?.documents.compactMap { try? $0.data(as: Baby.self) } ?? []
                self.babies = list.sorted { $0.createdAt < $1.createdAt }
                self.hasLoaded = true
            }
    }

    func stop() {
        listener?.remove()
        listener = nil
        babies = []
        hasLoaded = false
    }

    @discardableResult
    func createBaby(name: String, birthDate: Date, sex: BabySex?, ownerUid: String, ownerEmail: String) throws -> String {
        let ref = db.collection("babies").document()
        let baby = Baby(
            name: name,
            birthDate: birthDate,
            sex: sex,
            ownerUid: ownerUid,
            ownerEmail: ownerEmail,
            memberEmails: [ownerEmail],
            createdAt: Date()
        )
        try ref.setData(from: baby)
        selectedBabyID = ref.documentID
        UserDefaults.standard.set(ref.documentID, forKey: Self.selectionKey)
        return ref.documentID
    }

    func updateBaby(_ baby: Baby, name: String, birthDate: Date, sex: BabySex?) {
        db.collection("babies").document(baby.babyID).updateData([
            "name": name,
            "birthDate": Timestamp(date: birthDate),
            "sex": sex?.rawValue ?? NSNull(),
        ])
    }

    func setFeedReminder(hours: Double?, for baby: Baby) {
        db.collection("babies").document(baby.babyID).updateData([
            "feedReminderHours": hours ?? NSNull(),
        ])
    }

    func setVitaminDReminder(_ on: Bool, for baby: Baby) {
        var data: [String: Any] = ["vitaminDReminder": on]
        if on && baby.vitaminDSince == nil {
            data["vitaminDSince"] = Timestamp(date: Calendar.current.startOfDay(for: Date()))
        }
        db.collection("babies").document(baby.babyID).updateData(data)
    }

    func addCaregiver(email: String, to baby: Baby) {
        let cleaned = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleaned.isEmpty else { return }
        db.collection("babies").document(baby.babyID)
            .updateData(["memberEmails": FieldValue.arrayUnion([cleaned])])
    }

    func removeCaregiver(email: String, from baby: Baby) {
        guard email != baby.ownerEmail else { return }
        db.collection("babies").document(baby.babyID)
            .updateData(["memberEmails": FieldValue.arrayRemove([email])])
    }
}
