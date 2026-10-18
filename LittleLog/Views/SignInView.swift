import SwiftUI

struct SignInView: View {
    @Environment(AuthService.self) private var auth
    @State private var isSigningIn = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 72))
                .foregroundStyle(Theme.feed)
            VStack(spacing: 8) {
                Text("Little Log")
                    .font(.largeTitle.bold())
                Text("Feeds, diapers, naps and firsts,\nshared with everyone who cares for your baby.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            Button {
                isSigningIn = true
                Task {
                    await auth.signInWithGoogle()
                    isSigningIn = false
                }
            } label: {
                HStack {
                    if isSigningIn { ProgressView().tint(.white) }
                    Text("Continue with Google").fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .disabled(isSigningIn)

            if let message = auth.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(32)
    }
}
