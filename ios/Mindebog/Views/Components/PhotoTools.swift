import SwiftUI
import PhotosUI
import Photos
import UIKit
import ImageIO

// Skalerer et valgt billede ned (≈ CKAsset-venligt) og gemmer som JPEG.
enum ImageTools {
    static func resized(_ data: Data, maxDimension: CGFloat = 1200) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        let scale = longest > 0 ? min(1, maxDimension / longest) : 1
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let output = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return output.jpegData(compressionQuality: 0.8)
    }

    /// Billedets egen form til visning på kort — så intet beskæres væk.
    /// Begrænset til mellem 3:4 (portræt) og 16:9 (landskab), så et meget højt
    /// billede ikke fylder hele skærmen. Læser kun målene — afkoder ikke billedet.
    static func displayAspect(_ data: Data) -> CGFloat {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? CGFloat,
              let h = props[kCGImagePropertyPixelHeight] as? CGFloat, h > 0 else { return 4.0 / 3.0 }
        // EXIF-rotation: ved 90°/270° er bredde og højde byttet om.
        let orientation = props[kCGImagePropertyOrientation] as? UInt32 ?? 1
        let ratio = (5...8).contains(orientation) ? h / w : w / h
        return min(max(ratio, 3.0 / 4.0), 16.0 / 9.0)
    }

    /// Hvornår billedet blev taget (fra billedets EXIF), hvis det står i filen.
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

    /// Miniature i visningsstørrelse. Afkoder kun det, der skal vises (ImageIO nedskalerer under
    /// afkodningen), og husker resultatet — så gitre og tidslinjer ruller glat.
    static func thumbnail(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        let key = "\(data.hashValue)_\(Int(maxPixel))" as NSString
        if let hit = thumbCache.object(forKey: key) { return hit }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return UIImage(data: data)
        }
        let image = UIImage(cgImage: cg)
        thumbCache.setObject(image, forKey: key, cost: cg.bytesPerRow * cg.height)
        return image
    }

    private static let thumbCache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.totalCostLimit = 120 * 1024 * 1024   // ~120 MB afkodede miniaturer
        return c
    }()
}

// Viser billeddata; fylder sin ramme. Afkodes som miniature (maxPixel) — nok til kort
// og gitre på en Retina-skærm. Fuld skærm sætter selv en højere grænse.
struct DataImage: View {
    let data: Data
    var contentMode: ContentMode = .fill
    var maxPixel: CGFloat = 800
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        if let ui = ImageTools.thumbnail(data, maxPixel: maxPixel) {
            Image(uiImage: ui)
                .resizable()
                .aspectRatio(contentMode: contentMode)
                // Billedet "fremkaldes" blidt i stedet for at hoppe på plads.
                .opacity(shown || reduceMotion ? 1 : 0)
                .onAppear { withAnimation(.easeOut(duration: 0.3)) { shown = true } }
        } else {
            Theme.bgDark
        }
    }
}

/// Billede der skal beskæres (index bruges når det er ét af flere).
struct CropTarget: Identifiable {
    let id = UUID()
    let image: UIImage
    var index: Int = 0
}

// Foto-felt til formularer (vælg / beskær / skift / fjern).
struct PhotoField: View {
    @Binding var data: Data?
    var title: String = "Vælg billede"
    /// Vis "Forslag" (de nyeste billeder fra Fotos) — slået fra fx til profilbilleder.
    var suggestions = true
    /// Periode, forslagene hentes fra (ellers de seneste 31 dage).
    var suggestRange: ClosedRange<Date>? = nil
    /// Kaldes med datoen, billedet blev taget (fra billedet selv), når der vælges et nyt.
    var onCaptureDate: ((Date) -> Void)? = nil
    @State private var pickerItem: PhotosPickerItem?
    @State private var cropping: CropTarget?
    @State private var showSuggestions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let data {
                DataImage(data: data, contentMode: .fit)
                    .frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.small))
            }
            HStack(spacing: 16) {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label(data == nil ? title : "Vælg et andet", systemImage: "photo")
                }
                .buttonStyle(.borderless)
                if suggestions && data == nil {
                    Button { showSuggestions = true } label: {
                        Label("Forslag", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderless)
                }
                if let data, let image = UIImage(data: data) {
                    Button { cropping = CropTarget(image: image) } label: {
                        Label("Beskær", systemImage: "crop")
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                    Button("Fjern", role: .destructive) { self.data = nil }
                        .buttonStyle(.borderless)
                }
            }
        }
        .fullScreenCover(item: $cropping) { target in
            CropView(image: target.image) { data = $0 }
        }
        .sheet(isPresented: $showSuggestions) {
            PhotoSuggestionsView(range: suggestRange, allowMultiple: false) { picked in data = picked.first }
        }
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let raw = try? await newItem.loadTransferable(type: Data.self) {
                    // Datoen læses før nedskalering (som fjerner billedets oplysninger).
                    if let taken = ImageTools.captureDate(raw) { onCaptureDate?(taken) }
                    data = ImageTools.resized(raw)
                }
                pickerItem = nil
            }
        }
    }
}

