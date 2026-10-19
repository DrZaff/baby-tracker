import SwiftUI

struct SignInView: View {
    @Environment(AuthService.self) private var auth
    @State private var isSigningIn = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Theme.lime, Theme.leaf], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 170, height: 170)
                    .shadow(color: Theme.canopy.opacity(0.3), radius: 18, y: 8)
                Text("🐘").font(.system(size: 96)).offset(y: 6)
                Text("🌺").font(.system(size: 36)).offset(x: 66, y: -62)
                Text("🦜").font(.system(size: 40)).offset(x: -74, y: -40)
                Text("🐒").font(.system(size: 40)).offset(x: 72, y: 56)
            }
            .accessibilityHidden(true)
            VStack(spacing: 10) {
                Text("Little Log")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.canopy)
                Text("Feeds, diapers, growth and firsts,\nshared with everyone in your baby's jungle.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text("🦁 🦒 🦛 🐯 🦩")
                    .font(.title2)
                    .accessibilityHidden(true)
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
            .tint(Theme.canopy)
            .shadow(color: Theme.canopy.opacity(0.3), radius: 10, y: 5)
            .disabled(isSigningIn)

            if let message = auth.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(32)
        .background(JungleBackground())
    }
}
