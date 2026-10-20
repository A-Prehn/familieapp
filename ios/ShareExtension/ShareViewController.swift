import UIKit
import SwiftUI
import UniformTypeIdentifiers
import ImageIO

// "Del → Vores familie" fra Fotos (eller en anden app): vælg barnet, skriv en linje, gem.
// Billederne lægges i indbakken (ShareInbox) og bliver til et højdepunkt, næste gang appen åbnes.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let model = ShareModel(items: extensionContext?.inputItems as? [NSExtensionItem] ?? [])
        model.finish = { [weak self] in self?.extensionContext?.completeRequest(returningItems: nil) }
        model.cancel = { [weak self] in
            self?.extensionContext?.cancelRequest(withError: NSError(domain: "VoresFamilie", code: 0))
        }
        let host = UIHostingController(rootView: ShareView(model: model))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        Task { await model.load() }
    }
}

@MainActor
final class ShareModel: ObservableObject {
    struct Kid: Identifiable, Hashable { let id: String; let name: String }

    @Published var photos: [Data] = []
    @Published var thumbs: [UIImage] = []
    @Published var kids: [Kid] = []
    @Published var selected: Set<String> = []
    @Published var text = ""
    @Published var loading = true
    @Published var error: String?
    var date: Date?
    var finish: () -> Void = {}
    var cancel: () -> Void = {}
    private let items: [NSExtensionItem]
    static let maxPhotos = 20

    init(items: [NSExtensionItem]) {
        self.items = items
        // Børnene skrives af appen til App Group'en (SharedNames), når Hjem indlæses.
        kids = SharedNames.children.map { Kid(id: $0.key, name: $0.value) }.sorted { $0.name < $1.name }
        if kids.count == 1 { selected = [kids[0].id] }
    }

    func load() async {
        defer { loading = false }
        let providers = items.flatMap { $0.attachments ?? [] }
            .filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }
            .prefix(Self.maxPhotos)
        var dates: [Date] = []
        for provider in providers {
            // Ét billede ad gangen og straks nedskaleret — udvidelser har kun lidt hukommelse.
            guard let raw = await Self.loadData(provider) else { continue }
            if let d = Self.captureDate(raw) { dates.append(d) }
            guard let small = Self.resized(raw, maxDimension: 1600) else { continue }
            photos.append(small)
            if let t = Self.resized(raw, maxDimension: 240).flatMap(UIImage.init(data:)) { thumbs.append(t) }
        }
        date = dates.min()
        if photos.isEmpty { error = "Der var ingen billeder at gemme." }
    }

    func save() {
        guard !selected.isEmpty, !photos.isEmpty else { return }
        do {
            try ShareInbox.add(childIds: Array(selected), text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                               date: date, photos: photos)
            finish()
        } catch {
            self.error = "Kunne ikke gemme: \(error.localizedDescription)"
        }
    }

    // MARK: Billeder
    private static func loadData(_ provider: NSItemProvider) async -> Data? {
        await withCheckedContinuation { cont in
            _ = provider.loadDataRepresentation(for: .image) { data, _ in cont.resume(returning: data) }
        }
    }

    static func captureDate(_ data: Data) -> Date? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        guard let raw = (exif?[kCGImagePropertyExifDateTimeOriginal] ?? tiff?[kCGImagePropertyTIFFDateTime]) as? String else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return f.date(from: raw)
    }

    /// Nedskalerer under afkodningen (ImageIO), så et 48-megapixel-billede ikke fylder hukommelsen.
    static func resized(_ data: Data, maxDimension: CGFloat) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg).jpegData(compressionQuality: 0.85)
    }
}

struct ShareView: View {
    @ObservedObject var model: ShareModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if model.loading {
                        HStack { ProgressView(); Text("Henter billeder…").foregroundStyle(.secondary) }
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(Array(model.thumbs.enumerated()), id: \.offset) { _, img in
                                    Image(uiImage: img).resizable().scaledToFill()
                                        .frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                    }
                } footer: {
                    if !model.loading { Text("\(model.photos.count) \(model.photos.count == 1 ? "billede" : "billeder") bliver til et højdepunkt.") }
                }

                if model.kids.isEmpty {
                    Section {
                        Text("Åbn Vores familie én gang, så den kender jeres børn. Prøv så at dele igen.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Hvem handler det om?") {
                        ForEach(model.kids) { kid in
                            Button {
                                if model.selected.contains(kid.id) { model.selected.remove(kid.id) } else { model.selected.insert(kid.id) }
                            } label: {
                                HStack {
                                    Text(kid.name).foregroundStyle(.primary)
                                    Spacer()
                                    if model.selected.contains(kid.id) { Image(systemName: "checkmark").foregroundStyle(.tint) }
                                }
                            }
                        }
                    }
                    Section {
                        TextField("Hvad skete der?", text: $model.text, axis: .vertical).lineLimit(2...5)
                    } footer: {
                        Text("Gemmes i jeres iCloud, næste gang du åbner Vores familie.")
                    }
                }

                if let error = model.error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Vores familie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annullér") { model.cancel() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gem") { model.save() }
                        .disabled(model.loading || model.selected.isEmpty || model.photos.isEmpty)
                }
            }
        }
    }
}
