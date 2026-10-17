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
    @EnvironmentObject var state: AppState
    @State private var selection: MainTab = .home
    @State private var interview: InterviewTarget?

    init() {
        // Kun farven sættes — ingen egen UITabBarAppearance, så iOS 26 beholder Liquid Glass.
        UITabBar.appearance().unselectedItemTintColor = UIColor(Theme.muted)
    }

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { HomeView().tabSwipe(.home, selection: $selection) }
                .tabItem { tabLabel("Hjem", "house", .home) }
                .tag(MainTab.home)

            NavigationStack { ChildrenView().tabSwipe(.family, selection: $selection) }
                .tabItem { tabLabel("Børn", "person.2", .family) }
                .tag(MainTab.family)

            NavigationStack { FamilyView().tabSwipe(.shared, selection: $selection) }
                .tabItem { tabLabel("Familie", "heart.text.square", .shared) }
                .tag(MainTab.shared)

            NavigationStack { MoreView().tabSwipe(.more, selection: $selection) }
                .tabItem { tabLabel("Mere", "gearshape", .more) }
                .tag(MainTab.more)
        }
        // "Gemmer…" og fejl fra gem i baggrunden, lige over fanebjælken.
        .overlay(alignment: .bottom) { SaveQueueBanner().padding(.bottom, 56) }
        // Tryk på interview-påmindelsen: åbn interviewet for barnet.
        .sheet(item: $interview) { target in
            NavigationStack {
                InterviewView(child: target.child, initialAge: target.age)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Luk") { interview = nil } }
                    }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openInterview)) { _ in Task { await openPendingInterview() } }
        .task { await openPendingInterview() }
    }

    struct InterviewTarget: Identifiable {
        let child: Child
        let age: Int
        var id: String { "\(child.id)_\(age)" }
    }

    private func openPendingInterview() async {
        guard let link = DeepLink.pendingInterview, let familyId = state.familyId else { return }
        DeepLink.pendingInterview = nil
        guard let child = (try? await state.store.children(familyId: familyId))?.first(where: { $0.id == link.childId }) else { return }
        interview = InterviewTarget(child: child, age: link.age)
    }

    // iOS 26's glas-tabbar farver selv ikonerne sort/hvid. Ikonerne tegnes derfor som
    // færdigfarvede billeder, og SwiftUI får eksplicit besked på at beholde farven
    // (.renderingMode(.original)) — ellers laves de om til skabeloner igen.
    private func tabLabel(_ title: String, _ symbol: String, _ tab: MainTab) -> some View {
        let selected = selection == tab
        let color = selected ? Theme.tint : Theme.muted
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: selected ? .semibold : .regular)
        let image = (UIImage(systemName: symbol, withConfiguration: config) ?? UIImage())
            .withTintColor(UIColor(color), renderingMode: .alwaysOriginal)
        return Label {
            Text(title).foregroundStyle(color)
        } icon: {
            Image(uiImage: image).renderingMode(.original)
        }
    }
}

// Vandret swipe på fanernes forsider skifter fane: højre → fanen til venstre
// (tilbage mod Hjem), venstre → fanen til højre. Sidder kun på forsiderne,
// så undersider beholder iOS' normale swipe-tilbage fra kanten.
private struct TabSwipe: ViewModifier {
    let tab: MainTab
    @Binding var selection: MainTab
    /// Områder (fx en vandret rullende række), hvor et swipe ikke må skifte fane.
    @State private var blocked: [CGRect] = []

    func body(content: Content) -> some View {
        content
            .coordinateSpace(name: TabSwipeSpace.name)
            .onPreferenceChange(NoTabSwipeKey.self) { blocked = $0 }
            .simultaneousGesture(
            DragGesture(minimumDistance: 30, coordinateSpace: .named(TabSwipeSpace.name)).onEnded { value in
                // Startede swipet i en vandret rullende række, er det rulningen — ikke et faneskift.
                if blocked.contains(where: { $0.contains(value.startLocation) }) { return }
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

private enum TabSwipeSpace { static let name = "tabSwipe" }

private struct NoTabSwipeKey: PreferenceKey {
    static var defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) { value.append(contentsOf: nextValue()) }
}

extension View {
    func tabSwipe(_ tab: MainTab, selection: Binding<MainTab>) -> some View {
        modifier(TabSwipe(tab: tab, selection: selection))
    }

    /// Markér en vandret rullende række, så swipes i den ikke skifter hovedfane.
    func noTabSwipe() -> some View {
        background(GeometryReader { geo in
            Color.clear.preference(key: NoTabSwipeKey.self, value: [geo.frame(in: .named(TabSwipeSpace.name))])
        })
    }
}
