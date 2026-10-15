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

enum MainTab: Int, CaseIterable, Hashable {
    case home, family, shared, more
}

struct MainTabView: View {
    @State private var selection: MainTab = .home

    init() {
        // Ikke-valgte faner i appens dæmpede grå i stedet for sort (valgt fane = Theme.tint).
        let muted = UIColor(Theme.muted)
        UITabBar.appearance().unselectedItemTintColor = muted
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        for layout in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance,
                       appearance.compactInlineLayoutAppearance] {
            layout.normal.iconColor = muted
            layout.normal.titleTextAttributes = [.foregroundColor: muted]
        }
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { HomeView().tabSwipe(.home, selection: $selection) }
                .tabItem { tabLabel("Hjem", "house", .home) }
                .tag(MainTab.home)

            NavigationStack { ChildrenView().tabSwipe(.family, selection: $selection) }
                .tabItem { tabLabel("Familie", "person.2", .family) }
                .tag(MainTab.family)

            NavigationStack { FamilyView().tabSwipe(.shared, selection: $selection) }
                .tabItem { tabLabel("Fælles", "calendar", .shared) }
                .tag(MainTab.shared)

            NavigationStack { MoreView().tabSwipe(.more, selection: $selection) }
                .tabItem { tabLabel("Mere", "gearshape", .more) }
                .tag(MainTab.more)
        }
    }

    // iOS 26's glas-tabbar ignorerer UITabBarAppearance for ikonfarver, så ikonerne
    // tegnes som færdigfarvede billeder: dæmpet grå når ikke valgt, appens blå når valgt.
    private func tabLabel(_ title: String, _ symbol: String, _ tab: MainTab) -> some View {
        let selected = selection == tab
        let color = UIColor(selected ? Theme.tint : Theme.muted)
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: selected ? .semibold : .regular)
        let image = (UIImage(systemName: symbol, withConfiguration: config) ?? UIImage())
            .withTintColor(color, renderingMode: .alwaysOriginal)
        return Label { Text(title) } icon: { Image(uiImage: image) }
    }
}

// Vandret swipe på fanernes forsider skifter fane: højre → fanen til venstre
// (tilbage mod Hjem), venstre → fanen til højre. Sidder kun på forsiderne,
// så undersider beholder iOS' normale swipe-tilbage fra kanten.
private struct TabSwipe: ViewModifier {
    let tab: MainTab
    @Binding var selection: MainTab

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 30).onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dx) > 80, abs(dx) > abs(dy) * 2 else { return }
                let all = MainTab.allCases
                guard let index = all.firstIndex(of: tab) else { return }
                let next = dx < 0 ? index + 1 : index - 1
                guard all.indices.contains(next) else { return }
                withAnimation(.easeInOut(duration: 0.2)) { selection = all[next] }
            }
        )
    }
}

extension View {
    func tabSwipe(_ tab: MainTab, selection: Binding<MainTab>) -> some View {
        modifier(TabSwipe(tab: tab, selection: selection))
    }
}
