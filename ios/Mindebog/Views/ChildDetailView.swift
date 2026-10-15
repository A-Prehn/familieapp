import SwiftUI

struct ChildDetailView: View {
    @EnvironmentObject var state: AppState
    @State private var child: Child
    @State private var editing = false

    init(child: Child) {
        _child = State(initialValue: child)
    }

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header

                NavigationLink { HighlightsView(child: child) } label: {
                    tile("Højdepunkter", "star", Theme.rose, wide: true)
                }
                .buttonStyle(.plain)

                LazyVGrid(columns: columns, spacing: 10) {
                    NavigationLink { DiaryView(child: child) } label: {
                        // Blød bindestreg: lange sammensatte ord deles pænt ("Svangerskabs-/dagbog").
                        tile(child.onTheWay ? "Svangerskabs\u{00AD}dagbog" : "Dagbog", "book", Theme.neutralDark)
                    }
                    NavigationLink { GalleryView(child: child, kind: .belly) } label: {
                        tile("Maven måned for måned", "figure.and.child.holdinghands", Theme.neutralDark)
                    }
                    NavigationLink { GalleryView(child: child, kind: .monthly) } label: {
                        tile("Måned for måned", "photo.on.rectangle", Theme.tint)
                    }
                    NavigationLink { AboutMeView(child: child) } label: {
                        tile("Om dig", "message", Theme.rose)
                    }
                    NavigationLink { MilestonesView(child: child) } label: {
                        tile("Milepæle", "flag", Theme.green)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(child.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Redigér") { editing = true }
            }
        }
        .sheet(isPresented: $editing) {
            NewChildView(editing: child) { updated in child = updated }
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            HStack(spacing: 16) {
                ChildAvatar(child: child, size: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text(child.name).font(.serifTitle(22))
                    Text(subtitle).font(.subheadline).foregroundStyle(Theme.muted)
                }
                Spacer()
            }
            if child.onTheWay, let due = child.dueDate {
                let days = max(0, Calendar.current.dateComponents([.day], from: Date(), to: due).day ?? 0)
                HStack(spacing: 20) {
                    Text("\(days)").font(.system(size: 44, weight: .medium, design: .serif))
                        .foregroundStyle(Theme.neutralDark)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("dage til termin").font(.footnote).foregroundStyle(Theme.neutral)
                        Text("Termin: \(Fmt.long(due))").font(.footnote).foregroundStyle(Theme.neutralDark)
                    }
                    Spacer()
                }
                .padding(16)
                .background(Theme.bgDark)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(16)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.sep))
    }

    private var subtitle: String {
        if child.onTheWay { return "På vej" }
        guard let birth = child.birthDate else { return "" }
        let months = Calendar.current.dateComponents([.month], from: birth, to: Date()).month ?? 0
        return months < 24 ? "\(max(0, months)) mdr." : "\(months / 12) år"
    }

    private func tile(_ title: String, _ symbol: String, _ color: Color, wide: Bool = false) -> some View {
        HStack(spacing: 12) {
            Circle().fill(color.opacity(0.15)).frame(width: 38, height: 38)
                .overlay(Image(systemName: symbol).font(.system(size: 17)).foregroundStyle(color))
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.leading)
            if wide { Spacer() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.sep))
    }
}
