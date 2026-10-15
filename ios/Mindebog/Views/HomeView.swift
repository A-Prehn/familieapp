import SwiftUI

// Hjem: hilsen, hurtig-tilføj, "På denne dag" (minder fra samme dato tidligere år)
// og seneste minder. Børnene ligger under Familie-fanen.
struct HomeView: View {
    @EnvironmentObject var state: AppState
    @State private var children: [Child] = []
    @State private var onThisDay: [RecentMemory] = []
    @State private var recent: [RecentMemory] = []
    @State private var quickAdd: QuickAdd?
    @State private var chooseChildFor: QuickAdd.Kind?
    @State private var lightbox: LightboxState?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HeroView().padding(.vertical, 8)

                Text(greeting)
                    .font(.serifTitle(22))
                    .foregroundStyle(Theme.text)

                if children.isEmpty {
                    emptyState
                } else {
                    quickAddSection
                    if !onThisDay.isEmpty {
                        memorySection("På denne dag", onThisDay) { m in
                            "\(yearsAgo(m.date)) · \(m.childName) · \(m.kind)"
                        }
                    }
                    if !recent.isEmpty {
                        memorySection("Seneste minder", recent) { m in "\(m.childName) · \(m.kind)" }
                    }
                }
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Hjem")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Child.self) { ChildDetailView(child: $0) }
        .sheet(item: $quickAdd, onDismiss: { Task { await load() } }) { item in
            switch item.kind {
            case .highlight: AddHighlightView(childId: item.child.id)
            case .diary: AddDiaryView(childId: item.child.id)
            case .photo: AddGalleryItemView(childId: item.child.id, kind: item.child.onTheWay ? .belly : .monthly)
            }
        }
        .confirmationDialog("Hvilket barn?", isPresented: Binding(
            get: { chooseChildFor != nil }, set: { if !$0 { chooseChildFor = nil } }
        ), titleVisibility: .visible) {
            ForEach(children) { child in
                Button(child.name) {
                    if let kind = chooseChildFor { quickAdd = QuickAdd(kind: kind, child: child) }
                }
            }
        }
        .fullScreenCover(item: $lightbox) { LightboxView(state: $0) }
        .refreshable { await load() }
        .task { await load() }
    }

    // MARK: Sektioner
    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("Tilføj jeres første barn under Familie, så fylder vi forsiden med minder.")
                .font(.footnote).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(24)
        .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.sep))
    }

    private var quickAddSection: some View {
        HStack(spacing: 10) {
            quickButton("Højdepunkt", "star", Theme.rose, .highlight)
            quickButton("Dagbog", "book", Theme.neutralDark, .diary)
            quickButton("Foto", "camera", Theme.tint, .photo)
        }
    }

    private func quickButton(_ title: String, _ symbol: String, _ color: Color, _ kind: QuickAdd.Kind) -> some View {
        Button {
            if children.count == 1, let only = children.first {
                quickAdd = QuickAdd(kind: kind, child: only)
            } else {
                chooseChildFor = kind
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(color)
                Text(title).font(.caption).foregroundStyle(Theme.text)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.sep))
        }
        .buttonStyle(.plain)
    }

    private func memorySection(_ title: String, _ items: [RecentMemory],
                               meta: @escaping (RecentMemory) -> String) -> some View {
        VStack(spacing: 10) {
            SectionLabel(title)
            ForEach(items) { memory in
                HStack(alignment: .top, spacing: 12) {
                    if let photo = memory.photo {
                        DataImage(data: photo)
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .onTapGesture { lightbox = LightboxState(photos: [photo]) }
                    } else {
                        RoundedRectangle(cornerRadius: 8).fill(Theme.bgDark)
                            .frame(width: 64, height: 64)
                            .overlay(Image(systemName: memory.symbol).foregroundStyle(Theme.neutralDark))
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(meta(memory))
                            .font(.caption).foregroundStyle(Theme.muted)
                        Text(memory.text.isEmpty ? "Uden tekst" : memory.text)
                            .font(.footnote).foregroundStyle(Theme.text).lineLimit(2)
                        if let date = memory.date {
                            Text(Fmt.long(date)).font(.caption2).foregroundStyle(Theme.muted)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.sep))
            }
        }
    }

    // MARK: Data
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let word: String
        switch hour {
        case 5..<10: word = "Godmorgen"
        case 10..<18: word = "Hej"
        default: word = "Godaften"
        }
        let name = state.user?.name.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty || name == "Forælder" ? word : "\(word), \(name)"
    }

    private func load() async {
        guard let familyId = state.familyId else { return }
        let store = state.store
        let loadedKids = (try? await store.children(familyId: familyId)) ?? []
        children = loadedKids

        // Børnenes minder (højdepunkter + dagbog).
        var memories: [RecentMemory] = []
        for child in loadedKids {
            for h in (try? await store.highlights(childId: child.id)) ?? [] {
                memories.append(RecentMemory(id: "hl_\(h.id)", childName: child.name, kind: "Højdepunkt", symbol: "star",
                                             date: h.date, sortDate: h.date ?? h.createdAt, text: h.text, photo: h.photos.first))
            }
            for d in (try? await store.diary(childId: child.id)) ?? [] {
                memories.append(RecentMemory(id: "dy_\(d.id)", childName: child.name, kind: child.onTheWay ? "Svangerskabsdagbog" : "Dagbog",
                                             symbol: "book", date: d.date, sortDate: d.date ?? d.createdAt, text: d.text, photo: d.photo))
            }
        }
        recent = Array(memories.sorted { $0.sortDate > $1.sortDate }.prefix(5))

        // Fælles minder tæller også med i "På denne dag".
        var all = memories
        for e in (try? await store.events(familyId: familyId)) ?? [] {
            all.append(RecentMemory(id: "ev_\(e.id)", childName: "Fælles", kind: "Begivenhed", symbol: "calendar",
                                    date: e.date, sortDate: e.date ?? .distantPast, text: e.title, photo: e.photo))
        }
        for v in (try? await store.vacations(familyId: familyId)) ?? [] {
            all.append(RecentMemory(id: "va_\(v.id)", childName: "Fælles", kind: "Ferie", symbol: "beach.umbrella",
                                    date: v.startDate, sortDate: v.startDate ?? .distantPast, text: v.title, photo: v.photo))
        }
        let cal = Calendar.current
        let now = Date()
        let today = cal.dateComponents([.year, .month, .day], from: now)
        onThisDay = all.filter { m in
            guard let date = m.date else { return false }
            let c = cal.dateComponents([.year, .month, .day], from: date)
            return c.month == today.month && c.day == today.day && (c.year ?? 0) < (today.year ?? 0)
        }
        .sorted { $0.sortDate > $1.sortDate }
    }

    private func yearsAgo(_ date: Date?) -> String {
        guard let date else { return "" }
        let years = Calendar.current.component(.year, from: Date()) - Calendar.current.component(.year, from: date)
        return years == 1 ? "For 1 år siden" : "For \(years) år siden"
    }
}

// MARK: - Hjælpetyper

struct RecentMemory: Identifiable {
    let id: String
    let childName: String
    let kind: String
    let symbol: String
    let date: Date?
    let sortDate: Date
    let text: String
    let photo: Data?
}

struct QuickAdd: Identifiable {
    enum Kind { case highlight, diary, photo }
    let kind: Kind
    let child: Child
    var id: String { "\(kind)_\(child.id)" }
}
