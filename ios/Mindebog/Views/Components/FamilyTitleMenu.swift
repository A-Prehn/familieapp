import SwiftUI

// Titlen øverst på Hjem, Børn og Familie. Er man med i flere familier (fx bedsteforældre med
// børnebørn to steder), bliver titlen en menu, og ét tryk skifter hele appen til den anden familie.
// Med kun én familie vises titlen bare som tekst.
struct FamilyTitleMenu: View {
    @EnvironmentObject var state: AppState
    /// Fast titel ("Hjem", "Familie") — ellers vises den valgte families navn.
    var title: String? = nil
    /// Vis kun, når der er flere familier at vælge imellem (Hjem har sin egen hilsen).
    var onlyWhenSeveral = false
    @State private var families: [Family] = []

    private var current: Family? { families.first { $0.id == state.familyId } }

    var body: some View {
        Group {
            if onlyWhenSeveral && families.count <= 1 {
                EmptyView()
            } else if families.count > 1 {
                Menu {
                    ForEach(families) { f in
                        Button {
                            state.switchFamily(f.id)
                            Haptics.light()
                        } label: {
                            if f.id == state.familyId { Label(f.name, systemImage: "checkmark") } else { Text(f.name) }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(label).font(.headline).foregroundStyle(Theme.text).lineLimit(1)
                        Image(systemName: "chevron.down").font(.caption2.weight(.bold)).foregroundStyle(Theme.muted)
                    }
                }
                .accessibilityLabel("Skift familie — nu \(current?.name ?? "")")
            } else {
                Text(label).font(.headline).foregroundStyle(Theme.text)
            }
        }
        .task(id: state.familyId) { await load() }
    }

    private var label: String {
        if let title { return title }
        return current?.name ?? "Børn"
    }

    private struct Cached: Codable { var families: [Family] }

    private func load() async {
        guard let userId = state.user?.id else { return }
        let key = "families_\(userId)"
        if families.isEmpty, let cached = ScreenCache.load(Cached.self, key: key) { families = cached.families }
        guard let fetched = try? await state.store.families(for: userId) else { return }
        families = fetched.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        ScreenCache.save(Cached(families: families), key: key)
    }
}
