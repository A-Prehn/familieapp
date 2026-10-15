import SwiftUI

// Hjem = "lige nu": hilsen, børnene i dag, det næste der sker, seneste minder
// og hurtig-tilføj. Oversigten/strukturen ligger under Familie-fanen.
struct HomeView: View {
    @EnvironmentObject var state: AppState
    @State private var children: [Child] = []
    @State private var next: Upcoming?
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
                    todaySection
                    quickAddSection
                    if let next { nextCard(next) }
                    if !recent.isEmpty { recentSection }
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

    private var todaySection: some View {
        VStack(spacing: 10) {
            SectionLabel("I dag")
            ForEach(children) { child in
                NavigationLink(value: child) {
                    HStack(spacing: 14) {
                        Circle().fill(Theme.bgDark).frame(width: 48, height: 48)
                            .overlay(Image(systemName: "figure.child").foregroundStyle(Theme.neutralDark))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(child.name).font(.serifTitle(17)).foregroundStyle(Theme.text)
                            Text(ChildAge.today(child)).font(.footnote).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.muted)
                    }
                    .padding(14)
                    .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.sep))
                }
                .buttonStyle(.plain)
            }
        }
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

    private func nextCard(_ item: Upcoming) -> some View {
        VStack(spacing: 10) {
            SectionLabel("Næste")
            HStack(spacing: 14) {
                VStack(spacing: 0) {
                    if item.days == 0 {
                        Text("🎉").font(.title3)
                    } else {
                        Text("\(item.days)").font(.serifTitle(20))
                        Text(item.days == 1 ? "dag" : "dage").font(.caption2).foregroundStyle(Theme.muted)
                    }
                }
                .frame(width: 60).padding(.vertical, 8)
                .background(Theme.bgDark).clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.system(size: 15, weight: .medium))
                    Text("\(item.kind) · \(Fmt.long(item.date))").font(.footnote).foregroundStyle(Theme.muted)
                }
                Spacer()
            }
            .padding(14)
            .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.sep))
        }
    }

    private var recentSection: some View {
        VStack(spacing: 10) {
            SectionLabel("Seneste minder")
            ForEach(recent) { memory in
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
                        Text("\(memory.childName) · \(memory.kind)")
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
        let loadedEvents = (try? await store.events(familyId: familyId)) ?? []
        let loadedVacations = (try? await store.vacations(familyId: familyId)) ?? []
        let loadedBirthdays = (try? await store.birthdays(familyId: familyId)) ?? []

        // Næste: fødselsdage (årlige), begivenheder og ferier fremad i tiden.
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var candidates: [Upcoming] = []
        func days(to date: Date) -> Int { cal.dateComponents([.day], from: today, to: cal.startOfDay(for: date)).day ?? 0 }
        for child in loadedKids {
            if let birth = child.birthDate {
                let next = Fmt.nextOccurrence(of: birth, from: today)
                candidates.append(Upcoming(title: "\(child.name)s fødselsdag", kind: "Fødselsdag", date: next, days: days(to: next)))
            } else if let due = child.dueDate, due >= today {
                candidates.append(Upcoming(title: "Termin · \(child.name)", kind: "Termin", date: due, days: days(to: due)))
            }
        }
        for b in loadedBirthdays {
            let next = Fmt.nextOccurrence(of: b.date, from: today)
            candidates.append(Upcoming(title: "\(b.emoji) \(b.name)", kind: "Fødselsdag", date: next, days: days(to: next)))
        }
        for e in loadedEvents { if let d = e.date, d >= today { candidates.append(Upcoming(title: e.title, kind: "Begivenhed", date: d, days: days(to: d))) } }
        for v in loadedVacations { if let d = v.startDate, d >= today { candidates.append(Upcoming(title: v.title, kind: "Ferie", date: d, days: days(to: d))) } }
        next = candidates.min { $0.days < $1.days }

        // Seneste minder på tværs af børnene (højdepunkter + dagbog).
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
    }
}

// MARK: - Hjælpetyper

struct Upcoming {
    let title: String
    let kind: String
    let date: Date
    let days: Int
}

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
