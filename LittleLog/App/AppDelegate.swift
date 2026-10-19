import UIKit
import FirebaseMessaging
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        guard LittleLogApp.isFirebaseConfigured else { return true }
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Push registration failed: \(error.localizedDescription)")
    }

    /// Another caregiver logged something: refresh the home screen widget in the background.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        guard LittleLogApp.isFirebaseConfigured, let babyID = userInfo["babyId"] as? String else { return .noData }
        let selected = UserDefaults.standard.string(forKey: "selectedBabyID")
        guard selected == nil || selected == babyID else { return .noData }
        let since = Calendar.current.date(byAdding: .day, value: -3, to: Date()) ?? Date()
        guard let entries = try? await EntryRepository.fetch(babyID: babyID, from: since, to: Date().addingTimeInterval(60)) else {
            return .failed
        }
        let name = UserDefaults.standard.string(forKey: "selectedBabyName") ?? "Baby"
        WidgetSnapshot.publish(babyName: name, entries: entries.sorted { $0.timestamp > $1.timestamp })
        return .newData
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        DispatchQueue.main.async {
            PushNotifications.shared.update(token: fcmToken)
        }
    }

    // Show banners even while the app is open.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}
