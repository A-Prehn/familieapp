import SwiftUI

struct DiaryView: View {
    @EnvironmentObject var state: AppState
    @Namespace private var zoomNS   // zoom-overgang til fuld skærm (iOS 18)
    let child: Child
    @State private var entries: [DiaryEntry] = []
    @State private var showAdd = false
    @State private var editing: DiaryEntry?
    @State private var lightbox: LightboxState?
    @State private var loading = true

    var body: some View {
        ScrollView {
            if entries.isEmpty && loading {
                ShimmerList()
            } else if entries.isEmpty {
                ContentUnavailableView("Ingen indlæg endnu", systemImage: "book")
                    .padding(.top, 60)
            } else {
                // Tidslinje som ferier og højdepunkter; uden dato bruges oprettelsesåret.
                TimelineView(items: entries,
                             year: { Calendar.current.component(.year, from: $0.date ?? $0.createdAt) }) { entry in
                    card(entry)
                }
                .padding(16)
            }
        }
        .jumpsToPendingRecord()
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(child.onTheWay ? "Svangerskabsdagbog" : "Dagbog")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if state.canEdit { Button { showAdd = true } label: { Image(systemName: "plus") } }
            }
        }
        .sheet(isPresented: $showAdd, onDismiss: { Task { await load() } }) {
            AddDiaryView(childId: child.id)
        }
        .sheet(item: $editing, onDismiss: { Task { await load() } }) { entry in
            AddDiaryView(childId: child.id, editing: entry)
        }
        .fullScreenCover(item: $lightbox) { LightboxView(state: $0).zoomTarget(id: $0.sourceId, in: zoomNS) }
        .refreshable { await load() }
        .task { await load() }
        .reloadOnStoreChange { await load() }
    }

    // Tryk på opslaget = redigér; tryk på billedet = fuld skærm.
    // Samme kortstil som tidslinjen for ferier og højdepunkter.
    private func card(_ entry: DiaryEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let date = entry.date {
                Text(Fmt.long(date)).font(.caption).foregroundStyle(Theme.muted)
            }
            Text(entry.text).font(.body).foregroundStyle(Theme.text)
            if !entry.photos.isEmpty {
                // Forsidebillede + "+N" for resten (#71); tryk viser alle billeder.
                CoverPhotoView(set: entry.photos, cornerRadius: Radius.small, zoomId: entry.id, zoomNamespace: zoomNS) {
                    openLightbox($0, entry: entry)
                }
            }
            CommentsBar(targetId: entry.id, title: entry.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Theme.sep))
        .contentShape(RoundedRectangle(cornerRadius: Radius.card))
        .onTapGesture { if state.canEdit { edit(entry) } }
        .contextMenu {
            Button { if state.canEdit { edit(entry) } } label: { Label("Redigér", systemImage: "pencil") }
        }
    }

    /// Fuld skærm: thumb med det samme, og originalerne så snart de er hentet (#62).
    private func openLightbox(_ shown: LightboxState, entry: DiaryEntry) {
        lightbox = shown
        guard shown.needsOriginals else { return }
        Task {
            await CloudKitStore.withOriginals { await load() }
            guard let fresh = entries.first(where: { $0.id == entry.id }), !fresh.photos.photos.isEmpty,
                  lightbox?.id == shown.id else { return }
            lightbox = LightboxState.coverFirst(fresh.photos, sourceId: entry.id).replacing(shown)
        }
    }

    /// Redigering kræver originalen (ellers ville et gem ikke kunne ændre billedet).
    private func edit(_ entry: DiaryEntry) {
        if entry.photoLoaded { editing = entry; return }
        Task {
            await CloudKitStore.withOriginals { await load() }
            editing = entries.first { $0.id == entry.id } ?? entry
        }
    }

    private func load() async {
        defer { loading = false }
        let cacheKey = "diary_\(child.id)"
        if entries.isEmpty, let cached = ScreenCache.load([DiaryEntry].self, key: cacheKey) { entries = cached; loading = false }
        if let fresh = try? await state.store.diary(childId: child.id) {
            entries = fresh
            ScreenCache.save(fresh, key: cacheKey)
        }
    }
}

struct AddDiaryView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let childId: String
    /// Øvrige børn samme indlæg også gemmes for (hurtig-tilføj på Hjem med flere børn valgt).
    var alsoFor: [Child] = []
    /// Navne vist øverst i formularen, når der gemmes for flere børn.
    var forNames: [String] = []
    /// Sat ved redigering; nil ved oprettelse.
    var editing: DiaryEntry? = nil
    /// Tekst, feltet starter med (ugens spørgsmål som overskrift).
    var initialText: String = ""
    @State private var date = Date()
    @State private var text = ""
    @State private var photos: [Data] = []
    @State private var cover = 0
    @State private var saving = false
    @State private var saveError: String?
    @State private var savedFor: Set<String> = []   // ved fejl midt i flere børn: undgå dubletter ved nyt forsøg
    @State private var loaded = false
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Group {
                ForChildrenNote(names: forNames)
                DatePicker("Dato", selection: $date, displayedComponents: .date)
                Section("Tekst") {
                    TextField("Skriv dit indlæg…", text: $text, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section("Billeder") {
                    // Flere billeder pr. indlæg (#71); forslag fra dagene omkring den dato, man skriver om.
                    MultiPhotoField(photos: $photos, cover: $cover, suggestRange: .around(date, days: 3))
                }
                if editing != nil {
                    Section {
                        Button("Slet indlæg", role: .destructive) { confirmDelete = true }
                    }
                }
                }.listRowBackground(Theme.card)
            }
            .themedList()
            .navigationTitle(editing == nil ? "Nyt indlæg" : "Redigér indlæg")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annullér") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gem") {
                        // Billedtekster bevares fra før, hvis billederne ikke er rørt.
                        var set = editing?.photos ?? PhotoSet()
                        if set.photos != photos { set.captions = [] }
                        set.photos = photos; set.cover = cover; set.loaded = true
                        if var entry = editing {
                            entry.date = date; entry.text = text; entry.photos = set
                            let updated = entry
                            Task {
                                await performSave(saving: $saving, errorMessage: $saveError, dismiss: dismiss) {
                                    try await state.store.updateDiary(childId: childId, updated)
                                }
                            }
                        } else {
                            // Nyt indlæg: luk med det samme, gem i baggrunden.
                            let (store, ids, date, text, set) = (state.store, [childId] + alsoFor.map(\.id), date, text, set)
                            performSaveInBackground(label: "dagbogsindlægget", dismiss: dismiss) {
                                for id in ids {
                                    _ = try await store.addDiary(childId: id, date: date, text: text, photos: set)
                                }
                            }
                        }
                    }
                    .disabled(saving || (text.trimmingCharacters(in: .whitespaces).isEmpty && photos.isEmpty))
                }
            }
            .saveErrorAlert($saveError)
            .confirmationDialog("Slet indlægget?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Slet", role: .destructive) {
                    Task {
                        await performSave(saving: $saving, errorMessage: $saveError, dismiss: dismiss) {
                            if let id = editing?.id { try await state.store.deleteDiary(childId: childId, id: id) }
                        }
                    }
                }
            } message: {
                Text("Indlægget og dets billeder slettes for hele familien.")
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let e = editing {
                    date = e.date ?? e.createdAt; text = e.text; photos = e.photos.photos; cover = e.photos.coverIndex
                } else if text.isEmpty {
                    text = initialText
                }
            }
        }
    }
}
