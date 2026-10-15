import SwiftUI

// Bruges til både "Maven måned for måned" og "Måned for måned".
struct GalleryView: View {
    @EnvironmentObject var state: AppState
    let child: Child
    let kind: GalleryKind
    @State private var items: [GalleryItem] = []
    @State private var showAdd = false
    @State private var lightbox: LightboxState?

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        ScrollView {
            if items.isEmpty {
                ContentUnavailableView("Ingen fotos endnu", systemImage: "photo.on.rectangle")
                    .padding(.top, 60)
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
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAdd, onDismiss: { Task { await load() } }) {
            AddGalleryItemView(childId: child.id, kind: kind)
        }
        .fullScreenCover(item: $lightbox) { LightboxView(state: $0) }
        .refreshable { await load() }
        .task { await load() }
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
            if !item.caption.isEmpty {
                Text(item.caption)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.sep))
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
    @State private var caption = ""
    @State private var photo: Data?
    @State private var saving = false
    @State private var saveError: String?
    @State private var savedFor: Set<String> = []   // ved fejl midt i flere børn: undgå dubletter ved nyt forsøg

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
            }
            .navigationTitle("Nyt foto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annullér") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gem") {
                        Task {
                            await performSave(saving: $saving, errorMessage: $saveError, dismiss: dismiss) {
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
        }
    }
}
