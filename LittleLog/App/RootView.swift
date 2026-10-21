import SwiftUI

struct RootView: View {
    @Environment(AuthService.self) private var auth
    @Environment(BabyStore.self) private var store

    var body: some View {
        Group {
            if auth.isLoading {
                JungleLoading()
            } else if auth.user == nil {
                SignInView()
            } else if !store.hasLoaded {
                JungleLoading()
            } else if store.babies.isEmpty {
                NavigationStack {
                    BabyFormView(mode: .create, isFirstBaby: true)
                }
            } else {
                MainTabView()
            }
        }
        .tint(Theme.canopy)
        .fontDesign(.rounded)
        .task(id: auth.user?.uid) {
            if let email = auth.email {
                store.start(email: email)
                PushNotifications.shared.signedIn(uid: auth.user?.uid)
                await PushNotifications.shared.requestPermission()
            } else {
                store.stop()
                PushNotifications.shared.signedIn(uid: nil)
            }
        }
    }
}

struct MainTabView: View {
    @Environment(BabyStore.self) private var store
    @State private var tab = DesignPreview.isOn ? DesignPreview.screen : "today"

    var body: some View {
        if let baby = store.selectedBaby {
            TabView(selection: $tab) {
                TodayView(baby: baby)
                    .tag("today")
                    .tabItem { Label("Today", systemImage: "sun.max.fill") }
                TrendsView(baby: baby)
                    .tag("trends")
                    .tabItem { Label("Trends", systemImage: "chart.bar.fill") }
                PhotosView(baby: baby)
                    .tag("photos")
                    .tabItem { Label("Photos", systemImage: "camera.fill") }
                FamilyView(baby: baby)
                    .tag("family")
                    .tabItem { Label("Family", systemImage: "pawprint.fill") }
            }
            .celebratesMilestones()
        }
    }
}

/// A monkey swinging gently while things load.
struct JungleLoading: View {
    @State private var swing = false

    var body: some View {
        VStack(spacing: 12) {
            Text("🐒")
                .font(.system(size: 64))
                .rotationEffect(.degrees(swing ? 12 : -12), anchor: .top)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: swing)
            ProgressView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(JungleBackground())
        .onAppear { swing = true }
    }
}

struct SetupMissingView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Almost ready", systemImage: "wrench.and.screwdriver")
        } description: {
            Text("Add GoogleService-Info.plist from your Firebase project to the LittleLog folder, then run xcodegen again. The README walks through it.")
        }
    }
}
