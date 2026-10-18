import SwiftUI

// Hjem: hilsen, hurtig-tilføj, "På denne dag" (minder fra samme dato tidligere år)
// og seneste minder. Børnene ligger under Familie-fanen.
struct HomeView: View {
    @EnvironmentObject var state: AppState
    @Namespace private var zoomNS   // zoom-overgang til fuld skærm (iOS 18)
    @State private var children: [Child] = []
    @State private var onThisDay: [RecentMemory] = []
    @State private var recent: [RecentMemory] = []
    @State private var quickAdd: QuickAdd?
    @State private var chooseChildFor: HomeAction?
    @State private var pendingAdd: QuickAdd?
    @State private var familyAdd: HomeAction?
    @State private var showActionsEditor = false
    @State private var noChildMessage: String?
    @AppStorage(HomeAction.storageKey) private var homeActionsRaw = ""
    @State private var lightbox: LightboxState?
    @State private var loading = true
    @State private var refreshing = false   // viser "Henter nyeste", mens listen fra sidst opdateres
    @State private var loadGeneration = 0
    @State private var lastLoad: Date?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HeroView().padding(.vertical, 8)

                // Hilsen og citat toner ind med et lille "åndedrag" efter hinanden.
                Text(greeting)
                    .font(.serifTitle(22))
                    .foregroundStyle(Theme.text)
                    .softAppear(index: 1)

                quoteCard.softAppear(index: 2)

