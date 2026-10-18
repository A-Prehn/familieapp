import SwiftUI

// Bruges til både "Maven måned for måned" og "Måned for måned".
struct GalleryView: View {
    @EnvironmentObject var state: AppState
    @Namespace private var zoomNS   // zoom-overgang til fuld skærm (iOS 18)
    let child: Child
    let kind: GalleryKind
    @State private var items: [GalleryItem] = []
    /// Serier, der vises med ældste først (standard er nyeste først). Gemt på telefonen.
    @AppStorage("mindebog.galleryOldestFirst") private var oldestFirstRaw = ""

    private var oldestFirst: Bool { oldestFirstRaw.split(separator: ",").contains(Substring(kind.rawValue)) }
    private func setOldestFirst(_ on: Bool) {
        var set = Set(oldestFirstRaw.split(separator: ",").map(String.init))
        if on { set.insert(kind.rawValue) } else { set.remove(kind.rawValue) }
        oldestFirstRaw = set.sorted().joined(separator: ",")
    }
    /// Billederne i den valgte rækkefølge.
    private var sorted: [GalleryItem] {
        items.sorted { oldestFirst ? $0.shownDate < $1.shownDate : $0.shownDate > $1.shownDate }
    }
    @State private var showAdd = false
    @State private var editing: GalleryItem?
    @State private var lightbox: LightboxState?
    @State private var scanning = false
    @State private var scanError: String?
    @State private var loading = true

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        ScrollView {
            if items.isEmpty && loading {
                ShimmerGrid(columns: kind == .belly ? 1 : 2)
            } else if items.isEmpty {
                if kind == .drawings {
                    ContentUnavailableView {
                        Label("Ingen tegninger endnu", systemImage: "paintpalette")
                    } description: {
                        Text("Scan en tegning med kameraet — appen finder selv kanterne og retter den op. Alderen sættes automatisk.")
                    } actions: {
                        if state.canEdit && DocumentScanner.isAvailable {
                            Button { scanning = true } label: { Label("Scan tegning", systemImage: "doc.viewfinder") }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.top, 60)
                } else {
                    ContentUnavailableView("Ingen fotos endnu", systemImage: "photo.on.rectangle")
                        .padding(.top, 60)
                }
            } else if kind == .belly {
                // Maven: tidslinje i rækkefølge (første uge øverst), så man kan se maven vokse.
                TimelineView(items: sorted,
                             year: { Calendar.current.component(.year, from: $0.shownDate) }) { item in
                    timelineCard(item)
                }
                .padding(16)
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { i, item in
                        cell(item).softAppear(index: i)
                    }
                }
                .padding(16)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker("Rækkefølge", selection: Binding(get: { oldestFirst }, set: { setOldestFirst($0) })) {
                        Label("Nyeste først", systemImage: "arrow.down").tag(false)
                        Label("Ældste først", systemImage: "arrow.up").tag(true)
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .accessibilityLabel("Rækkefølge")
            }
            ToolbarItem(placement: .topBarTrailing) {
                if state.canEdit {
                    if kind == .drawings && DocumentScanner.isAvailable {
                        Menu {
                            Button { scanning = true } label: { Label("Scan med kameraet", systemImage: "doc.viewfinder") }
                            Button { showAdd = true } label: { Label("Vælg billede", systemImage: "photo") }
                        } label: { Image(systemName: "plus") }
                    } else {
                        Button { showAdd = true } label: { Image(systemName: "plus") }
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $scanning) {
            DocumentScanner { pages in
                guard !pages.isEmpty else { return }
                Task { await saveScans(pages) }
            }
            .ignoresSafeArea()
        }
        .saveErrorAlert($scanError)
        .sheet(isPresented: $showAdd, onDismiss: { Task { await load() } }) {
            AddGalleryItemView(childId: child.id, kind: kind, defaultCaption: kind == .drawings ? ChildAge.short(child) : "")
        }
        .sheet(item: $editing, onDismiss: { Task { await load() } }) { item in
            AddGalleryItemView(childId: child.id, kind: kind, editing: item)
        }
        .fullScreenCover(item: $lightbox) { LightboxView(state: $0).zoomTarget(id: $0.sourceId, in: zoomNS) }
        .refreshable { await load() }
        .task { await load() }
        .reloadOnStoreChange { await load() }
    }

    // Kort i tidslinjen: uge/måned som overskrift, billedet i portræt (maven fylder i højden).
    private func timelineCard(_ item: GalleryItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Uge/måned og så kommentaren efter, fx "Uge 24 · Første spark i dag".
            (Text(item.caption.isEmpty ? Fmt.long(item.shownDate) : item.caption)
                .font(.serifTitle(16))
                .foregroundStyle(Theme.text)
             + Text(item.note.isEmpty ? "" : "  ·  \(item.note)")
                .font(.system(size: 15))
                .foregroundStyle(Theme.neutralDark))
            if !item.caption.isEmpty {
                Text(Fmt.long(item.shownDate)).font(.caption).foregroundStyle(Theme.muted)
            }
            if let photo = item.photo {
                Color.clear
                    .aspectRatio(ImageTools.displayAspect(photo), contentMode: .fit)
                    .overlay { DataImage(data: photo) }
                    .zoomSource(id: item.id, in: zoomNS)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onTapGesture { openLightbox(at: item) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.sep))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture { if state.canEdit { editing = item } }
        .contextMenu {
            Button { if state.canEdit { editing = item } } label: { Label("Redigér", systemImage: "pencil") }
        }
    }

    private func cell(_ item: GalleryItem) -> some View {
        VStack(spacing: 0) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let photo = item.photo {
                        DataImage(data: photo)
                    } else {
                        Theme.bgDark
                    }
                }
                .clipped()
                .zoomSource(id: item.id, in: zoomNS)
                .contentShape(Rectangle())
                .onTapGesture { openLightbox(at: item) }
                // Lille blyant: redigér tekst/billede (tryk på selve billedet = fuld skærm).
                .overlay(alignment: .topTrailing) {
                    if state.canEdit {
                        Button { editing = item } label: {
                            Image(systemName: "pencil.circle.fill")
                                .font(.title3)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.45))
                                .padding(6)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Redigér")
                    }
                }
            if !item.caption.isEmpty || (kind != .drawings && !item.note.isEmpty) {
                // Tegninger: beskrivelsen vises kun i fuld skærm. Andre serier: efter måneden.
                (Text(item.caption)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.text)
                 + Text(kind == .drawings || item.note.isEmpty ? "" : (item.caption.isEmpty ? "" : " · ") + item.note)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted))
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .contentShape(Rectangle())
                    .onTapGesture { if state.canEdit { editing = item } }
            }
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.sep))
        .contextMenu {
            Button { if state.canEdit { editing = item } } label: { Label("Redigér", systemImage: "pencil") }
        }
    }

    private func openLightbox(at item: GalleryItem) {
        let withPhotos = sorted.filter { $0.photo != nil }
        let photos = withPhotos.compactMap { $0.photo }
        guard !photos.isEmpty else { return }
        let index = withPhotos.firstIndex(where: { $0.id == item.id }) ?? 0
        // Tegninger: beskrivelsen vises kun her, i fuld skærm.
        let captions = withPhotos.map { $0.note.isEmpty ? $0.caption : ($0.caption.isEmpty ? $0.note : "\($0.caption) · \($0.note)") }
        lightbox = LightboxState(photos: photos, index: index, captions: captions, sourceId: item.id)
    }

    private func load() async {
        defer { loading = false }
        // Vis det, der blev vist sidst, med det samme — og hent så det nye fra iCloud.
        let cacheKey = "gallery_\(child.id)_\(kind.rawValue)"
        if items.isEmpty, let cached = ScreenCache.load([GalleryItem].self, key: cacheKey) { items = cached }
        if let fresh = try? await state.store.gallery(childId: child.id, kind: kind) {
            items = fresh
            ScreenCache.save(fresh, key: cacheKey)
        }
    }

    /// Scannede tegninger gemmes med det samme; billedteksten er barnets alder (kan rettes bagefter).
    private func saveScans(_ pages: [Data]) async {
        let caption = ChildAge.short(child)
        do {
            for page in pages {
                _ = try await state.store.addGalleryItem(childId: child.id, kind: .drawings, caption: caption, photo: page)
            }
        } catch {
            scanError = "Kunne ikke gemme tegningen: \(error.localizedDescription)"
        }
        await load()
    }
}

