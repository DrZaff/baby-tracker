import SwiftUI

struct RootView: View {
    @Environment(AuthService.self) private var auth
    @Environment(BabyStore.self) private var store

    var body: some View {
        Group {
            if auth.isLoading {
                ProgressView()
            } else if auth.user == nil {
                SignInView()
            } else if !store.hasLoaded {
                ProgressView("Loading…")
            } else if store.babies.isEmpty {
                NavigationStack {
                    BabyFormView(mode: .create, isFirstBaby: true)
                }
            } else {
                MainTabView()
            }
        }
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

    var body: some View {
        if let baby = store.selectedBaby {
            TabView {
                TodayView(baby: baby)
                    .tabItem { Label("Today", systemImage: "list.bullet.rectangle.portrait") }
                TrendsView(baby: baby)
                    .tabItem { Label("Trends", systemImage: "chart.bar.xaxis") }
                PhotosView(baby: baby)
                    .tabItem { Label("Photos", systemImage: "photo.on.rectangle") }
                FamilyView(baby: baby)
                    .tabItem { Label("Family", systemImage: "person.2") }
            }
        }
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
