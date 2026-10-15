import UIKit
import SwiftUI

// Mindebogen som PDF: forside, milepæle, højdepunkter, dagbog, billedserier og åbnede breve.
// Tegnes lokalt med UIGraphicsPDFRenderer (A4) — ingen server. Forseglede breve udelades.
@MainActor
enum BookExporter {
    nonisolated(unsafe) private static let page = CGRect(x: 0, y: 0, width: 595, height: 842)   // A4 i punkter
    nonisolated(unsafe) private static let margin: CGFloat = 48

    nonisolated private static func serif(_ size: CGFloat, _ weight: UIFont.Weight = .regular) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let d = base.fontDescriptor.withDesign(.serif) else { return base }
        return UIFont(descriptor: d, size: size)
    }
    nonisolated private static func sans(_ size: CGFloat, _ weight: UIFont.Weight = .regular) -> UIFont {
        UIFont.systemFont(ofSize: size, weight: weight)
    }
    nonisolated(unsafe) private static let ink = UIColor(Theme.text)
    nonisolated(unsafe) private static let muted = UIColor(Theme.muted)
    nonisolated(unsafe) private static let accent = UIColor(Theme.neutralDark)
    nonisolated(unsafe) private static let sep = UIColor(Theme.sep)

    /// Bygger bogen for ét barn og returnerer stien til PDF-filen.
    static func make(child: Child, store: Store, familyName: String) async throws -> URL {
        // Hent alt indhold først (billeder inkl.).
        let milestones = (try? await store.milestones(childId: child.id)) ?? [:]
        let highlights = ((try? await store.highlights(childId: child.id)) ?? []).reversed()
        let diary = ((try? await store.diary(childId: child.id)) ?? []).reversed()
        let monthly = (try? await store.gallery(childId: child.id, kind: .monthly)) ?? []
        let belly = (try? await store.gallery(childId: child.id, kind: .belly)) ?? []
        let letters = ((try? await store.letters(childId: child.id)) ?? []).filter { !$0.isSealed }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Mindebog – \(child.name).pdf")
        let meta: [String: Any] = [kCGPDFContextTitle as String: "Mindebog – \(child.name)",
                                   kCGPDFContextCreator as String: "Vores familie"]
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = meta
        let renderer = UIGraphicsPDFRenderer(bounds: page, format: format)

        try renderer.writePDF(to: url) { ctx in
            var y: CGFloat = 0
            func newPage() { ctx.beginPage(); y = margin }
            func ensure(_ height: CGFloat) { if y + height > page.height - margin { newPage() } }
            let width = page.width - margin * 2

            @discardableResult
            func text(_ string: String, _ font: UIFont, _ color: UIColor = ink, spacing: CGFloat = 8,
                      align: NSTextAlignment = .left) -> CGFloat {
                let style = NSMutableParagraphStyle()
                style.alignment = align
                style.lineSpacing = font.pointSize * 0.25
                let attr = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color,
                                                                           .paragraphStyle: style])
                let h = ceil(attr.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                               options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height)
                ensure(h)
                attr.draw(with: CGRect(x: margin, y: y, width: width, height: h),
                          options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                y += h + spacing
                return h
            }

            func image(_ data: Data, maxHeight: CGFloat = 300) {
                guard let img = UIImage(data: data), img.size.width > 0 else { return }
                let scale = min(width / img.size.width, maxHeight / img.size.height)
                let size = CGSize(width: img.size.width * scale, height: img.size.height * scale)
                ensure(size.height + 10)
                let rect = CGRect(x: margin + (width - size.width) / 2, y: y, width: size.width, height: size.height)
                UIBezierPath(roundedRect: rect, cornerRadius: 6).addClip()
                img.draw(in: rect)
                ctx.cgContext.resetClip()
                y += size.height + 12
            }

            func heading(_ title: String) {
                newPage()
                text(title.uppercased(), sans(11, .semibold), muted, spacing: 4)
                ctx.cgContext.setFillColor(sep.cgColor)
                ctx.cgContext.fill(CGRect(x: margin, y: y, width: width, height: 1))
                y += 16
            }

            func photoGrid(_ items: [GalleryItem]) {
                let cols: CGFloat = 2, gap: CGFloat = 14
                let cell = (width - gap) / cols
                var col: CGFloat = 0
                for item in items {
                    guard let data = item.photo, let img = UIImage(data: data) else { continue }
                    if col == 0 { ensure(cell + 26) }
                    let x = margin + col * (cell + gap)
                    let rect = CGRect(x: x, y: y, width: cell, height: cell)
                    ctx.cgContext.saveGState()
                    UIBezierPath(roundedRect: rect, cornerRadius: 6).addClip()
                    // Udfyld kvadratet (beskær midten).
                    let s = max(cell / img.size.width, cell / img.size.height)
                    let drawn = CGSize(width: img.size.width * s, height: img.size.height * s)
                    img.draw(in: CGRect(x: x + (cell - drawn.width) / 2, y: y + (cell - drawn.height) / 2,
                                        width: drawn.width, height: drawn.height))
                    ctx.cgContext.restoreGState()
                    let caption = NSAttributedString(string: item.caption,
                                                     attributes: [.font: sans(10, .medium), .foregroundColor: ink])
                    caption.draw(in: CGRect(x: x, y: y + cell + 4, width: cell, height: 16))
                    col += 1
                    if col == cols { col = 0; y += cell + 26 }
                }
                if col != 0 { y += cell + 26 }
            }

            // Forside
            newPage()
            y = 150
            text(familyName.uppercased(), sans(11, .semibold), muted, spacing: 18, align: .center)
            text(child.name, serif(40, .medium), ink, spacing: 10, align: .center)
            if let birth = child.birthDate {
                text("Født \(Fmt.long(birth))", serif(15), accent, spacing: 30, align: .center)
            } else if let due = child.dueDate {
                text("Termin \(Fmt.long(due))", serif(15), accent, spacing: 30, align: .center)
            }
            if let cover = child.photo ?? monthly.first?.photo ?? belly.last?.photo {
                image(cover, maxHeight: 360)
            }
            text("Mindebog", serif(18), muted, spacing: 0, align: .center)

            // Milepæle
            let filled = Constants.milestones.filter { milestones[$0.key]?.value != nil || milestones[$0.key]?.photo != nil }
            if !filled.isEmpty {
                heading("Milepæle")
                for def in filled {
                    let entry = milestones[def.key]
                    let value = entry?.value.map { MilestoneValue.display($0, kind: def.kind) } ?? ""
                    text("\(def.icon)  \(def.label)", serif(15, .medium), ink, spacing: 2)
                    if !value.isEmpty { text(value, sans(12), muted, spacing: 6) }
                    if let photo = entry?.photo { image(photo, maxHeight: 200) }
                    y += 6
                }
            }

            // Højdepunkter
            if !highlights.isEmpty {
                heading("Højdepunkter")
                for h in highlights {
                    if let date = h.date { text(Fmt.long(date), sans(11), muted, spacing: 2) }
                    text(h.text, serif(15), ink, spacing: 6)
                    for p in h.photos { image(p, maxHeight: 260) }
                    y += 10
                }
            }

            // Dagbog
            if !diary.isEmpty {
                heading(child.onTheWay ? "Svangerskabsdagbog" : "Dagbog")
                for d in diary {
                    if let date = d.date { text(Fmt.long(date), sans(11), muted, spacing: 2) }
                    text(d.text, serif(14), ink, spacing: 6)
                    if let p = d.photo { image(p, maxHeight: 240) }
                    y += 10
                }
            }

            // Billedserier
            if belly.contains(where: { $0.photo != nil }) {
                heading("Maven måned for måned")
                photoGrid(belly)
            }
            if monthly.contains(where: { $0.photo != nil }) {
                heading("Måned for måned")
                photoGrid(monthly)
            }

            // Breve (kun dem, der må åbnes)
            if !letters.isEmpty {
                heading("Breve til dig")
                for l in letters {
                    text(l.title.isEmpty ? "Brev til \(child.name)" : l.title, serif(17, .medium), ink, spacing: 2)
                    text("Skrevet af \(l.author) · \(Fmt.long(l.writtenAt))", sans(11), muted, spacing: 8)
                    if let p = l.photo { image(p, maxHeight: 220) }
                    text(l.text, serif(14), ink, spacing: 18)
                }
            }
        }
        return url
    }
}

/// Apples del-ark for en fil (Gem i Filer, AirDrop, Mail, Udskriv …).
struct ShareSheet: UIViewControllerRepresentable, Identifiable {
    let url: URL
    var id: URL { url }
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
