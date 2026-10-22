import SwiftUI

// Hjem: hilsen, hurtig-tilføj, "På denne dag" (minder fra samme dato tidligere år)
// og seneste minder. Børnene ligger under Børn-fanen.
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
    @State private var showSearch = false
    @Environment(\.scenePhase) private var scenePhase
    /// Skifter, når appen kommer frem igen — så "Henter nyeste"-hjulet tegnes på ny og drejer (iOS fryser det i baggrunden).
    @State private var spinnerToken = 0
    // "De første skridt": tre konkrete forslag, mens mindebogen stadig er næsten tom.
    @State private var memoryCount = Int.max      // Int.max indtil første hentning, så kortet ikke blinker
    @State private var memberCount: Int?
    @State private var firstStepsHidden = true
    @State private var birthDiary: Child?
    @State private var showInvite = false
    @State private var importChild: Child?
    @State private var chooseImportChild = false
    // Skoleferie, der er ved at slutte: "har I et billede eller to, I vil gemme?" — kan afvises.
    @State private var holiday: SchoolHolidays.Holiday? = SchoolHolidays.endingSoon().flatMap { SchoolHolidays.isDismissed($0) ? nil : $0 }
    @State private var holidayChild: Child?
    @State private var chooseHolidayChild = false
    private var bornChildren: [Child] { children.filter { $0.birthDate != nil } }

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
                    if showFirstSteps { firstSteps.softAppear(index: 4) }
                    yearCards.softAppear(index: 4)
                    if let holiday, state.canEdit { holidayCard(holiday).softAppear(index: 4) }
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
        .toolbar {
            ToolbarItem(placement: .principal) { FamilyTitleMenu(title: "Hjem") }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 4) {
                    Button { showSearch = true } label: { Image(systemName: "magnifyingglass").foregroundStyle(Theme.text) }
                        .accessibilityLabel("Søg i alt")
                    NotificationBell()
                }
            }
        }
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
        .sheet(isPresented: $showSearch) { SearchView() }
        // De første skridt: fødselsminde med en overskrift at skrive videre på, og invitation af partneren.
        .sheet(item: $birthDiary, onDismiss: { Task { await load() } }) { child in
            AddDiaryView(childId: child.id, initialText: "Det, jeg husker fra dagen, \(child.name) kom til verden:\n\n")
        }
        .sheet(item: $importChild) { FirstYearImportView(child: $0) }
        .sheet(item: $holidayChild) { child in
            if let h = holiday {
                PhotoSuggestionsView(range: h.range, allowMultiple: true, maxSelection: 20, title: h.title) { photos in
                    saveHoliday(h, child: child, photos: photos)
                }
            }
        }
        .confirmationDialog("Hvilket barn?", isPresented: $chooseHolidayChild, titleVisibility: .visible) {
            ForEach(children) { child in Button(child.name) { holidayChild = child } }
        }
        .confirmationDialog("Hvilket barn?", isPresented: $chooseImportChild, titleVisibility: .visible) {
            ForEach(bornChildren) { child in Button(child.name) { importChild = child } }
        }
        .sheet(isPresented: $showInvite, onDismiss: { Task { await load() } }) {
            NavigationStack {
                FamilyAccessView(familyName: "")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Luk") { showInvite = false } } }
            }
        }
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
        // Kommer appen frem igen midt i en hentning, kan den hentning være gået i stå — start en ny,
        // så hjulet ikke bliver stående (#22).
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            spinnerToken += 1
            if refreshing { Task { await load() } } else { Task { await loadIfStale() } }
        }
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
            Text("Tilføj jeres første barn under Børn, så fylder vi forsiden med minder.")
                .font(.footnote).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(24)
        .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.sep))
    }

    // MARK: Året der gik — i januar og omkring fødselsdagen
    @ViewBuilder private var yearCards: some View {
        let ready = children.compactMap { c in YearSpec.current(for: c).map { (child: c, spec: $0) } }
        if !ready.isEmpty {
            VStack(spacing: 10) {
                SectionLabel("Året der gik")
                ForEach(ready, id: \.child.id) { item in
                    NavigationLink { YearInReviewView(child: item.child, spec: item.spec) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles.rectangle.stack").font(.system(size: 20)).foregroundStyle(Theme.green).frame(width: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(item.spec.title(for: item.child)) er klar").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                                Text("Året i tal, de bedste billeder og en lille film.").font(.caption).foregroundStyle(Theme.muted)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.muted)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.sep))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Skoleferie, der er ved at slutte
    private func holidayCard(_ h: SchoolHolidays.Holiday) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "sun.max").font(.system(size: 20)).foregroundStyle(Theme.green).frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(h.title.prefix(1).uppercased() + h.title.dropFirst()) er ved at være slut")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                    Text("Har I et billede eller to, I vil gemme? Vi viser jer billederne fra feriens dage.")
                        .font(.caption).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                Button {
                    if children.count == 1 { holidayChild = children[0] } else { chooseHolidayChild = true }
                } label: {
                    Label("Vælg fra Fotos", systemImage: "photo.on.rectangle").font(.caption.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Theme.bgDark).clipShape(Capsule())
                }
                Button("Ikke nu") { SchoolHolidays.dismiss(h); withAnimation { holiday = nil } }
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.sep))
    }

    /// Billederne fra ferien bliver ét højdepunkt for barnet med feriens navn.
    private func saveHoliday(_ h: SchoolHolidays.Holiday, child: Child, photos: [Data]) {
        guard !photos.isEmpty else { return }
        let store = state.store
        let date = photos.compactMap(ImageTools.captureDate).min() ?? h.start
        SaveQueue.shared.enqueue(label: h.title) {
            _ = try await store.addHighlight(childId: child.id, date: date, text: h.title, photos: photos, cover: 0, place: nil)
        }
        SchoolHolidays.dismiss(h)
        withAnimation { holiday = nil }
    }

    // MARK: De første skridt
    private var firstStepsKey: String { "mindebog.firstSteps.hidden_\(state.familyId ?? "")" }
    private var showFirstSteps: Bool { state.canEdit && !firstStepsHidden && memoryCount < 5 }

    private var firstSteps: some View {
        VStack(spacing: 10) {
            HStack {
                SectionLabel("De første skridt")
                Button {
                    withAnimation { firstStepsHidden = true }
                    UserDefaults.standard.set(true, forKey: firstStepsKey)
                } label: { Text("Skjul").font(.caption.weight(.semibold)) }
            }
            stepCard("photo.on.rectangle.angled", Theme.tint, "Tilføj det første billede",
                     "Et højdepunkt med et billede — fx hjemkomsten eller det første smil.") { start(.highlight) }
            stepCard("book", Theme.neutralDark, "Skriv, hvad du husker fra fødslen",
                     "Det glemmes hurtigere, end man tror. Tre linjer er nok.") {
                if children.count == 1 { birthDiary = children[0] } else { start(.diary) }
            }
            if !bornChildren.isEmpty {
                stepCard("photo.stack", Theme.green, "Hent billeder fra det første år",
                         "Vælg op til \(FirstYearImportView.maxPhotos) billeder fra Fotos — de får selv dato og alder.") {
                    if bornChildren.count == 1 { importChild = bornChildren[0] } else { chooseImportChild = true }
                }
            }
            if (memberCount ?? 2) < 2, state.usingCloud {
                stepCard("person.2", Theme.rose, "Inviter den anden forælder",
                         "Så skriver I minderne sammen — det er gratis.") { showInvite = true }
            }
        }
    }

    private func stepCard(_ symbol: String, _ color: Color, _ title: String, _ text: String,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(color).frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                    Text(text).font(.caption).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.muted)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.sep))
        }
        .buttonStyle(.plain)
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
            noChildMessage = action == .belly ? "Der er ikke noget barn på vej." : "Tilføj et barn under Børn først."
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
                            ProgressView().controlSize(.mini).id(spinnerToken)
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
                        // Tryk på teksten: åbn den skærm, opslaget hører til (som fra en notifikation).
                        Button { open(memory) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(meta(memory))
                                    .font(.caption).foregroundStyle(Theme.muted)
                                Text(memory.text.isEmpty ? "Uden tekst" : memory.text)
                                    .font(.footnote).foregroundStyle(Theme.text).lineLimit(2)
                                if let date = memory.date {
                                    Text(Fmt.long(date)).font(.caption2).foregroundStyle(Theme.muted)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        CommentsBar(targetId: memory.id, title: memory.text)
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

    /// Åbner det, et opslag handler om — via samme vej som et tryk på en notifikation (RootView.open).
    private func open(_ memory: RecentMemory) {
        guard let s = memory.summary else { return }
        let kind: String
        switch s.kind {
        case .highlight: kind = "Highlight"
        case .diary: kind = "Diary"
        case .event: kind = "Event"
        case .vacation: kind = "Vacation"
        case .photo: kind = "GalleryItem"
        case .interview: kind = "Interview"
        case .tradition: kind = "Tradition"
        case .letter: kind = "Letter"
        case .memory: kind = "Memory"
        }
        let entry = NotificationLogEntry(id: "open_" + s.id, date: Date(), title: "", body: memory.text, kind: kind,
                                         recordId: s.id, childId: s.childId, info: ["galleryKind": s.detail])
        NotificationCenter.default.post(name: .openNotificationTarget, object: entry)
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
        // Vagt (#22): svarer iCloud ikke inden for 20 sekunder, fjernes hjulet alligevel — listen fra sidst bliver stående.
        Task {
            try? await Task.sleep(for: .seconds(20))
            if isCurrent() && refreshing { refreshing = false; loading = false }
        }
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
        memoryCount = summaries.count
        firstStepsHidden = UserDefaults.standard.bool(forKey: firstStepsKey)
        if showFirstSteps, memberCount == nil, let members = try? await store.members(familyId: familyId), isCurrent() {
            memberCount = members.count
        }

        // Seneste i familien: alt, hvad der er lagt op eller ændret — det nyeste først.
        var newRecent = Array(Self.groupedPhotos(all.sorted { changed($0) > changed($1) }).prefix(5))

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
    /// Flere billeder lagt op samme dag til samme serie for samme barn (fx fem fødselsdagsbilleder)
    /// bliver ét opslag: "9 · 5 billeder". Listen er sorteret nyeste først; det nyeste billede vises.
    private static func groupedPhotos(_ list: [RecentMemory]) -> [RecentMemory] {
        let cal = Calendar.current
        func key(_ m: RecentMemory) -> String? {
            guard let s = m.summary, s.kind == .photo else { return nil }
            return [s.childId ?? "", s.detail, s.text, Fmt.iso(cal.startOfDay(for: s.createdAt))].joined(separator: "|")
        }
        var counts: [String: Int] = [:]
        for m in list { if let k = key(m) { counts[k, default: 0] += 1 } }
        var seen: Set<String> = []
        return list.compactMap { m in
            guard let k = key(m) else { return m }
            guard seen.insert(k).inserted else { return nil }
            let n = counts[k] ?? 1
            guard n > 1 else { return m }
            let text = m.text.isEmpty ? "\(n) billeder" : "\(m.text) · \(n) billeder"
            return RecentMemory(id: m.id, summary: m.summary, childName: m.childName, kind: m.kind, symbol: m.symbol,
                                date: m.date, sortDate: m.sortDate, text: text, photo: m.photo)
        }
    }

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
