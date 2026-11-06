import Photos
import UIKit
import ImageIO

/// "Hent skarp udgave" (#69): til og med 1.3 blev billeder gemt i 1200 px. Ligger originalen stadig i
/// Fotos på denne telefon, findes den ud fra optagelsestiden (som vi bevarer i billedet) og samme form,
/// og gemmes igen i fuld størrelse (2560 px) — så hele familien får den skarpe udgave.
enum SharpOriginals {
    /// Mindre end det, appen gemmer i dag? Læser kun målene.
    static func isSoft(_ data: Data) -> Bool {
        (ImageTools.longestSide(data) ?? .infinity) < ImageTools.uploadPixels - 1
    }

    /// Originalen fra Fotos, klar til at gemme (nedskaleret til 2560 px). nil = ikke fundet her,
    /// ingen adgang til Fotos, eller billedet har ingen optagelsestid.
    static func find(for data: Data) async -> Data? {
        guard let taken = ImageTools.captureDate(data), let ratio = ratio(of: data) else { return nil }
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else { return nil }

        let options = PHFetchOptions()
        // Optagelsestiden i billedet er lokal tid uden tidszone. Er billedet taget (eller lagt op) i en anden
        // tidszone, ligger den hele kvarter forskudt fra Fotos' tidspunkt — så der søges et døgn rundt om, og
        // sekunderne skal passe på nær et helt antal kvarter.
        options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate <= %@",
                                        taken.addingTimeInterval(-14 * 3600 - 2) as NSDate,
                                        taken.addingTimeInterval(14 * 3600 + 2) as NSDate)
        let result = PHAsset.fetchAssets(with: .image, options: options)
        let size = Int(ImageTools.longestSide(data) ?? 0)
        var best: PHAsset?
        var bestOffset = TimeInterval.infinity
        result.enumerateObjects { asset, _, _ in
            guard asset.pixelHeight > 0, let created = asset.creationDate else { return }
            let offset = created.timeIntervalSince(taken)
            guard abs(offset - (offset / 900).rounded() * 900) <= 2 else { return }
            // Samme form (ellers er billedet beskåret i appen, og originalen ville fjerne beskæringen).
            let diff = abs(CGFloat(asset.pixelWidth) / CGFloat(asset.pixelHeight) - ratio)
            if diff < 0.02, max(asset.pixelWidth, asset.pixelHeight) > size, abs(offset) < bestOffset {
                best = asset
                bestOffset = abs(offset)
            }
        }
        guard let best else { return nil }

        let request = PHImageRequestOptions()
        request.isNetworkAccessAllowed = true   // originalen kan ligge i iCloud-fotos
        request.deliveryMode = .highQualityFormat
        request.version = .current
        let raw: Data? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(for: best, options: request) { data, _, _, _ in
                continuation.resume(returning: data)
            }
        }
        return raw.flatMap { ImageTools.resized($0) }
    }

    /// Bredde/højde som billedet vises (gemte billeder er tegnet om, så retningen ligger i pixelerne).
    private static func ratio(of data: Data) -> CGFloat? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? CGFloat,
              let h = props[kCGImagePropertyPixelHeight] as? CGFloat, h > 0 else { return nil }
        let orientation = props[kCGImagePropertyOrientation] as? UInt32 ?? 1
        return (5...8).contains(orientation) ? h / w : w / h
    }
}
