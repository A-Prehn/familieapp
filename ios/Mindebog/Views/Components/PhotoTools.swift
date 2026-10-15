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

// Fuldskærms-visning med swipe mellem billeder.
struct LightboxState: Identifiable {
    let id = UUID()
    let photos: [Data]
    var index: Int = 0
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
