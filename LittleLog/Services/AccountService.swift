import AuthenticationServices
import CryptoKit
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import FirebaseStorage
import GoogleSignIn
import UIKit

/// Sign in with Apple support, plus deleting an account and everything only that person can see.
enum AppleSignIn {
    static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        if SecRandomCopyBytes(kSecRandomDefault, length, &bytes) != errSecSuccess {
            return UUID().uuidString + UUID().uuidString
        }
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Asks Apple to confirm the person again, outside of the sign-in button (used before deleting an account).
    @MainActor
    static func authorize(nonce: String) async throws -> ASAuthorizationAppleIDCredential {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = []
        request.nonce = sha256(nonce)
        let controller = ASAuthorizationController(authorizationRequests: [request])
        let delegate = Delegate()
        controller.delegate = delegate
        controller.presentationContextProvider = delegate
        // The controller only holds its delegate weakly, so keep both alive until Apple answers.
        active = (controller, delegate)
        defer { active = nil }
        return try await withCheckedThrowingContinuation { continuation in
            delegate.continuation = continuation
            controller.performRequests()
        }
    }

    @MainActor private static var active: (ASAuthorizationController, Delegate)?

    private final class Delegate: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
        var continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?

        func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
            if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
                continuation?.resume(returning: credential)
            } else {
                continuation?.resume(throwing: ASAuthorizationError(.failed))
            }
            continuation = nil
        }

        func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
            continuation?.resume(throwing: error)
            continuation = nil
        }

        func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
            UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                .first ?? ASPresentationAnchor()
        }
    }
}

enum AccountError: LocalizedError {
    case signedOut, missingToken

    var errorDescription: String? {
        switch self {
        case .signedOut: return "You're not signed in."
        case .missingToken: return "Couldn't confirm your account. Please try again."
        }
    }
}

extension AuthService {
    var signedInWithApple: Bool {
        user?.providerData.contains { $0.providerID == "apple.com" } == true
    }

    /// Deletes the signed-in account:
    /// - babies only this person can see are deleted with all their entries, photos and appointments,
    /// - babies shared with others stay for them (ownership passes to another caregiver),
    /// - then the sign-in itself is deleted.
    @MainActor
    func deleteAccount(babies: [Baby]) async throws {
        guard let user = Auth.auth().currentUser, let email = self.email else { throw AccountError.signedOut }

        // Apple and Firebase both want a fresh confirmation before deleting.
        var appleAuthorizationCode: String?
        if signedInWithApple {
            let nonce = AppleSignIn.randomNonce()
            let apple = try await AppleSignIn.authorize(nonce: nonce)
            guard let tokenData = apple.identityToken, let idToken = String(data: tokenData, encoding: .utf8) else {
                throw AccountError.missingToken
            }
            appleAuthorizationCode = apple.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
            let credential = OAuthProvider.appleCredential(withIDToken: idToken, rawNonce: nonce, fullName: nil)
            _ = try await user.reauthenticate(with: credential)
        } else {
            if let clientID = FirebaseApp.app()?.options.clientID {
                GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
            }
            guard let presenter = UIApplication.topViewController() else { throw AccountError.missingToken }
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter, hint: email, additionalScopes: nil)
            guard let idToken = result.user.idToken?.tokenString else { throw AccountError.missingToken }
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: result.user.accessToken.tokenString)
            _ = try await user.reauthenticate(with: credential)
        }

        let db = Firestore.firestore()
        for baby in babies where baby.memberEmails.contains(email) {
            let others = baby.memberEmails.filter { $0 != email }
            let ref = db.collection("babies").document(baby.babyID)
            if others.isEmpty {
                try await Self.deleteEverything(for: baby.babyID)
                try await ref.delete()
            } else if baby.ownerEmail == email {
                try await ref.updateData([
                    "ownerEmail": others[0],
                    "ownerUid": "",
                    "memberEmails": others,
                ])
            } else {
                try await ref.updateData(["memberEmails": FieldValue.arrayRemove([email])])
            }
        }

        await PushNotifications.shared.removeCurrentToken()
        try? await db.collection("users").document(user.uid).delete()
        if let code = appleAuthorizationCode {
            try? await Auth.auth().revokeToken(withAuthorizationCode: code)
        }
        try await user.delete()
        GIDSignIn.sharedInstance.signOut()
        WidgetSnapshot.clear()
    }

    /// Deletes a baby's entries, appointments and photos (including the image files).
    private static func deleteEverything(for babyID: String) async throws {
        let baby = Firestore.firestore().collection("babies").document(babyID)
        let storage = Storage.storage()
        for name in ["entries", "appointments", "photos", "vaccines"] {
            while true {
                let page = try await baby.collection(name).limit(to: 300).getDocuments()
                if page.documents.isEmpty { break }
                let batch = Firestore.firestore().batch()
                for document in page.documents {
                    if name == "photos" {
                        for key in ["storagePath", "thumbStoragePath"] {
                            if let path = document.data()[key] as? String, !path.isEmpty {
                                try? await storage.reference(withPath: path).delete()
                            }
                        }
                    }
                    batch.deleteDocument(document.reference)
                }
                try await batch.commit()
            }
        }
    }
}
