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
    @State private var pendingAdd: QuickAdd?
    @State private var showAddEvent = false
    @State private var lightbox: LightboxState?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HeroView().padding(.vertical, 8)

                Text(greeting)
                    .font(.serifTitle(22))
                    .foregroundStyle(Theme.text)

                quoteCard

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
            let first = item.children[0]
            let others = Array(item.children.dropFirst())
            let names = item.children.map(\.name)
            switch item.kind {
            case .highlight: AddHighlightView(childId: first.id, alsoFor: others, forNames: names)
            case .diary: AddDiaryView(childId: first.id, alsoFor: others, forNames: names)
            }
        }
        // Begivenhed hører til hele familien (Fælles) — intet barnevalg.
        .sheet(isPresented: $showAddEvent, onDismiss: { Task { await load() } }) {
            AddEventView(familyId: state.familyId ?? "")
        }
        // Flere børn: vælg ét eller flere — samme indlæg gemmes for hvert valgt barn.
        .sheet(item: $chooseChildFor, onDismiss: {
            if let pending = pendingAdd { quickAdd = pending; pendingAdd = nil }
        }) { kind in
            ChooseChildrenView(children: children) { selected in
                pendingAdd = QuickAdd(kind: kind, children: selected)
                chooseChildFor = nil
            }
            .presentationDetents([.medium, .large])
        }
        .fullScreenCover(item: $lightbox) { LightboxView(state: $0) }
        .refreshable { await load() }
        .task { await load() }
    }

    // MARK: Sektioner
    private var quoteCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "quote.opening")
                .font(.system(size: 16))
                .foregroundStyle(Theme.rose.opacity(0.7))
                .padding(.top, 2)
            Text(DailyQuotes.today())
                .font(.system(size: 16, design: .serif).italic())
                .foregroundStyle(Theme.neutralDark)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Theme.bgDark)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityLabel("Dagens citat: \(DailyQuotes.today())")
    }

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
            quickButton("Begivenhed", "calendar.badge.plus", Theme.tint, nil)
        }
    }

    /// kind = nil → ny begivenhed under Fælles; ellers et indlæg for ét eller flere børn.
    private func quickButton(_ title: String, _ symbol: String, _ color: Color, _ kind: QuickAdd.Kind?) -> some View {
        Button {
            guard let kind else { showAddEvent = true; return }
            if children.count == 1, let only = children.first {
                quickAdd = QuickAdd(kind: kind, children: [only])
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

    private struct Cached: Codable {
        var children: [Child]
        var recent: [RecentMemory]
        var onThisDay: [RecentMemory]
        var day: String   // "På denne dag" gælder kun samme dato
    }

    private func load() async {
        guard let familyId = state.familyId else { return }
        let cacheKey = "home_\(familyId)"
        let todayKey = Fmt.iso(Date())
        if children.isEmpty, let cached = ScreenCache.load(Cached.self, key: cacheKey) {
            children = cached.children
            ChildPalette.update(children)
            recent = cached.recent
            onThisDay = cached.day == todayKey ? cached.onThisDay : []
        }

        let store = state.store
        guard let loadedKids = try? await store.children(familyId: familyId) else { return }
        children = loadedKids
        ChildPalette.update(children)
        Task { await Reminders.schedule(children: loadedKids) }
        defer {
            ScreenCache.save(Cached(children: children, recent: recent, onThisDay: onThisDay, day: todayKey), key: cacheKey)
        }

        // 1) Let oversigt over alle minder — kun tekst og datoer, ingen billeder.
        guard let summaries = try? await store.memorySummaries(familyId: familyId) else { return }
        let names = Dictionary(uniqueKeysWithValues: loadedKids.map { ($0.id, $0) })

        func memory(_ s: MemorySummary) -> RecentMemory? {
            switch s.kind {
            case .highlight, .diary:
                guard let id = s.childId, let child = names[id] else { return nil }   // barn slettet
                let isHighlight = s.kind == .highlight
                return RecentMemory(id: (isHighlight ? "hl_" : "dy_") + s.id, summary: s, childName: child.name,
                                    kind: isHighlight ? "Højdepunkt" : (child.onTheWay ? "Svangerskabsdagbog" : "Dagbog"),
                                    symbol: isHighlight ? "star" : "book",
                                    date: s.date, sortDate: s.date ?? s.createdAt, text: s.text, photo: nil)
            case .event:
                return RecentMemory(id: "ev_" + s.id, summary: s, childName: "Fælles", kind: "Begivenhed", symbol: "calendar",
                                    date: s.date, sortDate: s.date ?? .distantPast, text: s.text, photo: nil)
            case .vacation:
                return RecentMemory(id: "va_" + s.id, summary: s, childName: "Fælles", kind: "Ferie", symbol: "beach.umbrella",
                                    date: s.date, sortDate: s.date ?? .distantPast, text: s.text, photo: nil)
            }
        }
        let all = summaries.compactMap(memory)

        // Seneste minder: kun børnenes (højdepunkter + dagbog), de 5 nyeste.
        var newRecent = Array(all.filter { $0.summary?.childId != nil }
            .sorted { $0.sortDate > $1.sortDate }.prefix(5))

        // På denne dag: samme dag og måned i et tidligere år — også fælles minder.
        let cal = Calendar.current
        let today = cal.dateComponents([.year, .month, .day], from: Date())
        var newOnThisDay = all.filter { m in
            guard let date = m.date else { return false }
            let c = cal.dateComponents([.year, .month, .day], from: date)
            return c.month == today.month && c.day == today.day && (c.year ?? 0) < (today.year ?? 0)
        }
        .sorted { $0.sortDate > $1.sortDate }

        // 2) Billeder kun til de viste minder; genbrug dem vi allerede har fra sidst.
        var known: [String: Data] = [:]
        for m in recent + onThisDay { if let p = m.photo { known[m.id] = p } }
        func withPhotos(_ list: [RecentMemory]) async -> [RecentMemory] {
            var out = list
            for i in out.indices {
                if let cached = known[out[i].id] {
                    out[i].photo = cached
                } else if let s = out[i].summary {
                    out[i].photo = try? await store.coverPhoto(familyId: familyId, memory: s)
                    if let p = out[i].photo { known[out[i].id] = p }
                }
            }
            return out
        }
        newRecent = await withPhotos(newRecent)
        newOnThisDay = await withPhotos(newOnThisDay)
        recent = newRecent
        onThisDay = newOnThisDay
    }

    private func yearsAgo(_ date: Date?) -> String {
        guard let date else { return "" }
        let years = Calendar.current.component(.year, from: Date()) - Calendar.current.component(.year, from: date)
        return years == 1 ? "For 1 år siden" : "For \(years) år siden"
    }
}

// MARK: - Hjælpetyper

struct RecentMemory: Identifiable, Codable {
    let id: String
    /// Oversigten bag mindet — bruges til at hente billedet, når det skal vises.
    var summary: MemorySummary? = nil
    let childName: String
    let kind: String
    let symbol: String
    let date: Date?
    let sortDate: Date
    let text: String
    var photo: Data?
}

struct QuickAdd: Identifiable {
    enum Kind: String, Identifiable {
        case highlight, diary
        var id: String { rawValue }
        var title: String {
            switch self {
            case .highlight: return "Højdepunkt"
            case .diary: return "Dagbog"
            }
        }
    }
    let kind: Kind
    let children: [Child]   // mindst ét
    var id: String { "\(kind)_" + children.map(\.id).joined(separator: "_") }
}

/// "Hvem gælder det?" — vælg ét eller flere børn til hurtig-tilføj.
struct ChooseChildrenView: View {
    let children: [Child]
    let onContinue: ([Child]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(children) { child in
                        Button {
                            if selected.contains(child.id) { selected.remove(child.id) } else { selected.insert(child.id) }
                        } label: {
                            HStack(spacing: 12) {
                                ChildAvatar(child: child, size: 36)
                                Text(child.name).foregroundStyle(Theme.text)
                                Spacer()
                                Image(systemName: selected.contains(child.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(child.id) ? Theme.tint : Theme.muted)
                                    .font(.title3)
                            }
                        }
                    }
                } footer: {
                    Text("Vælger du flere, gemmes det samme for hvert barn.")
                }
                Section {
                    Button(selected.count == children.count ? "Fravælg alle" : "Vælg alle") {
                        selected = selected.count == children.count ? [] : Set(children.map(\.id))
                    }
                }
            }
            .navigationTitle("Hvem gælder det?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annullér") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fortsæt") {
                        onContinue(children.filter { selected.contains($0.id) })   // samme rækkefølge som listen
                    }
                    .disabled(selected.isEmpty)
                }
            }
        }
    }
}
