import SwiftUI
import FirebaseCore
import GoogleSignIn

@main
struct LittleLogApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    static var isFirebaseConfigured: Bool {
        Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil
    }

    init() {
        if Self.isFirebaseConfigured {
            FirebaseApp.configure()
        }
    }

    var body: some Scene {
        WindowGroup {
            if DesignPreview.isOn {
                DesignPreviewRoot()
            } else if Self.isFirebaseConfigured {
                AppContainer()
                    .onOpenURL { url in
                        GIDSignIn.sharedInstance.handle(url)
                    }
            } else {
                SetupMissingView()
            }
        }
    }
}

/// Owns the app-wide services once Firebase is configured.
struct AppContainer: View {
    @State private var auth = AuthService()
    @State private var babyStore = BabyStore()

    var body: some View {
        RootView()
            .environment(auth)
            .environment(babyStore)
    }
}
