import SwiftUI
import PhotosUI
import UIKit

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
}

// Viser billeddata; fylder sin ramme.
struct DataImage: View {
    let data: Data
    var contentMode: ContentMode = .fill

    var body: some View {
        if let ui = UIImage(data: data) {
            Image(uiImage: ui)
                .resizable()
                .aspectRatio(contentMode: contentMode)
        } else {
            Theme.bgDark
        }
    }
}

// Foto-felt til formularer (vælg / skift / fjern).
struct PhotoField: View {
    @Binding var data: Data?
    var title: String = "Vælg billede"
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let data {
                DataImage(data: data, contentMode: .fit)
                    .frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            HStack {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label(data == nil ? title : "Vælg et andet", systemImage: "photo")
                }
                .buttonStyle(.borderless)
                if data != nil {
                    Spacer()
                    Button("Fjern", role: .destructive) { data = nil }
                        .buttonStyle(.borderless)
                }
            }
        }
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let raw = try? await newItem.loadTransferable(type: Data.self) {
                    data = ImageTools.resized(raw)
                }
                pickerItem = nil
            }
        }
    }
}

// Flere billeder (højdepunkter).
struct MultiPhotoField: View {
    @Binding var photos: [Data]
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(photos.indices, id: \.self) { index in
                DataImage(data: photos[index], contentMode: .fit)
                    .frame(maxHeight: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("Tilføj billede", systemImage: "photo.badge.plus")
            }
            .buttonStyle(.borderless)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Sikker opslag: når et billede slettes, kan SwiftUI kortvarigt tegne en række
            // med et indeks, der ikke længere findes — den springes så over i stedet for at crashe.
            ForEach(set.photos.indices, id: \.self) { index in
                if let photo = set.photos.indices.contains(index) ? set.photos[index] : nil {
                HStack(alignment: .top, spacing: 12) {
                    DataImage(data: photo)
                        .frame(width: 84, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
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
            PhotosPicker(selection: $pickerItems, maxSelectionCount: 20, matching: .images) {
                Label(set.isEmpty ? "Vælg billeder" : "Tilføj flere billeder", systemImage: "photo.badge.plus")
            }
            .buttonStyle(.borderless)
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
    var aspect: CGFloat = 4.0 / 3.0
    var cornerRadius: CGFloat = 8
    var showCaption = true
    let onOpen: (LightboxState) -> Void

    var body: some View {
        if let cover = set.coverPhoto {
            Color.clear
                .aspectRatio(aspect, contentMode: .fit)
                .overlay { DataImage(data: cover) }
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
                    onOpen(LightboxState(photos: set.photos, index: set.coverIndex,
                                         captions: set.photos.indices.map { set.caption(at: $0) }))
                }
        }
    }
}

// Fuldskærms-visning med swipe mellem billeder.
struct LightboxState: Identifiable {
    let id = UUID()
    let photos: [Data]
    var index: Int = 0
    var captions: [String] = []
}

struct LightboxView: View {
    let state: LightboxState
    @Environment(\.dismiss) private var dismiss
    @State private var index: Int

    init(state: LightboxState) {
        self.state = state
        _index = State(initialValue: state.index)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(state.photos.indices, id: \.self) { i in
                    DataImage(data: state.photos[i], contentMode: .fit)
                        .overlay(alignment: .bottom) {
                            if state.captions.indices.contains(i), !state.captions[i].isEmpty {
                                Text(state.captions[i])
                                    .font(.callout)
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 20)
                                    .padding(.bottom, 56)
                            }
                        }
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: state.photos.count > 1 ? .automatic : .never))
            .ignoresSafeArea()

            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.5))
                    .padding(16)
            }
        }
    }
}
