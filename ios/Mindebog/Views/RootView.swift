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
    @State private var prompt: PromptTarget?
    @State private var content: ContentTarget?

    /// Det, en notifikation om et barn handler om: barnet og hvilken skærm.
    struct ContentTarget: Identifiable {
        let child: Child
        let kind: String
        let galleryKind: String
        var id: String { child.id + kind + galleryKind }
    }

    @ViewBuilder
    private func contentView(_ t: ContentTarget) -> some View {
        switch t.kind {
        case "Highlight": HighlightsView(child: t.child)
        case "Diary": DiaryView(child: t.child)
        // Milepæle: galleryKind rummer her milepælens nøgle; vaccinationer ("vac_…") har deres egen skærm.
        case "Milestone":
            if t.galleryKind.hasPrefix("vac_") { VaccinesView(child: t.child) } else { MilestonesView(child: t.child) }
        // Interview: galleryKind rummer alderen, så den rigtige årgang vises.
        case "Interview": InterviewView(child: t.child, initialAge: Int(t.galleryKind))
        case "Letter": LettersView(child: t.child)
        case "Answer": AboutMeView(child: t.child)
        case "Measurement": GrowthView(child: t.child)
        case "GalleryItem":
            if t.galleryKind == GalleryKind.birthday.rawValue { BirthdayPhotosView(child: t.child) }
            else { GalleryView(child: t.child, kind: GalleryKind(rawValue: t.galleryKind) ?? .monthly) }
        case "YearReview":   // galleryKind rummer her hvilket år ("cal:2025" / "age:3")
            YearInReviewView(child: t.child, spec: YearSpec(raw: t.galleryKind)
                             ?? YearSpec.current(for: t.child) ?? .calendar(Calendar.current.component(.year, from: Date())))
        default: ChildDetailView(child: t.child)
        }
    }

    /// Navigér til det, notifikationen handler om.
    private func open(_ e: NotificationLogEntry) async {
        // Påmindelser: interview og ugens spørgsmål har deres egne skærme.
        if let childId = e.info["interviewChild"], let age = Int(e.info["interviewAge"] ?? "") {
            DeepLink.pendingInterview = DeepLink.Interview(childId: childId, age: age)
            await openPendingInterview(); return
        }
        if let childId = e.info["promptChild"], let text = e.info["promptText"] {
            DeepLink.pendingPrompt = DeepLink.Prompt(childId: childId, text: text)
            await openPendingPrompt(); return
        }
        // Fælles indhold: skift til Familie og det rigtige faneblad.
        let familyTabs: [String: FamilyView.Tab] = [
            "Memory": .memories, "Event": .events, "Vacation": .vacations, "Birthday": .birthdays,
            "Tradition": .traditions, "Recipe": .recipes, "Person": .tree]
        JumpRequest.shared.recordId = e.recordId   // listen scroller hen til opslaget (jumpsToPendingRecord)
        if let tab = familyTabs[e.kind] {
            selection = .shared
            FamilyTabLink.pending = tab.rawValue
            NotificationCenter.default.post(name: .openFamilyTab, object: tab.rawValue)
            return
        }
        // Et barns indhold (eller en påmindelse om et barn): åbn barnets skærm.
        let childId = e.childId ?? e.info["child"] ?? (e.kind == "Child" ? e.recordId : nil)
        guard let childId, let familyId = state.familyId else { selection = .home; return }
        var kids = (try? await state.store.children(familyId: familyId)) ?? []
        kids += (try? await state.store.sharedChildren()) ?? []
        guard let child = kids.first(where: { $0.id == childId }) else { selection = .home; return }
        if e.kind == "reminder", let year = e.info["yearReview"] {
            content = ContentTarget(child: child, kind: "YearReview", galleryKind: year)
        } else {
            // Ekstra oplysning til skærmen: billedseriens type, milepælens nøgle eller interviewets alder.
            let extra: String
            switch e.kind {
            case "Milestone": extra = e.recordId.map { $0.replacingOccurrences(of: "ms_\(childId)_", with: "") } ?? ""
            case "Interview": extra = e.info["age"] ?? ""
            default: extra = e.info["galleryKind"] ?? ""
            }
            content = ContentTarget(child: child, kind: e.kind == "reminder" ? "Child" : e.kind, galleryKind: extra)
        }
    }
    /// iOS tegner fanebjælken første gang med sine egne sorte ikoner. Tælleren tvinger en ny
    /// tegning af fanerne lige efter opstart, så de får appens farver med det samme.
    @State private var tabRedraw = 0
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

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
        // Tryk på ugens spørgsmål: åbn dagbogen for barnet med spørgsmålet som overskrift.
        .sheet(item: $prompt) { target in
            AddDiaryView(childId: target.child.id, initialText: target.text + "\n\n")
        }
        .onReceive(NotificationCenter.default.publisher(for: .openDiaryPrompt)) { _ in Task { await openPendingPrompt() } }
        .task { await openPendingPrompt() }
        // Tryk på en notifikation (fra klokken eller fra låseskærmen): åbn det, den handler om.
        .sheet(item: $content) { target in
            NavigationStack {
                contentView(target)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Luk") { content = nil } }
                    }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openNotificationTarget)) { note in
            // Fra klokken (appen er aktiv). Fra låseskærmen er appen endnu ikke aktiv, og arket kan ikke
            // vises — så venter vi på scenePhase herunder.
            guard scenePhase == .active, let e = note.object as? NotificationLogEntry else { return }
            DeepLink.pendingEntry = nil
            Task { await open(e) }
        }
        .task { await openPendingEntry() }
        // Appen blev åbnet fra en notifikation (låseskærm/notifikationscenter): navigér, når vinduet er klar.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await openPendingEntry()
                await openPendingInterview()
                await openPendingPrompt()
            }
        }
        .task {
            // To gentegninger: én så snart første billede er vist, og én lidt senere, hvis glas-tabbaren var sen.
            for ms in [50, 600] {
                try? await Task.sleep(for: .milliseconds(ms))
                tabRedraw += 1
            }
        }
    }

    struct InterviewTarget: Identifiable {
        let child: Child
        let age: Int
        var id: String { "\(child.id)_\(age)" }
    }

    struct PromptTarget: Identifiable {
        let child: Child
        let text: String
        var id: String { child.id + text }
    }

    private func openPendingEntry() async {
        guard let e = DeepLink.pendingEntry else { return }
        DeepLink.pendingEntry = nil
        await open(e)
    }

    private func openPendingPrompt() async {
        guard let link = DeepLink.pendingPrompt, let familyId = state.familyId else { return }
        DeepLink.pendingPrompt = nil
        guard let child = (try? await state.store.children(familyId: familyId))?.first(where: { $0.id == link.childId }) else { return }
        prompt = PromptTarget(child: child, text: link.text)
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
        _ = tabRedraw   // fanen tegnes igen, når tælleren ændrer sig
        _ = colorScheme // … og når der skiftes mellem lyst og mørkt (ikonerne er færdigfarvede billeder)
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: selected ? .semibold : .regular)
        let image = (UIImage(systemName: symbol, withConfiguration: config) ?? UIImage())
            .withTintColor(UIColor(color), renderingMode: .alwaysOriginal)
        return Label {
            Text(title).foregroundStyle(color)
        } icon: {
            Image(uiImage: image).renderingMode(.original)
        }
        // Fanebjælken bruger ellers de udfyldte (sorte) ikoner ved opstart.
        .environment(\.symbolVariants, .none)
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