// Flere billeder (højdepunkter) — med fjern-knap på hvert billede.
struct MultiPhotoField: View {
    @Binding var photos: [Data]
    /// Forsidebilledet (vises på oversigten) — kun når feltet har fået en binding.
    var cover: Binding<Int>? = nil
    /// Periode, forslagene hentes fra (ellers de seneste 31 dage).
    var suggestRange: ClosedRange<Date>? = nil
    @State private var pickerItem: PhotosPickerItem?
    @State private var cropping: CropTarget?
    @State private var showSuggestions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(photos.indices, id: \.self) { index in
                // Sikker opslag, så en række med et netop slettet indeks ikke crasher.
                if let photo = photos.indices.contains(index) ? photos[index] : nil {
                    DataImage(data: photo, contentMode: .fit)
                        .frame(maxHeight: 180)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.small))
                        .overlay(alignment: .topLeading) {
                            // Forside: vises på oversigten. Tryk på stjernen for at vælge et andet billede.
                            if let cover, photos.count > 1 {
                                let isCover = index == (photos.indices.contains(cover.wrappedValue) ? cover.wrappedValue : 0)
                                Button { cover.wrappedValue = index } label: {
                                    Label(isCover ? "Forside" : "Brug som forside", systemImage: isCover ? "star.fill" : "star")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 8).padding(.vertical, 5)
                                        .background(Capsule().fill(isCover ? Theme.rose : .black.opacity(0.55)))
                                        .padding(6)
                                }
                                .buttonStyle(.borderless)
                                .disabled(isCover)
                            }
                        }
                        .overlay(alignment: .topTrailing) {
                            HStack(spacing: 0) {
                                Button {
                                    if let image = UIImage(data: photo) {
                                        cropping = CropTarget(image: image, index: index)
                                    }
                                } label: {
                                    Image(systemName: "crop")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .frame(width: 28, height: 28)
                                        .background(Circle().fill(.black.opacity(0.55)))
                                        .padding(6)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Beskær billede")
                                Button {
                                    if photos.indices.contains(index) {
                                        photos.remove(at: index)
                                        // Forsiden følger med, når et billede foran den slettes.
                                        if let cover, cover.wrappedValue > index { cover.wrappedValue -= 1 }
                                        else if let cover, cover.wrappedValue == index { cover.wrappedValue = 0 }
                                    }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title3)
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, .black.opacity(0.55))
                                        .padding(6)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Fjern billede")
                            }
                        }
                }
            }
            HStack(spacing: 16) {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("Tilføj billede", systemImage: "photo.badge.plus")
                }
                Button { showSuggestions = true } label: {
                    Label("Forslag", systemImage: "sparkles")
                }
            }
            .buttonStyle(.borderless)
        }
        .fullScreenCover(item: $cropping) { target in
            CropView(image: target.image) { cropped in
                if photos.indices.contains(target.index) { photos[target.index] = cropped }
            }
        }
        .sheet(isPresented: $showSuggestions) {
            PhotoSuggestionsView(range: suggestRange) { photos.append(contentsOf: $0) }
        }
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let raw = try? await newItem.loadTransferable(type: Data.self),
                   let resized = ImageTools.resized(raw) {
                    photos.append(resized)
                }
                pickerItem = nil
            }
        }
    }
}

// MARK: - Billedsæt (flere billeder, forside, billedtekst)

