import SwiftUI

// Familie-fanen: oversigten over børnene. Fælles indhold ligger i FamilyView (Fælles-fanen).
struct ChildrenView: View {
    @EnvironmentObject var state: AppState
    @State private var children: [Child] = []
    @State private var family: Family?
    @State private var showNewChild = false

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                SectionLabel("Vores børn")
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(children) { child in
                        NavigationLink(value: child) { ChildCard(child: child) }
                            .buttonStyle(.plain)
                    }
                    Button { showNewChild = true } label: { AddChildCard() }
                        .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(family?.name ?? "Familie")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Child.self) { ChildDetailView(child: $0) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showNewChild = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showNewChild, onDismiss: { Task { await load() } }) {
            NewChildView()
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        guard let familyId = state.familyId else { return }
        family = try? await state.store.families(for: state.user?.id ?? "").first { $0.id == familyId }
        children = (try? await state.store.children(familyId: familyId)) ?? []
    }
}
