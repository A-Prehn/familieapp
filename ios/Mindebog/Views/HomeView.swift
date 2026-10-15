import SwiftUI

struct HomeView: View {
    @EnvironmentObject var state: AppState
    @State private var children: [Child] = []
    @State private var family: Family?
    @State private var showNewChild = false

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HeroView()
                    .padding(.vertical, 8)

                Text("VORES BØRN")
                    .font(.caption2).tracking(1.4)
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 8).padding(.bottom, 12)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(children) { child in
                        NavigationLink(value: child) {
                            ChildCard(child: child)
                        }
                        .buttonStyle(.plain)
                    }
                    Button { showNewChild = true } label: {
                        AddCard()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(family?.name ?? "Hjem")
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

private struct ChildCard: View {
    let child: Child
    var body: some View {
        VStack(spacing: 10) {
            Circle()
                .fill(Theme.bgDark)
                .frame(width: 56, height: 56)
                .overlay(Image(systemName: "figure.child").foregroundStyle(Theme.neutralDark))
            Text(child.name).font(.serifTitle(16)).foregroundStyle(Theme.text)
            Text(subtitle).font(.caption).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 20)
        .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.sep))
    }

    private var subtitle: String {
        if child.onTheWay, let due = child.dueDate {
            let days = Calendar.current.dateComponents([.day], from: Date(), to: due).day ?? 0
            return days > 0 ? "\(days) dage til termin" : "Termin nået"
        }
        if let birth = child.birthDate {
            let months = Calendar.current.dateComponents([.month], from: birth, to: Date()).month ?? 0
            return months < 24 ? "\(max(0, months)) mdr." : "\(months / 12) år"
        }
        return "Ingen fødselsdato"
    }
}

private struct AddCard: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "plus").font(.system(size: 28, weight: .light))
            Text("Tilføj barn").font(.serifTitle(16))
        }
        .foregroundStyle(Theme.tint)
        .frame(maxWidth: .infinity).padding(.vertical, 20)
        .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.sep, style: StrokeStyle(lineWidth: 1, dash: [4])))
    }
}
