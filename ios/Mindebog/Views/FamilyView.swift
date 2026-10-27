import SwiftUI

struct FamilyView: View {
    @EnvironmentObject var state: AppState
    @Namespace private var zoomNS   // zoom-overgang til fuld skærm (iOS 18)

    enum Tab: String, CaseIterable, Identifiable {
        case memories = "Minder"
        case events = "Begivenheder"
        case vacations = "Rejser"
        case birthdays = "Fødselsdage"
        case tree = "Stamtræ"
        case traditions = "Traditioner"
        case recipes = "Opskrifter"
        var id: String { rawValue }

        /// Fanerne, der vises. Stamtræet er taget ud, indtil tegningen af det er færdig.
        static var visible: [Tab] { allCases.filter { $0 != .tree } }

        var symbol: String {
            switch self {
            case .memories: "heart"
            case .events: "calendar"
            case .vacations: "airplane.departure"
            case .birthdays: "gift"
            case .tree: "tree"
            case .traditions: "sparkles"
            case .recipes: "fork.knife"
            }
        }
    }

    @State private var tab: Tab = .memories
    @State private var events: [FamilyEvent] = []
    @State private var vacations: [Vacation] = []
    @State private var children: [Child] = []
    @State private var customBirthdays: [CustomBirthday] = []
    @State private var persons: [Person] = []
    @State private var editingPerson: Person?
    @State private var members: [AppUser] = []
    @State private var traditions: [Tradition] = []
    @State private var recipes: [Recipe] = []
    @State private var editingRecipe: Recipe?
    @State private var memories: [FamilyMemory] = []
    @State private var editingMemory: FamilyMemory?
    @State private var editingTradition: Tradition?
    @State private var activeSheet: Tab?
    @State private var editingEvent: FamilyEvent?
    @State private var editingVacation: Vacation?
    @State private var editingBirthday: CustomBirthday?
    @State private var lightbox: LightboxState?
    @State private var showVacationMap = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Seks faner med ikon og kort tekst, alle synlige på én gang; den valgte har en rosa streg under.
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        ForEach(Tab.visible) { t in
                            Button { if reduceMotion { tab = t } else { withAnimation(.snappy) { tab = t } } } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: t.symbol)
                                        .font(.system(size: 18, weight: tab == t ? .semibold : .light))
                                    // Fulde navne — med fem faner er der plads; teksten skrumper lidt, hvis ikke.
                                    Text(t.rawValue).font(.system(size: 11, weight: tab == t ? .semibold : .regular))
                                        .lineLimit(1).minimumScaleFactor(0.7)
                                    Rectangle()
                                        .fill(tab == t ? Theme.rose : .clear)
                                        .frame(height: 2)
                                        .padding(.horizontal, 6)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.top, 4)
                                .foregroundStyle(tab == t ? Theme.rose : Theme.muted)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Rectangle().fill(Theme.sep).frame(height: 1)
                }

                Group {
                switch tab {
                case .memories: MemoriesView(memories: memories, children: children, members: members, onEdit: { editMemory($0) },
                                             onAdd: { activeSheet = .memories }, onLightbox: { openLightbox($0) })
                case .events: eventsList
                case .vacations: vacationsList
                case .birthdays: birthdaysList
                case .tree: FamilyTreeView(persons: persons, children: children,
                                           onEdit: { editPerson($0) }, onAdd: { activeSheet = .tree })
                case .traditions: TraditionsView(traditions: traditions, onEdit: { editTradition($0) },
                                                 onAdd: { activeSheet = .traditions }, onLightbox: { openLightbox($0) })
                case .recipes: RecipesView(recipes: recipes, onEdit: { editRecipe($0) },
                                           onAdd: { activeSheet = .recipes }, onLightbox: { openLightbox($0) })
                }
                }
                .id(tab)
                .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .trailing)))
            }
            .padding(16)
        }
        .jumpsToPendingRecord()
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Familie")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { FamilyTitleMenu(title: "Familie") }
            ToolbarItem(placement: .topBarTrailing) {
                if state.canEdit { Button { activeSheet = tab } label: { Image(systemName: "plus") } }
            }
        }
        .sheet(item: $activeSheet, onDismiss: { Task { await load() } }) { which in
            switch which {
            case .memories: MemoryEditView(familyId: state.familyId ?? "", children: children, members: members)
            case .events: AddEventView(familyId: state.familyId ?? "", children: children, members: members)
            case .vacations: AddVacationView(familyId: state.familyId ?? "", children: children, members: members)
            case .birthdays: AddBirthdayView(familyId: state.familyId ?? "")
            case .tree: PersonEditView(familyId: state.familyId ?? "", persons: persons, children: children,
                                       members: members, birthdays: customBirthdays)
            case .traditions: TraditionEditView(familyId: state.familyId ?? "")
            case .recipes: RecipeEditView(familyId: state.familyId ?? "")
            }
        }
        .sheet(item: $editingEvent, onDismiss: { Task { await load() } }) { event in
            AddEventView(familyId: state.familyId ?? "", children: children, members: members, editing: event)
        }
        .sheet(item: $editingVacation, onDismiss: { Task { await load() } }) { vacation in
            AddVacationView(familyId: state.familyId ?? "", children: children, members: members, editing: vacation)
        }
        .sheet(item: $editingBirthday, onDismiss: { Task { await load() } }) { birthday in
            AddBirthdayView(familyId: state.familyId ?? "", editing: birthday)
        }
        .sheet(item: $editingMemory, onDismiss: { Task { await load() } }) { m in
            MemoryEditView(familyId: state.familyId ?? "", children: children, members: members, editing: m)
        }
        .sheet(item: $editingTradition, onDismiss: { Task { await load() } }) { t in
            TraditionEditView(familyId: state.familyId ?? "", editing: t)
        }
        .sheet(item: $editingRecipe, onDismiss: { Task { await load() } }) { r in
            RecipeEditView(familyId: state.familyId ?? "", editing: r)
        }
        .sheet(item: $editingPerson, onDismiss: { Task { await load() } }) { person in
            PersonEditView(familyId: state.familyId ?? "", persons: persons, children: children,
                           members: members, birthdays: customBirthdays, editing: person)
        }
        .fullScreenCover(item: $lightbox) { LightboxView(state: $0).zoomTarget(id: $0.sourceId, in: zoomNS) }
        .refreshable { await load() }
        .task { await load() }
        .reloadOnStoreChange { await load() }
        // Fra en notifikation: vis det rigtige faneblad (også hvis skærmen først oprettes nu).
        .onReceive(NotificationCenter.default.publisher(for: .openFamilyTab)) { note in
            if let raw = note.object as? String, let t = Tab(rawValue: raw) { tab = t; FamilyTabLink.pending = nil }
        }
        .onAppear {
            if let raw = FamilyTabLink.pending, let t = Tab(rawValue: raw) { tab = t; FamilyTabLink.pending = nil }
        }
    }

    // MARK: Begivenheder
    @ViewBuilder
    private var eventsList: some View {
        if events.isEmpty {
            ContentUnavailableView("Ingen begivenheder endnu", systemImage: "calendar")
                .padding(.top, 40)
        } else {
            // Tidslinje som ferier og højdepunkter: nyeste øverst, årstal når året skifter.
            TimelineView(items: events,
                         year: { $0.date.map { Calendar.current.component(.year, from: $0) } }) { event in
                PhotoCard(photos: event.photos, title: event.title, subtitle: event.date.map(Fmt.long),
                          about: aboutText(childIds: event.childIds, personIds: event.personIds),
                          zoomId: event.id, zoomNamespace: zoomNS,
                          onEdit: state.canEdit ? { editEvent(event) } : nil, onOpen: { openLightbox($0) }) {
                    VStack(alignment: .leading, spacing: 8) {
                        if !event.details.isEmpty {
                            Text(event.details).font(.footnote).foregroundStyle(Theme.muted)
                        }
                        if let place = event.place {
                            PlaceLabel(place: place)
                            PlaceMap(place: place)
                        }
                        CommentsBar(targetId: event.id, title: event.title)
                    }
                }
                .pressableCard { if state.canEdit { editEvent(event) } }
            }
        }
    }

    // MARK: Ferier
    @ViewBuilder
    private var vacationsList: some View {
        if vacations.isEmpty {
            ContentUnavailableView("Ingen rejser endnu", systemImage: "beach.umbrella")
                .padding(.top, 40)
        } else {
            // Liste eller verdenskort (#26).
            Picker("Visning", selection: $showVacationMap) {
                Label("Liste", systemImage: "list.bullet").tag(false)
                Label("Kort", systemImage: "globe.europe.africa").tag(true)
            }
            .pickerStyle(.segmented)
            if showVacationMap {
                VacationMapView(vacations: vacations, dateText: dateRange) { v in
                    if state.canEdit { editVacation(v) } else { showVacationMap = false }
                }
            } else {
            // Tidslinje som på websitet: nyeste øverst, årstal hver gang året skifter.
            TimelineView(items: vacations,
                         year: { $0.startDate.map { Calendar.current.component(.year, from: $0) } }) { vacation in
                    PhotoCard(photos: vacation.photos, title: vacation.title, subtitle: dateRange(vacation),
                              about: aboutText(childIds: vacation.childIds, personIds: vacation.personIds),
                              zoomId: vacation.id, zoomNamespace: zoomNS,
                              onEdit: state.canEdit ? { editVacation(vacation) } : nil, onOpen: { openLightbox($0) }) {
                        VStack(alignment: .leading, spacing: 8) {
                            if !vacation.details.isEmpty {
                                Text(vacation.details).font(.footnote).foregroundStyle(Theme.muted)
                            }
                            if let place = vacation.place {
                                PlaceLabel(place: place)
                                PlaceMap(place: place)
                            }
                            CommentsBar(targetId: vacation.id, title: vacation.title)
                        }
                    }
                    .pressableCard { if state.canEdit { editVacation(vacation) } }
            }
            }
        }
    }

    // MARK: Fødselsdage
    private struct BirthdayRow: Identifiable {
        let id: String
        let name: String
        let emoji: String
        let date: Date
        let days: Int
        let turning: Int
        /// Sat for egne fødselsdage (kan redigeres her); nil for børnene (rettes på barnets side).
        var custom: CustomBirthday? = nil
    }

    private var birthdayRows: [BirthdayRow] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var rows: [BirthdayRow] = []

        func make(id: String, name: String, emoji: String, date: Date) -> BirthdayRow {
            let next = Fmt.nextOccurrence(of: date, from: today)
            let days = cal.dateComponents([.day], from: today, to: next).day ?? 0
            let turning = cal.component(.year, from: next) - cal.component(.year, from: date)
            return BirthdayRow(id: id, name: name, emoji: emoji, date: date, days: days, turning: turning)
        }

        for child in children {
            if let birth = child.birthDate {
                let emoji = child.gender == .girl ? "👧" : (child.gender == .boy ? "👦" : "🧒")
                rows.append(make(id: child.id, name: child.name, emoji: emoji, date: birth))
            }
        }
        for custom in customBirthdays {
            var row = make(id: custom.id, name: custom.name, emoji: custom.emoji, date: custom.date)
            row.custom = custom
            rows.append(row)
        }
        return rows.sorted { $0.days < $1.days }
    }

    @ViewBuilder
    private var birthdaysList: some View {
        let rows = birthdayRows
        if rows.isEmpty {
            ContentUnavailableView("Ingen fødselsdage endnu", systemImage: "gift")
                .padding(.top, 40)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider() }
                    HStack(spacing: 14) {
                        VStack(spacing: 0) {
                            if row.days == 0 {
                                Image(systemName: "gift.fill").font(.title3).foregroundStyle(Theme.rose)
                                Text("i dag").font(.caption2).foregroundStyle(Theme.muted)
                            } else {
                                Text("\(row.days)").font(.serifTitle(20))
                                Text(row.days == 1 ? "dag" : "dage")
                                    .font(.caption2).foregroundStyle(Theme.muted)
                            }
                        }
                        .frame(width: 60)
                        .padding(.vertical, 8)
                        .background(Theme.bgDark)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.small))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.name).font(.system(size: 15, weight: .medium))
                            Text("\(dayMonth(row.date)) · fylder \(row.turning)")
                                .font(.footnote).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        if row.custom != nil {
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                    .onTapGesture { if state.canEdit, let custom = row.custom { editingBirthday = custom } }
                }
            }
            .padding(.horizontal, 16)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Theme.sep))
        }
    }

    // MARK: Hjælpere
    private static let danish = Locale(identifier: "da_DK")

    private func dayMonth(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Self.danish
        f.dateFormat = "d. MMMM"
        return f.string(from: date)
    }

    /// "Handler om" som tekst til PhotoCard, fx "William · Nohr"; nil hvis ingen er valgt.
    private func aboutText(childIds: [String], personIds: [String]) -> String? {
        let names = AboutPicker.names(childIds: childIds, personIds: personIds, children: children, members: members)
        return names.isEmpty ? nil : names
    }

    /// Dato og "handler om" på én linje under titlen: "15. november 2024 · Nohr, Sheila".
    @ViewBuilder
    private func aboutLine(date: String?, childIds: [String], personIds: [String]) -> some View {
        let names = AboutPicker.names(childIds: childIds, personIds: personIds, children: children, members: members)
        if date != nil || !names.isEmpty {
            HStack(spacing: 6) {
                if let date { Text(date) }
                if !names.isEmpty {
                    if date != nil { Text("·") }
                    Label(names, systemImage: "person")
                }
            }
            .font(.caption).foregroundStyle(Theme.muted)
        }
    }

    private func dateRange(_ vacation: Vacation) -> String? {
        switch (vacation.startDate, vacation.endDate) {
        case let (start?, end?): return "\(Fmt.long(start)) – \(Fmt.long(end))"
        case let (start?, nil): return Fmt.long(start)
        case let (nil, end?): return Fmt.long(end)
        default: return nil
        }
    }

    private struct Cached: Codable {
        var events: [FamilyEvent]
        var vacations: [Vacation]
        var children: [Child]
        var birthdays: [CustomBirthday]
        var persons: [Person] = []
        var traditions: [Tradition] = []
        var memories: [FamilyMemory] = []
        var recipes: [Recipe] = []
    }

    // MARK: Originaler (#62)
    // Listerne viser thumbs fra kopien. Fuld skærm åbner med thumbet og skifter til originalerne, når de er
    // hentet; redigering venter på originalerne, så et gem aldrig kan ændre billederne uden at have dem.

    private func openLightbox(_ shown: LightboxState) {
        lightbox = shown
        guard shown.needsOriginals, let id = shown.sourceId else { return }
        Task {
            await CloudKitStore.withOriginals { await load() }
            if let set = photoSet(for: id), !set.photos.isEmpty { lightbox = LightboxState.coverFirst(set, sourceId: id) }
        }
    }

    private func photoSet(for id: String) -> PhotoSet? {
        events.first { $0.id == id }?.photos
            ?? vacations.first { $0.id == id }?.photos
            ?? traditions.first { $0.id == id }?.photos
            ?? memories.first { $0.id == id }?.photos
            ?? recipes.first { $0.id == id }?.photos
    }

    private func withOriginals(_ loaded: Bool, then open: @escaping () -> Void) {
        if loaded { open(); return }
        Task { await CloudKitStore.withOriginals { await load() }; open() }
    }

    private func editEvent(_ e: FamilyEvent) {
        withOriginals(e.photos.loaded) { editingEvent = events.first { $0.id == e.id } ?? e }
    }
    private func editVacation(_ v: Vacation) {
        withOriginals(v.photos.loaded) { editingVacation = vacations.first { $0.id == v.id } ?? v }
    }
    private func editTradition(_ t: Tradition) {
        withOriginals(t.photos.loaded) { editingTradition = traditions.first { $0.id == t.id } ?? t }
    }
    private func editMemory(_ m: FamilyMemory) {
        withOriginals(m.photos.loaded) { editingMemory = memories.first { $0.id == m.id } ?? m }
    }
    private func editRecipe(_ r: Recipe) {
        withOriginals(r.photos.loaded) { editingRecipe = recipes.first { $0.id == r.id } ?? r }
    }
    private func editPerson(_ p: Person) {
        withOriginals(p.photoLoaded) { editingPerson = persons.first { $0.id == p.id } ?? p }
    }

    private func load() async {
        guard let familyId = state.familyId else { return }
        let cacheKey = "shared_\(familyId)"
        if events.isEmpty && vacations.isEmpty && customBirthdays.isEmpty,
           let cached = ScreenCache.load(Cached.self, key: cacheKey) {
            events = cached.events
            vacations = cached.vacations
            children = cached.children
            ChildPalette.update(children)
            customBirthdays = cached.birthdays
            persons = cached.persons
            traditions = cached.traditions
            memories = cached.memories
            recipes = cached.recipes
        }
        // Alle syv opslag kører samtidig — ventetiden bliver som det langsomste, ikke summen.
        // Behold det viste ved netværksfejl i stedet for at tømme listerne.
        let store = state.store
        async let eventsTask = store.events(familyId: familyId)
        async let vacationsTask = store.vacations(familyId: familyId)
        async let childrenTask = store.children(familyId: familyId)
        async let birthdaysTask = store.birthdays(familyId: familyId)
        async let personsTask = store.persons(familyId: familyId)
        async let membersTask = store.members(familyId: familyId)
        async let traditionsTask = store.traditions(familyId: familyId)
        async let memoriesTask = store.memories(familyId: familyId)
        async let recipesTask = store.recipes(familyId: familyId)
        if let v = try? await eventsTask { events = v }
        if let v = try? await vacationsTask { vacations = v }
        if let v = try? await childrenTask { children = v; ChildPalette.update(v) }
        if let v = try? await birthdaysTask { customBirthdays = v }
        if let v = try? await personsTask { persons = v }
        if let v = try? await membersTask { members = v }
        if let v = try? await traditionsTask { traditions = v }
        if let v = try? await memoriesTask { memories = v }
        if let v = try? await recipesTask { recipes = v }
        ScreenCache.save(Cached(events: events, vacations: vacations, children: children, birthdays: customBirthdays,
                                persons: persons, traditions: traditions, memories: memories, recipes: recipes),
                         key: cacheKey)
    }
}

