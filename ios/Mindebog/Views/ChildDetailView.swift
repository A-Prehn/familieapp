import SwiftUI

struct ChildDetailView: View {
    @EnvironmentObject var state: AppState
    let child: Child
    @State private var highlightCount = 0

    private struct Section: Identifiable {
        let id = UUID()
        let title: String
        let symbol: String
        let color: Color
    }

    private var sections: [Section] {
        [
            Section(title: "Højdepunkter", symbol: "star", color: Theme.rose),
            Section(title: child.onTheWay ? "Svangerskabsdagbog" : "Dagbog", symbol: "book", color: Theme.neutralDark),
            Section(title: "Maven måned for måned", symbol: "figure.child", color: Theme.neutralDark),
            Section(title: "Måned for måned", symbol: "photo.on.rectangle", color: Theme.tint),
            Section(title: "Om dig", symbol: "message", color: Theme.rose),
            Section(title: "Milepæle", symbol: "flag", color: Theme.green)
        ]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                NavigationLink(value: child.id) {
                    sectionRow(sections[0], subtitle: "\(highlightCount) højdepunkter", wide: true)
                }
                .buttonStyle(.plain)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(sections.dropFirst()) { s in
                        sectionRow(s, subtitle: nil, wide: false)
                    }
                }
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(child.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: String.self) { _ in
            HighlightsView(child: child)
        }
        .task {
            highlightCount = ((try? await state.store.highlights(childId: child.id)) ?? []).count
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Circle().fill(Theme.bgDark).frame(width: 64, height: 64)
                .overlay(Image(systemName: "figure.child").font(.title2).foregroundStyle(Theme.neutralDark))
            VStack(alignment: .leading, spacing: 2) {
                Text(child.name).font(.serifTitle(22))
                Text(child.onTheWay ? "På vej" : "").font(.subheadline).foregroundStyle(Theme.muted)
            }
            Spacer()
        }
        .padding(16)
        .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.sep))
    }

    private func sectionRow(_ s: Section, subtitle: String?, wide: Bool) -> some View {
        HStack(spacing: 12) {
            Circle().fill(s.color.opacity(0.15)).frame(width: 38, height: 38)
                .overlay(Image(systemName: s.symbol).font(.system(size: 17)).foregroundStyle(s.color))
            VStack(alignment: .leading, spacing: 2) {
                Text(s.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(Theme.muted) }
            }
            if wide { Spacer() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.sep))
    }
}