struct AddGalleryItemView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let childId: String
    /// Øvrige børn samme indlæg også gemmes for (hurtig-tilføj på Hjem med flere børn valgt).
    var alsoFor: [Child] = []
    /// Navne vist øverst i formularen, når der gemmes for flere børn.
    var forNames: [String] = []
    let kind: GalleryKind
    /// Sat ved redigering; nil ved oprettelse.
    var editing: GalleryItem? = nil
    /// Forudfyldt billedtekst ved oprettelse (fx barnets alder til en tegning).
    var defaultCaption = ""

    private var notePlaceholder: String {
        switch kind {
        case .belly: return "Fx \"Første spark i dag\""
        case .monthly: return "Fx \"Har lært at vinke\""
        case .drawings: return "Fx \"Tegnet til mormors fødselsdag — det er vores hus med regnbue\""
        case .birthday: return "Fx \"Pakker op med mormor\""
        }
    }
    @State private var caption = ""
    @State private var note = ""
    @State private var date = Date()
    @State private var photo: Data?
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
                Section(kind.captionLabel) {
                    TextField(kind.captionPlaceholder, text: $caption)
                }
                Section {
                    DatePicker("Dato", selection: $date, in: ...Date(), displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "da_DK"))
                } footer: {
                    Text("Hvornår billedet er fra. Vælger du et billede fra Fotos, sættes datoen automatisk til den dag, det blev taget.")
                }
                Section {
                    TextField(notePlaceholder, text: $note, axis: .vertical)
                        .lineLimit(2...5)
                } header: {
                    Text(kind == .drawings ? "Beskrivelse (valgfri)" : "Kommentar (valgfri)")
                } footer: {
                    Text(kind == .drawings ? "Vises, når man trykker på tegningen."
                         : kind == .birthday ? "Vises, når man trykker på billedet. Alderen bestemmer, hvilken fødselsdag billedet hører til."
                         : "Vises efter \(kind == .belly ? "ugen" : "måneden") på oversigten.")
                }
                Section("Billede") {
                    // Forslag fra ugerne omkring den valgte dato.
                    PhotoField(data: $photo, suggestRange: .around(date, days: 14), onCaptureDate: { date = $0 })
                }
                if editing != nil {
                    Section {
                        Button("Slet foto", role: .destructive) { confirmDelete = true }
                    }
                }
                }.listRowBackground(Theme.card)
            }
            .themedList()
            .navigationTitle(editing == nil ? "Nyt foto" : "Redigér foto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annullér") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gem") {
                        if var item = editing {
                            item.caption = caption; item.photo = photo; item.note = note; item.date = date
                            let updated = item
                            Task {
                                await performSave(saving: $saving, errorMessage: $saveError, dismiss: dismiss) {
                                    try await state.store.updateGalleryItem(childId: childId, updated)
                                }
                            }
                        } else {
                            // Nyt foto: luk med det samme, upload i baggrunden.
                            let (store, childId, kind, caption, note, photo, others) = (state.store, childId, kind, caption, note, photo, alsoFor)
                            // Datoen gemmes kun, hvis den ikke er i dag (så er "lagt op" den samme dag).
                            let chosen: Date? = Calendar.current.isDateInToday(date) ? nil : date
                            performSaveInBackground(label: "fotoet", dismiss: dismiss) {
                                var created = try await store.addGalleryItem(childId: childId, kind: kind, caption: caption, photo: photo)
                                if !note.isEmpty || chosen != nil {
                                    created.note = note
                                    created.date = chosen
                                    try await store.updateGalleryItem(childId: childId, created)
                                }
                                // Øvrige børn: "Maven måned for måned" hvis barnet er på vej, ellers "Måned for måned".
                                for other in others {
                                    var extra = try await store.addGalleryItem(childId: other.id, kind: other.onTheWay ? .belly : .monthly,
                                                                               caption: caption, photo: photo)
                                    if chosen != nil {
                                        extra.date = chosen
                                        try await store.updateGalleryItem(childId: other.id, extra)
                                    }
                                }
                            }
                        }
                    }
                    .disabled(saving || photo == nil)
                }
            }
            .saveErrorAlert($saveError)
            .confirmationDialog("Slet fotoet?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Slet", role: .destructive) {
                    Task {
                        await performSave(saving: $saving, errorMessage: $saveError, dismiss: dismiss) {
                            if let id = editing?.id { try await state.store.deleteGalleryItem(childId: childId, id: id) }
                        }
                    }
                }
            } message: {
                Text("Fotoet slettes for hele familien.")
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let item = editing { caption = item.caption; photo = item.photo; note = item.note; date = item.shownDate }
                else if caption.isEmpty { caption = defaultCaption }
            }
        }
    }
}