// MARK: - Tilføj-formularer

struct AddEventView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let familyId: String
    var children: [Child] = []
    var members: [AppUser] = []
    /// Sat ved redigering; nil ved oprettelse.
    var editing: FamilyEvent? = nil
    @State private var title = ""
    @State private var date = Date()
    @State private var details = ""
    @State private var photos = PhotoSet()
    @State private var place: Place?
    @State private var childIds: [String] = []
    @State private var personIds: [String] = []
    @State private var loaded = false
    @State private var confirmDelete = false
    @State private var saving = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                Group {
                TextField("Titel", text: $title)
                DatePicker("Dato", selection: $date, displayedComponents: .date)
                Section("Beskrivelse") {
                    TextField("Beskrivelse", text: $details, axis: .vertical).lineLimit(2...5)
                }
                AboutPicker(children: children, members: members, childIds: $childIds, personIds: $personIds)
                Section("Sted") {
                    PlaceField(place: $place)
                }
                Section("Billeder") {
                    PhotoSetEditor(set: $photos)
                }
                if editing != nil {
                    Section {
                        Button("Slet begivenhed", role: .destructive) { confirmDelete = true }
                    }
                }
                }.listRowBackground(Theme.card)
            }
            .themedList()
            .navigationTitle(editing == nil ? "Ny begivenhed" : "Redigér begivenhed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annullér") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gem") {
                        Task {
                            if var event = editing {
                                event.title = title; event.date = date; event.details = details
                                event.photos = photos; event.place = place
                                event.childIds = childIds; event.personIds = personIds
                                let updated = event
                                await performSave(saving: $saving, errorMessage: $saveError, dismiss: dismiss) {
                                    _ = try await state.store.updateEvent(familyId: familyId, updated)
                                }
                            } else {
                                let (store, familyId, title, date, details, photos, place, childIds, personIds) =
                                    (state.store, familyId, title, date, details, photos, place, childIds, personIds)
                                performSaveInBackground(label: "begivenheden", dismiss: dismiss) {
                                    _ = try await store.addEvent(familyId: familyId, title: title, date: date,
                                                                 details: details, photos: photos, place: place,
                                                                 childIds: childIds, personIds: personIds)
                                }
                            }
                        }
                    }
                    .disabled(saving || title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .saveErrorAlert($saveError)
            .confirmationDialog("Slet \"\(title)\"?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Slet", role: .destructive) {
                    Task {
                        await performSave(saving: $saving, errorMessage: $saveError, dismiss: dismiss) {
                            if let id = editing?.id { try await state.store.deleteEvent(familyId: familyId, id: id) }
                        }
                    }
                }
            } message: {
                Text("Begivenheden og dens billede slettes for hele familien.")
            }
            .onAppear {
                guard !loaded, let e = editing else { return }
                loaded = true
                title = e.title; date = e.date ?? Date(); details = e.details
                photos = e.photos; place = e.place
                childIds = e.childIds; personIds = e.personIds
            }
        }
    }
}