/// Formular-felt: tilføj flere billeder, vælg forside (★), skriv billedtekst, fjern.
struct PhotoSetEditor: View {
    @Binding var set: PhotoSet
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var cropping: CropTarget?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Sikker opslag: når et billede slettes, kan SwiftUI kortvarigt tegne en række
            // med et indeks, der ikke længere findes — den springes så over i stedet for at crashe.
            ForEach(set.photos.indices, id: \.self) { index in
                if let photo = set.photos.indices.contains(index) ? set.photos[index] : nil {
                HStack(alignment: .top, spacing: 12) {
                    DataImage(data: photo)
                        .frame(width: 84, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.small))
                        .overlay(alignment: .topLeading) {
                            if index == set.coverIndex {
                                Text("Forside")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Capsule().fill(Theme.rose))
                                    .padding(4)
                            }
                        }
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Billedtekst (valgfri)", text: Binding(
                            get: { set.caption(at: index) },
                            set: { set.setCaption($0, at: index) }))
                            .font(.footnote)
                        HStack(spacing: 16) {
                            Button {
                                set.cover = index
                            } label: {
                                Label(index == set.coverIndex ? "Forside" : "Brug som forside",
                                      systemImage: index == set.coverIndex ? "star.fill" : "star")
                                    .font(.footnote)
                            }
                            .tint(Theme.rose)
                            .disabled(index == set.coverIndex)
                            Spacer()
                            Button {
                                if let image = UIImage(data: photo) {
                                    cropping = CropTarget(image: image, index: index)
                                }
                            } label: {
                                Image(systemName: "crop")
                            }
                            .accessibilityLabel("Beskær billede")
                            Button(role: .destructive) {
                                set.remove(at: index)
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                }
                }
            }
            // Op til 100 ad gangen (#24) — og "Tilføj flere billeder" kan bruges igen, så der er reelt ingen grænse.
            PhotosPicker(selection: $pickerItems, maxSelectionCount: 100, matching: .images) {
                Label(set.isEmpty ? "Vælg billeder" : "Tilføj flere billeder", systemImage: "photo.badge.plus")
            }
            .buttonStyle(.borderless)
        }
        .fullScreenCover(item: $cropping) { target in
            CropView(image: target.image) { cropped in
                if set.photos.indices.contains(target.index) { set.photos[target.index] = cropped }
            }
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                for item in items {
                    if let raw = try? await item.loadTransferable(type: Data.self),
                       let resized = ImageTools.resized(raw) {
                        set.append(resized)
                    }
                }
                pickerItems = []
            }
        }
    }
}

/// Forsidebilledet med billedtekst nederst og "+N" for resten (som på websitet).
/// Tryk åbner alle billeder i fuld skærm, startende ved forsiden.
struct CoverPhotoView: View {
    let set: PhotoSet
    /// nil = billedets egen form (kort i tidslinjer); fast tal = ens felter (fx milepæls-gitteret).
    var aspect: CGFloat? = nil
    var cornerRadius: CGFloat = 8
    var showCaption = true
    /// Til zoom-overgangen: et id for kortet og den skærms namespace, der viser fuld skærm.
    var zoomId: String? = nil
    var zoomNamespace: Namespace.ID? = nil
    let onOpen: (LightboxState) -> Void

    var body: some View {
        if let cover = set.coverPhoto {
            Color.clear
                .aspectRatio(aspect ?? ImageTools.displayAspect(cover), contentMode: .fit)
                .overlay { DataImage(data: cover) }
                .modifier(OptionalZoomSource(id: zoomId, namespace: zoomNamespace))
                .overlay(alignment: .bottom) {
                    if showCaption && !set.coverCaption.isEmpty || set.count > 1 {
                        HStack(alignment: .bottom) {
                            if showCaption && !set.coverCaption.isEmpty {
                                Text(set.coverCaption)
                                    .font(.caption)
                                    .foregroundStyle(.white)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 4)
                            if set.count > 1 {
                                Text("+\(set.count - 1)")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(Capsule().fill(.black.opacity(0.55)))
                            }
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(
                            LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
                        )
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .contentShape(Rectangle())
                .onTapGesture {
                    onOpen(LightboxState.coverFirst(set, sourceId: zoomId))
                }
        }
    }
}

/// Zoom-kilde, der kun sættes, når både id og namespace er givet.
struct OptionalZoomSource: ViewModifier {
    let id: String?
    let namespace: Namespace.ID?
    func body(content: Content) -> some View {
        if let id, let namespace { content.zoomSource(id: id, in: namespace) } else { content }
    }
}

// Fuldskærms-visning med swipe mellem billeder.
struct LightboxState: Identifiable {
    let id = UUID()
    let photos: [Data]
    var index: Int = 0
    var captions: [String] = []
    /// Id på det billede, der blev trykket på — så fuld skærm kan "løfte sig" fra det (iOS 18).
    var sourceId: String? = nil

    /// Forsiden først, så resten i rækkefølge — så det valgte billede altid er det første, man ser.
    static func coverFirst(_ set: PhotoSet, sourceId: String? = nil) -> LightboxState {
        coverFirst(photos: set.photos, captions: set.photos.indices.map { set.caption(at: $0) },
                   cover: set.coverIndex, sourceId: sourceId)
    }

    static func coverFirst(photos: [Data], captions: [String] = [], cover: Int, sourceId: String? = nil) -> LightboxState {
        guard photos.indices.contains(cover), cover != 0 else {
            return LightboxState(photos: photos, index: 0, captions: captions, sourceId: sourceId)
        }
        let order = [cover] + photos.indices.filter { $0 != cover }
        let caps = captions.count == photos.count ? order.map { captions[$0] } : captions
        return LightboxState(photos: order.map { photos[$0] }, index: 0, captions: caps, sourceId: sourceId)
    }
}

struct LightboxView: View {
    let state: LightboxState
    @Environment(\.dismiss) private var dismiss
    @State private var index: Int

    init(state: LightboxState) {
        self.state = state
        _index = State(initialValue: state.index)
    }

    @State private var toast: String?
    /// Træk ned for at lukke (#21): hvor langt billedet er trukket, og om trækket er lodret.
    @State private var dragY: CGFloat = 0
    @State private var dragIsVertical: Bool?

    /// 0 → 1, mens man trækker ned; baggrunden toner ud, og billedet bliver lidt mindre.
    private var dragProgress: Double { Double(min(max(dragY, 0) / 300, 1)) }

    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                // Første bevægelse afgør retningen, så vandret swipe mellem billeder ikke lukker.
                if dragIsVertical == nil {
                    dragIsVertical = abs(value.translation.height) > abs(value.translation.width)
                }
                guard dragIsVertical == true else { return }
                dragY = max(value.translation.height, 0)
            }
            .onEnded { value in
                defer { dragIsVertical = nil }
                guard dragIsVertical == true else { return }
                // Luk ved et langt træk eller et hurtigt svirp nedad (forventet slutpunkt).
                if value.translation.height > 120 || value.predictedEndTranslation.height > 320 {
                    dismiss()
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { dragY = 0 }
                }
            }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(1 - dragProgress * 0.8).ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(state.photos.indices, id: \.self) { i in
                    // Teksten står under billedet på sort baggrund — oven på et lyst billede
                    // (fx en tegning på hvidt papir) kunne hvid tekst ikke læses.
                    VStack(spacing: 14) {
                        DataImage(data: state.photos[i], contentMode: .fit, maxPixel: 2400)
                            // Hold fingeren på billedet: Del, Gem i Fotos, Kopiér — som i Safari.
                            .contextMenu { photoActions(for: state.photos[i]) }
                        if state.captions.indices.contains(i), !state.captions[i].isEmpty {
                            Text(state.captions[i])
                                .font(.callout)
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 24)
                        }
                    }
                    .padding(.bottom, state.photos.count > 1 ? 44 : 20)   // plads til sideprikkerne
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: state.photos.count > 1 ? .automatic : .never))
            .ignoresSafeArea()
            .offset(y: dragY)
            .scaleEffect(CGFloat(1 - dragProgress * 0.15))
            .simultaneousGesture(dismissDrag)