                if children.isEmpty {
                    emptyState
                } else {
                    if state.canEdit { quickAddSection.softAppear(index: 3) }
                    if !onThisDay.isEmpty {
                        memorySection("På denne dag", onThisDay) { m in
                            "\(yearsAgo(m.date)) · \(m.childName) · \(m.kind)"
                        }
                        .softAppear(index: 5)
                    }
                    if !recent.isEmpty {
                        memorySection("Seneste i familien", recent, refreshing: refreshing) { m in "\(whenText(m)) · \(m.childName) · \(m.kind)" }
                            .softAppear(index: 7)
                    } else if loading {
                        // Skimmer, mens iCloud henter første gang.
                        VStack(spacing: 10) {
                            SectionLabel("Seneste i familien")
                            ForEach(0..<3, id: \.self) { _ in ShimmerPlaceholder(height: 88) }
                        }
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
            case .monthly: AddGalleryItemView(childId: first.id, alsoFor: others, forNames: names, kind: .monthly)
            case .belly: AddGalleryItemView(childId: first.id, kind: .belly)
            case .drawing: AddGalleryItemView(childId: first.id, kind: .drawings, defaultCaption: ChildAge.short(first))
            case .voice: RecordVoiceView(child: first)
            default: EmptyView()
            }
        }
        // Familie-handlinger (Fælles) — intet barnevalg.
        .sheet(item: $familyAdd, onDismiss: { Task { await load() } }) { action in
            let familyId = state.familyId ?? ""
            switch action {
            case .event: AddEventView(familyId: familyId, children: children)
            case .vacation: AddVacationView(familyId: familyId)
            case .birthday: AddBirthdayView(familyId: familyId)
            case .tradition: TraditionEditView(familyId: familyId)
            case .memory: MemoryEditView(familyId: familyId, children: children)
            default: EmptyView()
            }
        }
        .sheet(isPresented: $showActionsEditor) { HomeActionsEditor() }
        .alert(noChildMessage ?? "", isPresented: Binding(get: { noChildMessage != nil },
                                                           set: { if !$0 { noChildMessage = nil } })) {
            Button("OK", role: .cancel) {}
        }
        // Flere børn: vælg ét eller flere (eller ét, hvis handlingen kun gælder ét barn).
        .sheet(item: $chooseChildFor, onDismiss: {
            if let pending = pendingAdd { quickAdd = pending; pendingAdd = nil }
        }) { action in
            ChooseChildrenView(children: children.filter { action.fits($0) }) { selected in
                let picked = action.allowsSeveral ? selected : Array(selected.prefix(1))
                if !picked.isEmpty { pendingAdd = QuickAdd(kind: action, children: picked) }
                chooseChildFor = nil
            }
            .presentationDetents([.medium, .large])
        }
        .fullScreenCover(item: $lightbox) { LightboxView(state: $0).zoomTarget(id: $0.sourceId, in: zoomNS) }
        .refreshable { await load() }
        .task { await loadIfStale() }
        .reloadOnStoreChange { await load() }
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
        VStack(spacing: 8) {
            HStack {
                SectionLabel("Hurtigt")
                Button { showActionsEditor = true } label: {
                    Text("Redigér").font(.caption.weight(.semibold))
                }
            }
            HStack(spacing: 10) {
                ForEach(HomeAction.load(homeActionsRaw)) { quickButton($0) }
            }
        }
    }

    private func quickButton(_ action: HomeAction) -> some View {
        Button { start(action) } label: {
            VStack(spacing: 6) {
                Image(systemName: action.symbol).font(.system(size: 18)).foregroundStyle(action.color)
                Text(action.title).font(.caption).foregroundStyle(Theme.text)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.sep))
        }
        .buttonStyle(.plain)
        // Hold fingeren på en knap for at redigere, som på iPhonens hjemmeskærm.
        .contextMenu { Button { showActionsEditor = true } label: { Label("Redigér hurtigknapper", systemImage: "slider.horizontal.3") } }
    }

    /// Familie-handlinger åbner deres formular direkte; barne-handlinger spørger om barn, hvis der er flere.
    private func start(_ action: HomeAction) {
        guard action.isForChild else { familyAdd = action; return }
        let candidates = children.filter { action.fits($0) }
        if candidates.isEmpty {
            noChildMessage = action == .belly ? "Der er ikke noget barn på vej." : "Tilføj et barn under Familie først."
        } else if candidates.count == 1 {
            quickAdd = QuickAdd(kind: action, children: candidates)
        } else {
            chooseChildFor = action
        }
    }

    private func memorySection(_ title: String, _ items: [RecentMemory], refreshing: Bool = false,
                               meta: @escaping (RecentMemory) -> String) -> some View {
        VStack(spacing: 10) {
            SectionLabel(title)
                .overlay(alignment: .trailing) {
                    // Viser, at listen fra sidst er ved at blive opdateret fra iCloud.
                    if refreshing {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text("Henter nyeste").font(.caption2).foregroundStyle(Theme.muted)
                        }
                        .transition(.opacity)
                    }
                }
            ForEach(items) { memory in
                HStack(alignment: .top, spacing: 12) {
                    if let photo = memory.photo {
                        DataImage(data: photo)
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .zoomSource(id: memory.id, in: zoomNS)
                            .onTapGesture { lightbox = LightboxState(photos: [photo], sourceId: memory.id) }
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
                .opacity(refreshing ? 0.55 : 1)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: refreshing)
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

    /// Ved fanebladsskift: hent kun igen, hvis det er et stykke tid siden.
    private func loadIfStale() async {
        if let last = lastLoad, Date().timeIntervalSince(last) < 30 { return }
        await load()
    }

    private func load() async {
        // Kun den nyeste hentning må opdatere skærmen — en ældre, der bliver færdig sidst,
        // ville ellers vise gamle opslag igen.
        loadGeneration += 1
        let generation = loadGeneration
        func isCurrent() -> Bool { generation == loadGeneration }
        lastLoad = Date()
        defer { if isCurrent() { loading = false; refreshing = false } }
        guard let familyId = state.familyId else { return }
        let cacheKey = "home_\(familyId)"
        refreshing = true
        let todayKey = Fmt.iso(Date())
        if children.isEmpty, let cached = ScreenCache.load(Cached.self, key: cacheKey) {
            children = cached.children
            ChildPalette.update(children)
            recent = cached.recent
            onThisDay = cached.day == todayKey ? cached.onThisDay : []
        }

        let store = state.store
        // Børn og minde-oversigten hentes samtidig.
        async let kidsTask = store.children(familyId: familyId)
        async let summariesTask = store.memorySummaries(familyId: familyId)
        guard let loadedKids = try? await kidsTask, isCurrent() else { return }
        children = loadedKids
        ChildPalette.update(children)
        Task { await Reminders.schedule(children: loadedKids) }
        defer {
            if isCurrent() { ScreenCache.save(Cached(children: children, recent: recent, onThisDay: onThisDay, day: todayKey), key: cacheKey) }
        }

        // 1) Let oversigt over alle minder — kun tekst og datoer, ingen billeder.
        guard let summaries = try? await summariesTask, isCurrent() else { return }
        let names = Dictionary(uniqueKeysWithValues: loadedKids.map { ($0.id, $0) })
        // "På denne dag"-notifikationer for de næste uger.
        let childNames = loadedKids.reduce(into: [String: String]()) { $0[$1.id] = $1.name }
        Task { await OnThisDay.schedule(summaries: summaries, childNames: childNames) }

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
                return RecentMemory(id: "ev_" + s.id, summary: s, childName: "Familie", kind: "Begivenhed", symbol: "calendar",
                                    date: s.date, sortDate: s.date ?? .distantPast, text: s.text, photo: nil)
            case .vacation:
                return RecentMemory(id: "va_" + s.id, summary: s, childName: "Familie", kind: "Rejse", symbol: "beach.umbrella",
                                    date: s.date, sortDate: s.date ?? .distantPast, text: s.text, photo: nil)
            case .photo:
                guard let id = s.childId, let child = names[id] else { return nil }
                let (kind, symbol): (String, String) = switch s.detail {
                case "belly": ("Mavebillede", "leaf")
                case "drawings": ("Tegning", "paintpalette")
                case "birthday": ("Fødselsdag", "gift")
                default: ("Månedsbillede", "photo.on.rectangle")
                }
                return RecentMemory(id: "ph_" + s.id, summary: s, childName: child.name, kind: kind, symbol: symbol,
                                    date: s.date, sortDate: s.createdAt, text: s.text, photo: nil)
            case .interview:
                guard let id = s.childId, let child = names[id] else { return nil }
                return RecentMemory(id: "iv_" + s.id, summary: s, childName: child.name, kind: "Årligt interview",
                                    symbol: "bubble.left.and.text.bubble.right",
                                    date: s.date, sortDate: s.createdAt, text: s.text, photo: nil)
            case .tradition:
                return RecentMemory(id: "tr_" + s.id, summary: s, childName: "Familie", kind: "Tradition", symbol: "sparkles",
                                    date: nil, sortDate: s.createdAt, text: s.text, photo: nil)
            case .letter:
                guard let id = s.childId, let child = names[id] else { return nil }
                return RecentMemory(id: "le_" + s.id, summary: s, childName: child.name, kind: "Brev", symbol: "envelope",
                                    date: s.date, sortDate: s.createdAt, text: s.text, photo: nil)
            case .memory:
                return RecentMemory(id: "me_" + s.id, summary: s, childName: "Familie", kind: "Minde", symbol: "heart.text.square",
                                    date: s.date, sortDate: s.date ?? s.createdAt, text: s.text, photo: nil)
            }
        }
        let all = summaries.compactMap(memory)

        // Seneste i familien: alt, hvad der er lagt op eller ændret — det nyeste først.
        var newRecent = Array(all.sorted { changed($0) > changed($1) }.prefix(5))

        // På denne dag: samme dag og måned i et tidligere år — kun de klassiske minder.
        let classic: Set<MemorySummary.Kind> = [.highlight, .diary, .event, .vacation, .memory]
        let cal = Calendar.current
        let today = cal.dateComponents([.year, .month, .day], from: Date())
        var newOnThisDay = all.filter { classic.contains($0.summary?.kind ?? .highlight) }.filter { m in
            guard let date = m.date else { return false }
            let c = cal.dateComponents([.year, .month, .day], from: date)
            return c.month == today.month && c.day == today.day && (c.year ?? 0) < (today.year ?? 0)
        }
        .sorted { $0.sortDate > $1.sortDate }

        // 2) Billeder kun til de viste minder; genbrug dem vi allerede har fra sidst.
        var known: [String: Data] = [:]
        for m in recent + onThisDay { if let p = m.photo { known[m.id] = p } }
        // Vis den friske liste med det samme (med de billeder vi allerede har), så gamle opslag
        // fra hukommelsen ikke bliver stående, mens nye billeder hentes.
        func withKnownPhotos(_ list: [RecentMemory]) -> [RecentMemory] {
            list.map { var m = $0; if m.photo == nil { m.photo = known[m.id] }; return m }
        }
        withAnimation(.easeInOut(duration: 0.25)) {
            recent = withKnownPhotos(newRecent)
            onThisDay = withKnownPhotos(newOnThisDay)
            refreshing = false
        }
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
        guard isCurrent() else { return }
        recent = newRecent
        onThisDay = newOnThisDay

        // Widget og notifikationer: skriv det nyeste til App Group'en (i baggrunden).
        let familyName = (try? await store.families(for: state.user?.id ?? ""))?
            .first { $0.id == familyId }?.name ?? "Vores familie"
        Task { await WidgetSync.refresh(store: store, familyId: familyId, familyName: familyName) }
    }

    /// Hvornår noget sidst blev lagt op eller ændret (falder tilbage på oprettelsen).
    private func changed(_ m: RecentMemory) -> Date {
        guard let s = m.summary else { return m.sortDate }
        return max(s.modifiedAt, s.createdAt)
    }

    /// "I dag", "I går", "For 3 dage siden" — til "Seneste i familien".
    private func whenText(_ m: RecentMemory) -> String {
        let cal = Calendar.current
        let date = changed(m)
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: Date())).day ?? 0
        switch days {
        case ..<1: return "I dag"
        case 1: return "I går"
        case 2..<7: return "For \(days) dage siden"
        default: return Fmt.long(date)
        }
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
    let kind: HomeAction
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
                Group {
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
                }.listRowBackground(Theme.card)
            }
            .themedList()
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