struct AddVacationView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let familyId: String
    var children: [Child] = []
    var members: [AppUser] = []
    /// Sat ved redigering; nil ved oprettelse.
    var editing: Vacation? = nil
    @State private var title = ""
    @State private var start = Date()
    @State private var end = Date()
    @State private var details = ""
    @State private var photos = PhotoSet()
    @State private var place: Place?
    @State private var childIds: [String] = []
    @State private var personIds: [String] = []
    @State private var loaded = false
    @State private var confirmDelete = false
    @State private var saving = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                Group {
                TextField("Titel (f.eks. Sommerhus i Skagen)", text: $title)
                DatePicker("Fra", selection: $start, displayedComponents: .date)
                DatePicker("Til", selection: $end, in: start..., displayedComponents: .date)
                Section("Beskrivelse") {
                    TextField("Beskrivelse", text: $details, axis: .vertical).lineLimit(2...5)
                }
                AboutPicker(children: children, members: members, childIds: $childIds, personIds: $personIds)
                Section("Sted") {
                    PlaceField(place: $place)
                }
                Section("Billeder") {
                    PhotoSetEditor(set: $photos)
                }
                if editing != nil {
                    Section {
                        Button("Slet rejse", role: .destructive) { confirmDelete = true }
                    }
                }
                }.listRowBackground(Theme.card)
            }
            .themedList()
            .navigationTitle(editing == nil ? "Ny rejse" : "Redigér rejse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annullér") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gem") {
                        Task {
                            if var vacation = editing {
                                vacation.title = title; vacation.startDate = start; vacation.endDate = end
                                vacation.details = details; vacation.photos = photos; vacation.place = place
                                vacation.childIds = childIds; vacation.personIds = personIds
                                let updated = vacation
                                await performSave(saving: $saving, errorMessage: $saveError, dismiss: dismiss) {
                                    _ = try await state.store.updateVacation(familyId: familyId, updated)
                                }
                            } else {
                                let (store, familyId, title, start, end, details, photos, place, childIds, personIds) =
                                    (state.store, familyId, title, start, end, details, photos, place, childIds, personIds)
                                performSaveInBackground(label: "rejsen", dismiss: dismiss) {
                                    _ = try await store.addVacation(familyId: familyId, title: title, start: start, end: end,
                                                                    details: details, photos: photos, place: place,
                                                                    childIds: childIds, personIds: personIds)
                                }
                            }
                        }
                    }
                    .disabled(saving || title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .saveErrorAlert($saveError)
            .confirmationDialog("Slet \"\(title)\"?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Slet", role: .destructive) {
                    Task {
                        await performSave(saving: $saving, errorMessage: $saveError, dismiss: dismiss) {
                            if let id = editing?.id { try await state.store.deleteVacation(familyId: familyId, id: id) }
                        }
                    }
                }
            } message: {
                Text("Rejsen og dens billede slettes for hele familien.")
            }
            .onAppear {
                guard !loaded, let v = editing else { return }
                loaded = true
                title = v.title; start = v.startDate ?? Date(); end = v.endDate ?? start
                details = v.details; photos = v.photos; place = v.place
                childIds = v.childIds; personIds = v.personIds
            }
        }
    }
}