            HStack {
                // Del-knap øverst til venstre, så funktionen kan findes uden at kende hold-menuen.
                if let image = currentImage {
                    ShareLink(item: Image(uiImage: image),
                              preview: SharePreview("Billede", image: Image(uiImage: image))) {
                        Image(systemName: "square.and.arrow.up.circle.fill")
                            .font(.system(size: 30))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.5))
                            .padding(16)
                    }
                    .accessibilityLabel("Del billede")
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 30))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.5))
                        .padding(16)
                }
                .accessibilityLabel("Luk")
            }
            .opacity(1 - dragProgress * 2)   // knapperne forsvinder, så snart man begynder at trække
            .allowsHitTesting(dragY == 0)

            if let toast {
                Text(toast)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(.black.opacity(0.7)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 90)
                    .transition(.opacity)
            }
        }
        // Gennemsigtig præsentation, så skærmen bag billedet kommer til syne, mens man trækker ned.
        .presentationBackground(.clear)
    }

    private var currentImage: UIImage? {
        guard state.photos.indices.contains(index) else { return nil }
        return UIImage(data: state.photos[index])
    }

    @ViewBuilder
    private func photoActions(for data: Data) -> some View {
        if let image = UIImage(data: data) {
            ShareLink(item: Image(uiImage: image),
                      preview: SharePreview("Billede", image: Image(uiImage: image))) {
                Label("Del…", systemImage: "square.and.arrow.up")
            }
            Button {
                Task { await saveToPhotos(image) }
            } label: {
                Label("Gem i Fotos", systemImage: "square.and.arrow.down")
            }
            Button {
                UIPasteboard.general.image = image
                show("Kopieret")
            } label: {
                Label("Kopiér", systemImage: "doc.on.doc")
            }
        }
    }

    /// Gemmer i Fotos med "kun tilføj"-adgang (appen kan ikke se brugerens øvrige billeder).
    private func saveToPhotos(_ image: UIImage) async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            show("Giv adgang i Indstillinger → Vores familie → Fotos")
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            show("Gemt i Fotos")
        } catch {
            show("Kunne ikke gemme billedet")
        }
    }

    private func show(_ message: String) {
        withAnimation { toast = message }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { if toast == message { toast = nil } }
        }
    }
}
