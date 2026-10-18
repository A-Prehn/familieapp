import SwiftUI

// Familie-fanen: oversigten over børnene. Fælles indhold ligger i FamilyView (Fælles-fanen).
struct ChildrenView: View {
    @EnvironmentObject var state: AppState
    @State private var children: [Child] = []
    @State private var sharedChildren: [Child] = []
    @State private var family: Family?
    @State private var showNewChild = false
    @State private var paywall: PaywallReason?

    /// Gratis-versionen har plads til ét barn — barn nr. 2 kræver Premium.
    private func addChild() {
        if !state.isPremium && children.count >= AppState.freeChildLimit { paywall = .child } else { showNewChild = true }
    }

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                SectionLabel("Vores børn")
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(children.enumerated()), id: \.element.id) { i, child in
                        NavigationLink(value: child) { ChildCard(child: child) }
                            .buttonStyle(.plain)
                            .softAppear(index: i)
                    }
                    if state.canEdit {
                        Button { addChild() } label: { AddChildCard() }
                            .buttonStyle(.plain)
                    }
                }
                // Børn, der er delt med dig fra en anden familie (fx dit barn hos den anden forælder).
                if !sharedChildren.isEmpty {
                    SectionLabel("Delt med dig").padding(.top, 8)
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(Array(sharedChildren.enumerated()), id: \.element.id) { i, child in
                            NavigationLink(value: child) { ChildCard(child: child) }
                                .buttonStyle(.plain)
                                .softAppear(index: i)
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(family?.name ?? "Børn")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Child.self) { ChildDetailView(child: $0) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if state.canEdit { Button { addChild() } label: { Image(systemName: "plus") } }
            }
        }
        .sheet(item: $paywall) { PaywallView(reason: $0) }
        .sheet(isPresented: $showNewChild, onDismiss: { Task { await load() } }) {
            NewChildView()
        }
        .refreshable { await load() }
        .task { await load() }
        .reloadOnStoreChange { await load() }
    }

    private struct Cached: Codable { var family: Family?; var children: [Child] }

    private func load() async {
        guard let familyId = state.familyId else { return }
        let cacheKey = "children_\(familyId)"
        if children.isEmpty, let cached = ScreenCache.load(Cached.self, key: cacheKey) {
            family = cached.family
            children = cached.children
            ChildPalette.update(children)
        }
        // Børnene først — det er dem skærmen handler om; familienavnet bagefter.
        guard let loaded = try? await state.store.children(familyId: familyId) else { return }
        children = loaded
        ChildPalette.update(children)
        Task { await Reminders.schedule(children: loaded) }
        if let fams = try? await state.store.families(for: state.user?.id ?? "") {
            family = fams.first { $0.id == familyId }
        }
        ScreenCache.save(Cached(family: family, children: children), key: cacheKey)
        // Delte børn hører ikke til familien, så de vises ikke dobbelt.
        let own = Set(children.map(\.id))
        sharedChildren = ((try? await state.store.sharedChildren()) ?? []).filter { !own.contains($0.id) }
    }
}
