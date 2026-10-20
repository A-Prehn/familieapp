import SwiftUI

// Søg i alt: højdepunkter, dagbog, billedtekster, minder, begivenheder, rejser, traditioner,
// opskrifter, breve (ikke forseglede), interviewsvar, "Om mig" og milepæle.
// Søgningen kører i de lette oversigter (kun tekst), så den er hurtig; billeder hentes kun
// til de resultater, der vises. Et tryk åbner opslaget samme vej som en notifikation.
struct SearchView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var items: [SearchItem] = []
    @State private var children: [Child] = []
    @State private var filter: String? = nil        // barnets id eller "family"
    @State private var loading = true
    @AppStorage("mindebog.recentSearches") private var recentRaw = ""

    var body: some View {
        NavigationStack {
            List {
                Group {
                    if query.trimmingCharacters(in: .whitespaces).isEmpty {
                        start
                    } else if results.isEmpty {
                        if loading {
                            HStack { ProgressView(); Text("Søger…").foregroundStyle(Theme.muted) }
                        } else {
                            ContentUnavailableView.search(text: query)
                        }
                    } else {
                        ForEach(grouped, id: \.year) { group in
                            Section(group.year.map { "\($0) · \(group.items.count) \(group.items.count == 1 ? "resultat" : "resultater")" } ?? "Uden dato") {
                                ForEach(group.items) { item in
                                    Button { open(item) } label: { SearchRow(item: item, terms: terms) }
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .listRowBackground(Theme.card)
            }
            .themedList()
            .safeAreaInset(edge: .top) { if children.count > 0 { filters } }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Søg i minder, steder, milepæle …")
            .onSubmit(of: .search) { remember(query) }
            .navigationTitle("Søg")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Luk") { dismiss() } } }
            .task { await load() }
        }
    }

    // MARK: Start (før man skriver)
    @ViewBuilder private var start: some View {
        let recent = recentRaw.split(separator: "\n").map(String.init)
        if !recent.isEmpty {
            Section("Seneste søgninger") {
                ForEach(recent, id: \.self) { r in
                    Button { query = r } label: { Label(r, systemImage: "clock.arrow.circlepath") }
                }
            }
        }
        Section("Forslag") {
            ForEach(["første", "jul", "fødselsdag", "strand"], id: \.self) { s in
                Button { query = s } label: { Label(s, systemImage: "magnifyingglass") }
            }
        }
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("Alle", nil)
                ForEach(children) { chip($0.name, $0.id) }
                chip("Familie", "family")
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
        }
        .background(Theme.bg)
    }

    private func chip(_ title: String, _ value: String?) -> some View {
        let on = filter == value
        return Button { filter = value } label: {
            Text(title).font(.footnote.weight(on ? .semibold : .regular))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(on ? Theme.rose.opacity(0.18) : Theme.card))
                .overlay(Capsule().stroke(on ? Theme.rose : Theme.sep))
                .foregroundStyle(on ? Theme.rose : Theme.text)
        }
        .buttonStyle(.plain)
    }

    // MARK: Søgning
    private var terms: [String] {
        query.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init).filter { !$0.isEmpty }
    }

    private var results: [SearchItem] {
        let t = terms
        guard !t.isEmpty else { return [] }
        return items.filter { item in
            if let filter {
                if filter == "family" { if item.childId != nil { return false } } else if item.childId != filter { return false }
            }
            // Alle ord skal findes et sted i opslaget (titel, tekst, sted, barnets navn, type).
            return t.allSatisfy { item.haystack.contains($0) }
        }
        .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    private var grouped: [(year: Int?, items: [SearchItem])] {
        let cal = Calendar.current
        var order: [Int?] = []
        var map: [Int?: [SearchItem]] = [:]
        for r in results {
            let y = r.date.map { cal.component(.year, from: $0) }
            if map[y] == nil { order.append(y) }
            map[y, default: []].append(r)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    private func remember(_ q: String) {
        let q = q.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        var list = recentRaw.split(separator: "\n").map(String.init).filter { $0.lowercased() != q.lowercased() }
        list.insert(q, at: 0)
        recentRaw = list.prefix(5).joined(separator: "\n")
    }

    // MARK: Åbn
    private func open(_ item: SearchItem) {
        remember(query)
        dismiss()
        let entry = NotificationLogEntry(id: "search_" + item.id, date: Date(), title: "", body: item.text,
                                         kind: item.kind, recordId: item.recordId, childId: item.childId,
                                         info: ["galleryKind": item.detail, "age": item.age.map(String.init) ?? ""])
        // Lidt forsinket, så arket er lukket, før appen navigerer.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            NotificationCenter.default.post(name: .openNotificationTarget, object: entry)
        }
    }

    // MARK: Data
    private func load() async {
        defer { loading = false }
        guard let familyId = state.familyId else { return }
        let store = state.store
        var kids = (try? await store.children(familyId: familyId)) ?? []
        kids += ((try? await store.sharedChildren()) ?? []).filter { s in !kids.contains { $0.id == s.id } }
        children = kids
        let names = Dictionary(kids.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })

        // 1) Oversigten over minderne — det meste af søgningen.
        if let summaries = try? await store.memorySummaries(familyId: familyId) {
            items = summaries.compactMap { SearchItem(summary: $0, childName: $0.childId.flatMap { names[$0] }) }
        }
        // 2) Opskrifter, milepæle og "Om mig" — hentes bagefter og lægges til.
        var more: [SearchItem] = []
        if let recipes = try? await store.recipes(familyId: familyId) {
            more += recipes.map(SearchItem.init(recipe:))
        }
        for child in kids {
            if let ms = try? await store.milestones(childId: child.id) {
                for def in Constants.milestones {
                    guard let value = ms[def.key]?.value, !value.isEmpty else { continue }
                    more.append(SearchItem(milestone: def, value: value, child: child))
                }
            }
            if let answers = try? await store.answers(childId: child.id) {
                for (q, a) in answers where !a.isEmpty { more.append(SearchItem(question: q, answer: a, child: child)) }
            }
        }
        items += more
    }
}

/// Ét søgeresultat.
struct SearchItem: Identifiable {
    let id: String
    let recordId: String
    let kind: String          // CloudKit-recordtype, som notifikationerne bruger til at åbne det rigtige sted
    let label: String         // "Højdepunkt", "Milepæl" …
    let symbol: String
    let childId: String?
    let childName: String?
    let date: Date?
    let text: String
    let extra: String         // vises ikke, men søges i (beskrivelse, sted, svar)
    var detail: String = ""   // billedseriens type
    var age: Int? = nil       // interviewets alder
    var summary: MemorySummary? = nil

    var haystack: String { [label, childName ?? "Familie", text, extra].joined(separator: " ").lowercased() }

    init?(summary s: MemorySummary, childName: String?) {
        let (kind, label, symbol): (String, String, String)
        switch s.kind {
        case .highlight: (kind, label, symbol) = ("Highlight", "Højdepunkt", "star")
        case .diary: (kind, label, symbol) = ("Diary", "Dagbog", "book")
        case .event: (kind, label, symbol) = ("Event", "Begivenhed", "calendar")
        case .vacation: (kind, label, symbol) = ("Vacation", "Rejse", "airplane.departure")
        case .photo: (kind, label, symbol) = ("GalleryItem", "Billede", "photo")
        case .interview: (kind, label, symbol) = ("Interview", "Årligt interview", "bubble.left.and.text.bubble.right")
        case .tradition: (kind, label, symbol) = ("Tradition", "Tradition", "sparkles")
        case .letter:
            if s.text.hasSuffix("(forseglet)") { return nil }   // forseglede breve vises ikke i søgningen
            (kind, label, symbol) = ("Letter", "Brev", "envelope")
        case .memory: (kind, label, symbol) = ("Memory", "Minde", "heart.text.square")
        }
        id = s.id; recordId = s.id; self.kind = kind; self.label = label; self.symbol = symbol
        childId = s.childId; self.childName = childName; date = s.date ?? (s.kind == .tradition ? nil : s.createdAt)
        text = s.text; extra = s.search ?? ""; detail = s.detail; summary = s
        if s.kind == .interview, let n = Int(s.text.prefix(while: { $0.isNumber })) { age = n }
    }

    init(recipe r: Recipe) {
        id = r.id; recordId = r.id; kind = "Recipe"; label = "Opskrift"; symbol = "fork.knife"
        childId = nil; childName = nil; date = nil; text = r.title
        extra = [r.fromWhom, r.category, r.ingredients, r.story].joined(separator: " ")
    }

    init(milestone def: MilestoneDef, value: String, child: Child) {
        id = "ms_\(child.id)_\(def.key)"; recordId = id; kind = "Milestone"; label = "Milepæl"; symbol = "flag"
        childId = child.id; childName = child.name
        date = def.isDate ? Fmt.parseIso(value) : nil
        text = "\(def.label): \(MilestoneValue.display(value, kind: def.kind))"
        extra = ""; detail = def.key
    }

    init(question: String, answer: String, child: Child) {
        id = "ans_\(child.id)_\(question.hashValue)"; recordId = id; kind = "Answer"; label = "Om mig"; symbol = "person.text.rectangle"
        childId = child.id; childName = child.name; date = nil
        text = "\(question) \(answer)"; extra = ""
    }
}

/// Én række: miniature, "Højdepunkt · Theo · 14. juli 2026" og teksten med søgeordet markeret.
private struct SearchRow: View {
    @EnvironmentObject var state: AppState
    let item: SearchItem
    let terms: [String]
    @State private var photo: Data?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if let photo { DataImage(data: photo) } else {
                    ZStack { Theme.bgDark; Image(systemName: item.symbol).foregroundStyle(Theme.neutralDark) }
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text([item.label, item.childName ?? "Familie", item.date.map(Fmt.long)].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(Theme.muted)
                Text(highlighted).font(.subheadline).foregroundStyle(Theme.text).lineLimit(3)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .task(id: item.id) {
            guard photo == nil, let s = item.summary, let familyId = state.familyId else { return }
            photo = try? await state.store.coverPhoto(familyId: familyId, memory: s)
        }
    }

    /// Teksten med søgeordene fremhævet (fed og rosa).
    private var highlighted: AttributedString {
        let text = item.text
        var a = AttributedString(text)
        for term in terms {
            var from = text.startIndex
            while let r = text.range(of: term, options: [.caseInsensitive], range: from..<text.endIndex) {
                if let ar = Range(r, in: a) {
                    a[ar].foregroundColor = Theme.rose
                    a[ar].inlinePresentationIntent = .stronglyEmphasized
                }
                from = r.upperBound
            }
        }
        return a
    }
}
