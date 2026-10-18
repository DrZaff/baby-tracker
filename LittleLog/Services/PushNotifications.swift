import UIKit
import UserNotifications
import FirebaseFirestore
import FirebaseMessaging

/// Keeps this device's push token on the signed-in user's profile so the
/// Cloud Function can notify every caregiver when someone logs something.
final class PushNotifications {
    static let shared = PushNotifications()

    private var token: String?
    private var uid: String?

    func update(token: String?) {
        self.token = token
        save()
    }

    func signedIn(uid: String?) {
        self.uid = uid
        save()
    }

    @MainActor
    func requestPermission() async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        if granted {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    func removeCurrentToken() async {
        guard let token, let uid else { return }
        try? await Firestore.firestore().collection("users").document(uid)
            .updateData(["fcmTokens": FieldValue.arrayRemove([token])])
    }

    private func save() {
        guard let token, let uid else { return }
        Firestore.firestore().collection("users").document(uid)
            .setData(["fcmTokens": FieldValue.arrayUnion([token])], merge: true)
    }
}
