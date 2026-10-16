import SwiftUI
import Photos

// "Forslag fra Fotos": de nyeste billeder i brugerens fotobibliotek, så man vælger
// i stedet for at lede. Kræver læseadgang til Fotos (også "Udvalgte billeder" virker).
struct PhotoSuggestionsView: View {
    @Environment(\.dismiss) private var dismiss
    /// Hvor mange dage tilbage der foreslås fra.
    var days: Int = 31
    var allowMultiple = true
    var onPick: ([Data]) -> Void

    @State private var status: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @State private var assets: [PHAsset] = []
    @State private var selected: [String] = []
    @State private var loading = false

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 4)]

    var body: some View {
        NavigationStack {
            Group {
                if status == .authorized || status == .limited {
                    if assets.isEmpty {
                        ContentUnavailableView("Ingen billeder fra de sidste \(days) dage", systemImage: "photo")
                    } else {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 4) {
                                ForEach(assets, id: \.localIdentifier) { asset in
                                    AssetThumb(asset: asset, selected: selected.contains(asset.localIdentifier))
                                        .onTapGesture { toggle(asset) }
                                }
                            }
                            .padding(4)
                            if status == .limited {
                                Button("Vælg flere billeder, appen må se") {
                                    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                                       let vc = scene.windows.first?.rootViewController {
                                        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: vc)
                                    }
                                }
                                .font(.footnote).padding()
                            }
                        }
                    }
                } else if status == .notDetermined {
                    ProgressView().task {
                        status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
                        await load()
                    }
                } else {
                    ContentUnavailableView {
                        Label("Ingen adgang til Fotos", systemImage: "lock")
                    } description: {
                        Text("Giv adgang under Indstillinger → Vores familie → Fotos for at få forslag.")
                    } actions: {
                        Button("Åbn Indstillinger") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    }
                }
            }
            .navigationTitle("Forslag fra Fotos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annullér") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(loading ? "Henter…" : (selected.count > 1 ? "Brug \(selected.count)" : "Brug")) {
                        Task { await finish() }
                    }
                    .disabled(selected.isEmpty || loading)
                }
            }
            .task { if status == .authorized || status == .limited { await load() } }
        }
    }

    private func toggle(_ asset: PHAsset) {
        let id = asset.localIdentifier
        if let i = selected.firstIndex(of: id) { selected.remove(at: i) }
        else if allowMultiple { selected.append(id) }
        else { selected = [id] }
    }

    private func load() async {
        let options = PHFetchOptions()
        let since = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        options.predicate = NSPredicate(format: "mediaType == %d AND creationDate >= %@", PHAssetMediaType.image.rawValue, since as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 300
        let result = PHAsset.fetchAssets(with: options)
        var list: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in list.append(asset) }
        assets = list
    }

    private func finish() async {
        loading = true
        defer { loading = false }
        var out: [Data] = []
        for id in selected {
            guard let asset = assets.first(where: { $0.localIdentifier == id }) else { continue }
            if let data = await Self.fullImage(asset) { out.append(ImageTools.resized(data) ?? data) }
        }
        onPick(out)
        dismiss()
    }

    private static func fullImage(_ asset: PHAsset) async -> Data? {
        await withCheckedContinuation { cont in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true     // også billeder, der kun ligger i iCloud
            options.deliveryMode = .highQualityFormat
            options.version = .current
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                cont.resume(returning: data)
            }
        }
    }
}

/// Miniature af ét billede i biblioteket.
private struct AssetThumb: View {
    let asset: PHAsset
    let selected: Bool
    @State private var image: UIImage?

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image { Image(uiImage: image).resizable().scaledToFill() } else { Theme.bgDark }
            }
            .clipped()
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Theme.tint)
                        .padding(6)
                }
            }
            .overlay { if selected { Rectangle().stroke(Theme.tint, lineWidth: 3) } }
            .task(id: asset.localIdentifier) {
                let options = PHImageRequestOptions()
                options.isNetworkAccessAllowed = true
                options.deliveryMode = .opportunistic
                let size = CGSize(width: 300, height: 300)
                PHImageManager.default().requestImage(for: asset, targetSize: size, contentMode: .aspectFill,
                                                      options: options) { img, _ in
                    if let img { Task { @MainActor in image = img } }
                }
            }
    }
}
