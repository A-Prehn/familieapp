import SwiftUI
import UIKit

// Beskær et billede: træk og knib billedet på plads i en ramme (4:3, kvadrat eller portræt),
// som i Fotos-appen. Resultatet gemmes som nyt JPEG (samme størrelsesgrænse som ellers).

enum CropShape: String, CaseIterable, Identifiable {
    case landscape = "4:3"
    case square = "Kvadrat"
    case portrait = "Portræt"
    var id: String { rawValue }

    /// bredde / højde
    var ratio: CGFloat {
        switch self {
        case .landscape: return 4.0 / 3.0
        case .square: return 1
        case .portrait: return 4.0 / 5.0
        }
    }
}

struct CropView: View {
    let image: UIImage
    let onDone: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var shape: CropShape = .landscape
    @State private var scale: CGFloat = 1          // zoom ud over "fyld rammen"
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                GeometryReader { geo in
                    let frame = frameSize(in: geo.size)
                    let base = baseScale(for: frame)
                    let shown = CGSize(width: image.size.width * base * scale,
                                       height: image.size.height * base * scale)
                    ZStack {
                        Color.black
                        Image(uiImage: image)
                            .resizable()
                            .frame(width: shown.width, height: shown.height)
                            .offset(offset)
                        // Mørk maske uden for rammen + hvid kant.
                        Rectangle()
                            .fill(.black.opacity(0.55))
                            .reverseMask {
                                Rectangle().frame(width: frame.width, height: frame.height)
                            }
                            .allowsHitTesting(false)
                        Rectangle()
                            .strokeBorder(.white, lineWidth: 1.5)
                            .frame(width: frame.width, height: frame.height)
                            .allowsHitTesting(false)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .contentShape(Rectangle())
                    .gesture(
                        SimultaneousGesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    scale = max(1, min(lastScale * value, 6))
                                    offset = clamp(offset, frame: frame, base: base)
                                }
                                .onEnded { _ in
                                    lastScale = scale
                                    lastOffset = offset
                                },
                            DragGesture()
                                .onChanged { value in
                                    let proposed = CGSize(width: lastOffset.width + value.translation.width,
                                                          height: lastOffset.height + value.translation.height)
                                    offset = clamp(proposed, frame: frame, base: base)
                                }
                                .onEnded { _ in lastOffset = offset }
                        )
                    )
                    .onChange(of: shape) { _, _ in reset() }
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Brug") {
                                if let data = crop(frame: frame, base: base) { onDone(data) }
                                dismiss()
                            }
                        }
                    }
                }

                Picker("Form", selection: $shape) {
                    ForEach(CropShape.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                Text("Træk og knib for at placere billedet i rammen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
            }
            .navigationTitle("Beskær")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annullér") { dismiss() } }
            }
        }
    }

    // Rammen: så stor som muligt med luft rundt om, i den valgte form.
    private func frameSize(in area: CGSize) -> CGSize {
        let maxW = area.width - 32, maxH = area.height - 32
        let ratio = shape.ratio
        return maxW / ratio <= maxH
            ? CGSize(width: maxW, height: maxW / ratio)
            : CGSize(width: maxH * ratio, height: maxH)
    }

    // Skala hvor billedet netop fylder rammen.
    private func baseScale(for frame: CGSize) -> CGFloat {
        guard image.size.width > 0, image.size.height > 0 else { return 1 }
        return max(frame.width / image.size.width, frame.height / image.size.height)
    }

    // Billedet må ikke flyttes så rammen får tomme kanter.
    private func clamp(_ proposed: CGSize, frame: CGSize, base: CGFloat) -> CGSize {
        let shownW = image.size.width * base * scale
        let shownH = image.size.height * base * scale
        let maxX = max(0, (shownW - frame.width) / 2)
        let maxY = max(0, (shownH - frame.height) / 2)
        return CGSize(width: min(max(proposed.width, -maxX), maxX),
                      height: min(max(proposed.height, -maxY), maxY))
    }

    private func reset() {
        scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero
    }

    // Omsæt rammen til et udsnit af billedet og tegn det som nyt billede.
    private func crop(frame: CGSize, base: CGFloat) -> Data? {
        let total = base * scale
        // Rammens øverste venstre hjørne i billedets koordinater (punkter).
        let originX = (image.size.width * total - frame.width) / 2 - offset.width
        let originY = (image.size.height * total - frame.height) / 2 - offset.height
        let rect = CGRect(x: originX / total, y: originY / total,
                          width: frame.width / total, height: frame.height / total)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let output = UIGraphicsImageRenderer(size: rect.size, format: format).image { _ in
            image.draw(at: CGPoint(x: -rect.origin.x, y: -rect.origin.y))
        }
        guard let jpeg = output.jpegData(compressionQuality: 0.9) else { return nil }
        return ImageTools.resized(jpeg)   // samme maks-størrelse som andre billeder
    }
}

private extension View {
    /// Maske med "hul": viser alt undtagen det givne indhold.
    func reverseMask<Mask: View>(@ViewBuilder _ mask: () -> Mask) -> some View {
        self.mask {
            Rectangle()
                .overlay { mask().blendMode(.destinationOut) }
                .compositingGroup()
        }
    }
}
