import UIKit
import AVFoundation

// Laver en lille film af en billedserie (fx "Måned for måned"): titelkort med barnets navn,
// hvert billede i et par sekunder med en blød overgang og billedteksten nederst. Alt sker
// lokalt på telefonen med AVAssetWriter — ingen server. Resultatet er en MP4, man kan dele
// eller gemme i Fotos.
enum MovieMaker {
    struct Frame {
        let photo: Data
        let caption: String
        let subtitle: String
    }

    private static let size = CGSize(width: 1080, height: 1350)   // 4:5 — fylder godt på en telefon
    private static let fps: Int32 = 30
    private static let holdSeconds = 2.2
    private static let fadeSeconds = 0.5

    static func make(title: String, subtitle: String, frames: [Frame]) async throws -> URL {
        let url = MediaFiles.newURL("mp4")
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 6_000_000],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)

        // Kortene tegnes først, når de skal bruges (kun det aktuelle og det næste er i hukommelsen ad gangen) —
        // 50 færdigtegnede kort ville fylde flere hundrede MB.
        let photoFrames = frames.filter { UIImage(data: $0.photo) != nil }
        let cardCount = photoFrames.count + 2
        func renderCard(_ i: Int) -> CGImage {
            if i == 0 { return renderTitle(title, subtitle: subtitle) }
            if i == cardCount - 1 { return renderTitle("Vores familie", subtitle: "") }
            let f = photoFrames[i - 1]
            return renderPhoto(UIImage(data: f.photo)!, caption: f.caption, subtitle: f.subtitle)
        }

        var frameIndex: Int64 = 0
        func append(_ image: CGImage, blendingTo next: CGImage?, progress: Double) async throws {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            guard let pool = adaptor.pixelBufferPool else { throw CocoaError(.fileWriteUnknown) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { throw CocoaError(.fileWriteUnknown) }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: Int(size.width), height: Int(size.height),
                                   bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                   space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) {
                let rect = CGRect(origin: .zero, size: size)
                ctx.draw(image, in: rect)
                if let next, progress > 0 {
                    ctx.setAlpha(CGFloat(progress))
                    ctx.draw(next, in: rect)
                }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            let time = CMTime(value: frameIndex, timescale: fps)
            if !adaptor.append(buffer, withPresentationTime: time) { throw writer.error ?? CocoaError(.fileWriteUnknown) }
            frameIndex += 1
        }

        let hold = Int(holdSeconds * Double(fps))
        let fade = Int(fadeSeconds * Double(fps))
        var card = renderCard(0)
        for i in 0..<cardCount {
            for _ in 0..<hold { try await append(card, blendingTo: nil, progress: 0) }
            if i + 1 < cardCount {
                let next = renderCard(i + 1)
                for f in 0..<fade { try await append(card, blendingTo: next, progress: Double(f + 1) / Double(fade)) }
                card = next
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        return url
    }

    // MARK: Tegning af kort

    private static let paper = UIColor(red: 0.980, green: 0.973, blue: 0.957, alpha: 1)
    private static let ink = UIColor(red: 0.173, green: 0.157, blue: 0.125, alpha: 1)
    private static let muted = UIColor(red: 0.541, green: 0.510, blue: 0.470, alpha: 1)

    private static func renderTitle(_ title: String, subtitle: String) -> CGImage {
        render { ctx in
            paper.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            draw(title, font: serif(72), color: ink, y: size.height * 0.44, maxWidth: size.width - 160)
            draw(subtitle, font: sans(36), color: muted, y: size.height * 0.44 + 110, maxWidth: size.width - 160)
        }
    }

    private static func renderPhoto(_ image: UIImage, caption: String, subtitle: String) -> CGImage {
        render { ctx in
            paper.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            // Billedet fylder bredden med samme form som originalen, lodret centreret over teksten.
            let maxW = size.width - 80
            let maxH = size.height - 320
            let scale = min(maxW / image.size.width, maxH / image.size.height)
            let w = image.size.width * scale, h = image.size.height * scale
            let rect = CGRect(x: (size.width - w) / 2, y: 60 + (maxH - h) / 2, width: w, height: h)
            UIBezierPath(roundedRect: rect, cornerRadius: 24).addClip()
            image.draw(in: rect)
            ctx.resetClip()
            draw(caption, font: serif(56), color: ink, y: size.height - 200, maxWidth: size.width - 120)
            draw(subtitle, font: sans(32), color: muted, y: size.height - 120, maxWidth: size.width - 120)
        }
    }

    private static func render(_ body: (CGContext) -> Void) -> CGImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in body(ctx.cgContext) }
        return image.cgImage!
    }

    private static func draw(_ text: String, font: UIFont, color: UIColor, y: CGFloat, maxWidth: CGFloat) {
        guard !text.isEmpty else { return }
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byWordWrapping
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: style]
        let bounds = (text as NSString).boundingRect(with: CGSize(width: maxWidth, height: 400),
                                                     options: [.usesLineFragmentOrigin], attributes: attrs, context: nil)
        (text as NSString).draw(in: CGRect(x: (size.width - maxWidth) / 2, y: y, width: maxWidth, height: ceil(bounds.height) + 4),
                                withAttributes: attrs)
    }

    private static func serif(_ size: CGFloat) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: .medium)
        return base.fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: size) } ?? base
    }
    private static func sans(_ size: CGFloat) -> UIFont { .systemFont(ofSize: size, weight: .regular) }
}