struct AddBirthdayView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let familyId: String
    /// Sat ved redigering; nil ved oprettelse.
    var editing: CustomBirthday? = nil
    @State private var name = ""
    @State private var date = Date()
    @State private var emoji = ""
    @State private var saving = false
    @State private var saveError: String?
    @State private var loaded = false
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Group {
                TextField("Navn (f.eks. Mormor)", text: $name)
                DatePicker("Fødselsdato", selection: $date, in: ...Date(), displayedComponents: .date)
                if editing != nil {
                    Section {
                        Button("Slet fødselsdag", role: .destructive) { confirmDelete = true }
                    }
                }
                }.listRowBackground(Theme.card)
            }
            .themedList()
            .navigationTitle(editing == nil ? "Ny fødselsdag" : "Redigér fødselsdag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annullér") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gem") {
                        Task {
                            await performSave(saving: $saving, errorMessage: $saveError, dismiss: dismiss) {
                                if var birthday = editing {
                                    birthday.name = name; birthday.date = date; birthday.emoji = emoji
                                    try await state.store.updateBirthday(familyId: familyId, birthday)
                                } else {
                                    _ = try await state.store.addBirthday(familyId: familyId, name: name, date: date, emoji: emoji)
                                }
                            }
                        }
                    }
                    .disabled(saving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .saveErrorAlert($saveError)
            .confirmationDialog("Slet \(name)s fødselsdag?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Slet", role: .destructive) {
                    Task {
                        await performSave(saving: $saving, errorMessage: $saveError, dismiss: dismiss) {
                            if let id = editing?.id { try await state.store.deleteBirthday(familyId: familyId, id: id) }
                        }
                    }
                }
            }
            .onAppear {
                guard !loaded, let b = editing else { return }
                loaded = true
                name = b.name; date = b.date; emoji = b.emoji
            }
        }
    }
}
