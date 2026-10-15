import SwiftUI
import CoreImage.CIFilterBuiltins

// QR-kode af en tekst (delelinket). Partneren scanner med iPhonens kamera,
// som åbner linket — præcis som hvis det var sendt i en besked.
struct QRCodeView: View {
    let text: String

    var body: some View {
        if let image = Self.make(text) {
            Image(uiImage: image)
                .interpolation(.none)   // skarpe kanter, ellers bliver koden sløret
                .resizable()
                .scaledToFit()
                .padding(12)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("QR-kode med delelink")
        }
    }

    private static func make(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
