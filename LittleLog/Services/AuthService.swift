import SwiftUI
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import GoogleSignIn

@Observable
final class AuthService {
    private(set) var user: User?
    private(set) var isLoading = true
    var errorMessage: String?

    @ObservationIgnored private var handle: AuthStateDidChangeListenerHandle?

    var email: String? { user?.email?.lowercased() }
    var uid: String { user?.uid ?? "" }
    var displayName: String {
        if let name = user?.displayName, !name.isEmpty {
            return name.components(separatedBy: " ").first ?? name
        }
        return user?.email ?? "Someone"
    }

    init() {
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            self.user = user
            self.isLoading = false
            if let user { Self.saveProfile(user) }
        }
    }

    @MainActor
    func signInWithGoogle() async {
        errorMessage = nil
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            errorMessage = "Firebase isn't set up yet (missing client ID)."
            return
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        guard let presenter = UIApplication.topViewController() else { return }
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            guard let idToken = result.user.idToken?.tokenString else {
                errorMessage = "Google didn't return a sign-in token. Please try again."
                return
            }
            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: result.user.accessToken.tokenString
            )
            _ = try await Auth.auth().signIn(with: credential)
        } catch let error as GIDSignInError where error.code == .canceled {
            // The person closed the Google sheet.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func signOut() async {
        await PushNotifications.shared.removeCurrentToken()
        GIDSignIn.sharedInstance.signOut()
        WidgetSnapshot.clear()
        do {
            try Auth.auth().signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// users/{uid} holds the email (so invites can be matched) and push tokens.
    private static func saveProfile(_ user: User) {
        var data: [String: Any] = ["lastSignIn": FieldValue.serverTimestamp()]
        if let email = user.email { data["email"] = email.lowercased() }
        if let name = user.displayName { data["displayName"] = name }
        Firestore.firestore().collection("users").document(user.uid).setData(data, merge: true)
    }
}

extension UIApplication {
    @MainActor
    static func topViewController() -> UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
