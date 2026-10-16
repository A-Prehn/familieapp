import SwiftUI

// Bruges til både "Maven måned for måned" og "Måned for måned".
struct GalleryView: View {
    @EnvironmentObject var state: AppState
    let child: Child
    let kind: GalleryKind
    @State private var items: [GalleryItem] = []
    @State private var showAdd = false
    @State private var editing: GalleryItem?
    @State private var lightbox: LightboxState?
    @State private var scanning = false
    @State private var scanError: String?

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        ScrollView {
            if items.isEmpty {
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
                TimelineView(items: items,
                             year: { Calendar.current.component(.year, from: $0.createdAt) }) { item in
                    timelineCard(item)
                }
                .padding(16)
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(items) { item in
                        cell(item)
                    }
                }
                .padding(16)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
        .fullScreenCover(item: $lightbox) { LightboxView(state: $0) }
        .refreshable { await load() }
        .task { await load() }
    }

    // Kort i tidslinjen: uge/måned som overskrift, billedet i portræt (maven fylder i højden).
    private func timelineCard(_ item: GalleryItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.caption.isEmpty ? Fmt.long(item.createdAt) : item.caption)
                .font(.serifTitle(16))
                .foregroundStyle(Theme.text)
            if !item.caption.isEmpty {
                Text(Fmt.long(item.createdAt)).font(.caption).foregroundStyle(Theme.muted)
            }
            if let photo = item.photo {
                Color.clear
                    .aspectRatio(ImageTools.displayAspect(photo), contentMode: .fit)
                    .overlay { DataImage(data: photo) }
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
            if !item.caption.isEmpty {
                Text(item.caption)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.text)
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
        let withPhotos = items.filter { $0.photo != nil }
        let photos = withPhotos.compactMap { $0.photo }
        guard !photos.isEmpty else { return }
        let index = withPhotos.firstIndex(where: { $0.id == item.id }) ?? 0
        lightbox = LightboxState(photos: photos, index: index)
    }

    private func load() async {
        items = (try? await state.store.gallery(childId: child.id, kind: kind)) ?? []
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
    @State private var caption = ""
    @State private var photo: Data?
    @State private var saving = false
    @State private var saveError: String?
    @State private var savedFor: Set<String> = []   // ved fejl midt i flere børn: undgå dubletter ved nyt forsøg
    @State private var loaded = false
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                ForChildrenNote(names: forNames)
                Section(kind.captionLabel) {
                    TextField(kind.captionPlaceholder, text: $caption)
                }
                Section("Billede") {
                    PhotoField(data: $photo)
                }
                if editing != nil {
                    Section {
                        Button("Slet foto", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(editing == nil ? "Nyt foto" : "Redigér foto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annullér") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gem") {
                        Task {
                            await performSave(saving: $saving, errorMessage: $saveError, dismiss: dismiss) {
                                if var item = editing {
                                    item.caption = caption; item.photo = photo
                                    try await state.store.updateGalleryItem(childId: childId, item)
                                    return
                                }
                                if !savedFor.contains(childId) {
                                    _ = try await state.store.addGalleryItem(childId: childId, kind: kind, caption: caption, photo: photo)
                                    savedFor.insert(childId)
                                }
                                // Øvrige børn: "Maven måned for måned" hvis barnet er på vej, ellers "Måned for måned".
                                for other in alsoFor where !savedFor.contains(other.id) {
                                    _ = try await state.store.addGalleryItem(childId: other.id, kind: other.onTheWay ? .belly : .monthly,
                                                                             caption: caption, photo: photo)
                                    savedFor.insert(other.id)
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
                if let item = editing { caption = item.caption; photo = item.photo }
                else if caption.isEmpty { caption = defaultCaption }
            }
        }
    }
}
