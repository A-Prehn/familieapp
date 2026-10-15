import SwiftUI

struct RootView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Group {
            if !state.ready {
                ProgressView()
            } else if state.user == nil {
                SignInView()
            } else if state.familyId == nil {
                OnboardingView()
            } else {
                MainTabView()
            }
        }
        .background(Theme.bg.ignoresSafeArea())
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationStack { HomeView() }
                .tabItem { Label("Hjem", systemImage: "house") }

            NavigationStack { FamilyView() }
                .tabItem { Label("Fælles", systemImage: "calendar") }

            NavigationStack { MoreView() }
                .tabItem { Label("Mere", systemImage: "gearshape") }
        }
    }
}
