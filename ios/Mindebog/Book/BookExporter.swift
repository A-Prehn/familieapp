import UIKit
import SwiftUI

// Mindebogen som PDF — bygget som en rigtig bog: forside, indhold, et kapitel pr. leveår
// (højdepunkter, dagbog, billedserier, tegninger, fødselsdag og det årlige interview i tidsorden),
// og bagest "Om dig", milepæle, vaccinationer, vækst og breve. Varm papirfarve, serif, sidetal.
//
// To udgaver:
//  • Skærm/hjemmeprint: A4.
//  • Til tryk: A4 med 3 mm beskæring, ekstra indermargen til indbinding (spejlet på venstre/højre
//    side), billeder højst så store, at de står skarpt (≥ 200 dpi), og et sideantal, der går op i 4.
//
// Tegnes lokalt med UIGraphicsPDFRenderer — ingen server. Forseglede breve udelades.
@MainActor
enum BookExporter {
    /// Bygger bogen for ét barn og returnerer stien til PDF-filen.
    static func make(child: Child, store: Store, familyName: String, forPrint: Bool = false) async throws -> URL {
        let content = await BookContent.load(child: child, store: store, familyName: familyName)
        let name = forPrint ? "Mindebog – \(child.name) (til tryk).pdf" : "Mindebog – \(child.name).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        // To gennemløb: det første finder sidetallene til indholdsfortegnelsen, det andet tegner bogen.
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("mindebog-udkast.pdf")
        let toc = try BookWriter(content: content, forPrint: forPrint, toc: []).write(to: scratch)
        try? FileManager.default.removeItem(at: scratch)
        _ = try BookWriter(content: content, forPrint: forPrint, toc: toc).write(to: url)
        return url
    }
}

// MARK: - Indhold

/// Alt, der skal i bogen, hentet på forhånd.
@MainActor
struct BookContent {
    let child: Child
    let familyName: String
    var milestones: [String: MilestoneEntry] = [:]
    var highlights: [Highlight] = []
    var diary: [DiaryEntry] = []
    var belly: [GalleryItem] = []
    var monthly: [GalleryItem] = []
    var drawings: [GalleryItem] = []
    var birthdays: [GalleryItem] = []
    var letters: [Letter] = []
    var measurements: [Measurement] = []
    var interviews: [InterviewAnswer] = []
    var answers: [String: String] = [:]

    static func load(child: Child, store: Store, familyName: String) async -> BookContent {
        var c = BookContent(child: child, familyName: familyName)
        let id = child.id
        async let ms = store.milestones(childId: id)
        async let hl = store.highlights(childId: id)
        async let di = store.diary(childId: id)
        async let be = store.gallery(childId: id, kind: .belly)
        async let mo = store.gallery(childId: id, kind: .monthly)
        async let dr = store.gallery(childId: id, kind: .drawings)
        async let bd = store.gallery(childId: id, kind: .birthday)
        async let le = store.letters(childId: id)
        async let me = store.measurements(childId: id)
        async let iv = store.interviews(childId: id)
        async let an = store.answers(childId: id)
        c.milestones = (try? await ms) ?? [:]
        c.highlights = (try? await hl) ?? []
        c.diary = (try? await di) ?? []
        c.belly = ((try? await be) ?? []).sorted { $0.shownDate < $1.shownDate }
        c.monthly = ((try? await mo) ?? []).sorted { $0.shownDate < $1.shownDate }
        c.drawings = ((try? await dr) ?? []).sorted { $0.shownDate < $1.shownDate }
        c.birthdays = ((try? await bd) ?? []).sorted { $0.shownDate < $1.shownDate }
        c.letters = ((try? await le) ?? []).filter { !$0.isSealed }.sorted { $0.writtenAt < $1.writtenAt }
        c.measurements = ((try? await me) ?? []).sorted { $0.date < $1.date }
        c.interviews = ((try? await iv) ?? []).filter(\.hasAnswer)
        c.answers = ((try? await an) ?? [:]).filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return c
    }

    /// Et opslag i et kapitel, sorteret efter dato.
    enum Entry {
        case highlight(Highlight)
        case diary(DiaryEntry)
    }

    /// Kapitel: "Før du kom" (age nil) eller et leveår (0 = første år).
    struct Chapter {
        let age: Int?
        var title: String
        var range: String
        var entries: [(date: Date, entry: Entry)] = []
        var monthly: [GalleryItem] = []
        var drawings: [GalleryItem] = []
        var birthdays: [GalleryItem] = []
        var belly: [GalleryItem] = []
        var interview: [InterviewAnswer] = []
        var isEmpty: Bool {
            entries.isEmpty && monthly.isEmpty && drawings.isEmpty && birthdays.isEmpty && belly.isEmpty && interview.isEmpty
        }
    }

    /// Fordeler alt dateret indhold i kapitler efter barnets alder.
    func chapters() -> [Chapter] {
        let cal = Calendar.current
        let birth = child.birthDate.map { cal.startOfDay(for: $0) }
        func age(_ date: Date) -> Int? {
            guard let birth else { return nil }
            if date < birth { return nil }
            return cal.dateComponents([.year], from: birth, to: date).year ?? 0
        }
        var byAge: [Int: Chapter] = [:]
        var before = Chapter(age: nil, title: "Før du kom", range: child.dueDate.map { "Termin \(Fmt.long($0))" } ?? "")
        func chapter(_ a: Int) -> Chapter {
            if let c = byAge[a] { return c }
            let start = birth.flatMap { cal.date(byAdding: .year, value: a, to: $0) } ?? Date()
            let end = cal.date(byAdding: .day, value: -1, to: cal.date(byAdding: .year, value: 1, to: start) ?? start) ?? start
            let title = a == 0 ? "Dit første år" : "Da du var \(a)"
            return Chapter(age: a, title: title, range: Fmt.period(start, min(end, max(start, Date()))))
        }
        func put(_ date: Date, _ apply: (inout Chapter) -> Void) {
            if let a = age(date) {
                var c = chapter(a); apply(&c); byAge[a] = c
            } else {
                apply(&before)
            }
        }
        for h in highlights { let d = h.date ?? h.createdAt; put(d) { $0.entries.append((d, .highlight(h))) } }
        for e in diary { let d = e.date ?? e.createdAt; put(d) { $0.entries.append((d, .diary(e))) } }
        for g in monthly where g.photo != nil { put(g.shownDate) { $0.monthly.append(g) } }
        for g in drawings where g.photo != nil { put(g.shownDate) { $0.drawings.append(g) } }
        for g in belly where g.photo != nil { before.belly.append(g) }
        // Fødselsdagsbilleder har alderen som billedtekst ("5") — de hører til det år, barnet fylder.
        for g in birthdays where g.photo != nil {
            if let a = Int(g.caption.trimmingCharacters(in: .whitespaces)) {
                var c = chapter(a); c.birthdays.append(g); byAge[a] = c
            } else {
                put(g.shownDate) { $0.birthdays.append(g) }
            }
        }
        for i in interviews { var c = chapter(i.age); c.interview.append(i); byAge[i.age] = c }

        var out: [Chapter] = []
        if !before.isEmpty { before.entries.sort { $0.date < $1.date }; out.append(before) }
        for a in byAge.keys.sorted() {
            var c = byAge[a]!
            c.entries.sort { $0.date < $1.date }
            out.append(c)
        }
        return out
    }
}

// MARK: - Tegning

/// Tegner bogen. Én instans pr. gennemløb.
@MainActor
final class BookWriter {
    // Farver — altid lyse, så bogen ser ens ud uanset telefonens tema.
    private let paper = UIColor(red: 0.984, green: 0.969, blue: 0.937, alpha: 1)      // #fbf7ef
    private let chapterPaper = UIColor(red: 0.953, green: 0.922, blue: 0.878, alpha: 1) // #f3ebe0
    private let letterPaper = UIColor(red: 1.0, green: 0.992, blue: 0.973, alpha: 1)    // #fffdf8
    private let ink = UIColor(red: 0.173, green: 0.157, blue: 0.125, alpha: 1)        // #2c2820
    private let muted = UIColor(red: 0.541, green: 0.510, blue: 0.470, alpha: 1)      // #8a8278
    private let gold = UIColor(red: 0.627, green: 0.486, blue: 0.314, alpha: 1)       // #a07c50
    private let rose = UIColor(red: 0.831, green: 0.329, blue: 0.478, alpha: 1)       // #d4547a
    private let sep = UIColor(red: 0.886, green: 0.851, blue: 0.784, alpha: 1)        // #e2d9c8

    private let content: BookContent
    private let forPrint: Bool
    private let toc: [(title: String, page: Int)]

    // A4 i punkter. Til tryk lægges 3 mm (8,5 pt) beskæring på alle sider.
    private let trim = CGSize(width: 595, height: 842)
    private var bleed: CGFloat { forPrint ? 8.5 : 0 }
    private var pageRect: CGRect { CGRect(x: 0, y: 0, width: trim.width + bleed * 2, height: trim.height + bleed * 2) }

    private var ctx: UIGraphicsPDFRendererContext!
    private var page = 0                 // sidetal (forsiden er 1)
    private var y: CGFloat = 0
    private var frame = CGRect.zero      // skrivefladen på den aktuelle side
    private var numbered = true
    private var chapterPages: [(title: String, page: Int)] = []

    init(content: BookContent, forPrint: Bool, toc: [(title: String, page: Int)]) {
        self.content = content
        self.forPrint = forPrint
        self.toc = toc
    }

    /// Skriver PDF'en og returnerer kapitlernes sidetal (til indholdsfortegnelsen).
    func write(to url: URL) throws -> [(title: String, page: Int)] {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: "Mindebog – \(content.child.name)",
                               kCGPDFContextCreator as String: "Vores familie"]
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        try renderer.writePDF(to: url) { ctx in
            self.ctx = ctx
            self.drawBook()
        }
        return chapterPages
    }

    // MARK: Sider

    /// Ny side. Ulige sider er højresider (indbindingen til venstre), lige sider venstresider.
    private func newPage(background: UIColor? = nil, numbered: Bool = true) {
        if page > 0 { drawFooter() }
        ctx.beginPage()
        page += 1
        self.numbered = numbered
        (background ?? paper).setFill()
        UIRectFill(pageRect)
        let outer: CGFloat = 50
        let inner: CGFloat = forPrint ? 68 : 50
        let left = page % 2 == 1 ? inner : outer
        let right = page % 2 == 1 ? outer : inner
        frame = CGRect(x: bleed + left, y: bleed + 56, width: trim.width - left - right, height: trim.height - 56 - 64)
        y = frame.minY
    }

    private func drawFooter() {
        guard numbered else { return }
        let s = NSAttributedString(string: "\(page)", attributes: [.font: sans(9), .foregroundColor: muted])
        let w = s.size().width
        s.draw(at: CGPoint(x: bleed + (trim.width - w) / 2, y: bleed + trim.height - 38))
    }

    private var remaining: CGFloat { frame.maxY - y }
    private func ensure(_ h: CGFloat) { if h > remaining { newPage() } }

    // MARK: Tekst

    private func serif(_ size: CGFloat, _ weight: UIFont.Weight = .regular, italic: Bool = false) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        var d = base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor
        if italic, let i = d.withSymbolicTraits(.traitItalic) { d = i }
        return UIFont(descriptor: d, size: size)
    }
    private func sans(_ size: CGFloat, _ weight: UIFont.Weight = .regular) -> UIFont {
        UIFont.systemFont(ofSize: size, weight: weight)
    }

    private func attributed(_ s: String, _ font: UIFont, _ color: UIColor, align: NSTextAlignment = .left,
                            kern: CGFloat = 0) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.alignment = align
        style.lineSpacing = font.pointSize * 0.3
        return NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color,
                                                          .paragraphStyle: style, .kern: kern])
    }

    private func height(_ a: NSAttributedString, width: CGFloat) -> CGFloat {
        ceil(a.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                            options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height)
    }

    /// Tekst i skrivefladen. Lange tekster brydes over flere sider, afsnit for afsnit.
    private func text(_ s: String, _ font: UIFont, _ color: UIColor? = nil, align: NSTextAlignment = .left,
                      after: CGFloat = 8, x: CGFloat? = nil, width: CGFloat? = nil, kern: CGFloat = 0) {
        let w = width ?? frame.width
        let paragraphs = s.components(separatedBy: "\n")
        for (i, p) in paragraphs.enumerated() {
            let a = attributed(p.isEmpty ? " " : p, font, color ?? ink, align: align, kern: kern)
            let h = height(a, width: w)
            if h > frame.height {   // et meget langt afsnit: tegn det i bidder
                drawLong(p, font, color ?? ink, width: w)
            } else {
                ensure(h)
                a.draw(with: CGRect(x: x ?? frame.minX, y: y, width: w, height: h),
                       options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                y += h + (i == paragraphs.count - 1 ? after : font.pointSize * 0.5)
            }
        }
    }

    /// Et afsnit, der er længere end en hel side: del det på ord.
    private func drawLong(_ s: String, _ font: UIFont, _ color: UIColor, width: CGFloat) {
        var words = s.split(separator: " ").map(String.init)
        while !words.isEmpty {
            var line: [String] = []
            while !words.isEmpty {
                let candidate = (line + [words[0]]).joined(separator: " ")
                if height(attributed(candidate, font, color), width: width) > remaining - 4, !line.isEmpty { break }
                line.append(words.removeFirst())
            }
            let a = attributed(line.joined(separator: " "), font, color)
            let h = height(a, width: width)
            a.draw(with: CGRect(x: frame.minX, y: y, width: width, height: h),
                   options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            y += h + 8
            if !words.isEmpty { newPage() }
        }
    }

    private func kicker(_ s: String, color: UIColor? = nil, after: CGFloat = 6) {
        text(s.uppercased(), sans(8.5, .semibold), color ?? gold, after: after, kern: 1.4)
    }

    private func rule(width: CGFloat = 28, color: UIColor? = nil, centered: Bool = false) {
        (color ?? rose).setFill()
        let x = centered ? frame.midX - width / 2 : frame.minX
        UIRectFill(CGRect(x: x, y: y, width: width, height: 1))
        y += 12
    }

    // MARK: Billeder

    /// Største størrelse i punkter, et billede må fylde. Til tryk: højst så stort, at det er ≥ 200 dpi.
    private func maxPoints(_ img: UIImage) -> CGSize {
        guard forPrint else { return CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude) }
        let px = CGSize(width: img.size.width * img.scale, height: img.size.height * img.scale)
        return CGSize(width: px.width * 72 / 200, height: px.height * 72 / 200)
    }

    /// Ét billede, centreret, med samme form som originalen.
    private func photo(_ data: Data, maxHeight: CGFloat, after: CGFloat = 12) {
        guard let img = UIImage(data: data), img.size.width > 0 else { return }
        let cap = maxPoints(img)
        let scale = min(frame.width / img.size.width, maxHeight / img.size.height,
                        cap.width / img.size.width, cap.height / img.size.height)
        let size = CGSize(width: img.size.width * scale, height: img.size.height * scale)
        ensure(size.height + after)
        let rect = CGRect(x: frame.midX - size.width / 2, y: y, width: size.width, height: size.height)
        drawImage(img, in: rect, fill: false)
        y += size.height + after
    }

    /// Tegner billedet i rect med afrundede hjørner. fill = beskær til at fylde (kvadrater i gitre).
    private func drawImage(_ img: UIImage, in rect: CGRect, fill: Bool) {
        let cg = ctx.cgContext
        cg.saveGState()
        UIBezierPath(roundedRect: rect, cornerRadius: 4).addClip()
        if fill {
            let s = max(rect.width / img.size.width, rect.height / img.size.height)
            let d = CGSize(width: img.size.width * s, height: img.size.height * s)
            img.draw(in: CGRect(x: rect.midX - d.width / 2, y: rect.midY - d.height / 2, width: d.width, height: d.height))
        } else {
            img.draw(in: rect)
        }
        cg.restoreGState()
    }

    /// Gitter af kvadratiske billeder med billedtekst under.
    private func grid(_ photos: [(data: Data, caption: String)], columns: Int, captionFont: UIFont? = nil) {
        let gap: CGFloat = 10
        let cell = (frame.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
        let capH: CGFloat = photos.contains { !$0.caption.isEmpty } ? 16 : 0
        var col = 0
        for p in photos {
            guard let img = UIImage(data: p.data) else { continue }
            if col == 0 { ensure(cell + capH + gap) }
            let x = frame.minX + CGFloat(col) * (cell + gap)
            drawImage(img, in: CGRect(x: x, y: y, width: cell, height: cell), fill: true)
            if !p.caption.isEmpty {
                attributed(p.caption, captionFont ?? sans(8.5), muted, align: .center)
                    .draw(with: CGRect(x: x, y: y + cell + 3, width: cell, height: 14),
                          options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
            }
            col += 1
            if col == columns { col = 0; y += cell + capH + gap }
        }
        if col != 0 { y += cell + capH + gap }
        y += 6
    }

    // MARK: Bogen

    private func drawBook() {
        let c = content
        cover()
        tableOfContents()
        for ch in c.chapters() { chapter(ch) }
        aboutMe()
        milestones()
        vaccines()
        growth()
        letters()
        closing()
        // Til tryk: sideantallet skal gå op i 4 (trykkeriets ark). Fyld op med tomme sider.
        if forPrint {
            while page % 4 != 0 { newPage(numbered: false) }
        }
        drawFooter()
    }

    private func cover() {
        let c = content
        newPage(numbered: false)
        y = frame.minY + 70
        text(c.familyName, sans(9, .semibold), gold, align: .center, after: 26, kern: 2)
        let portrait = c.child.photo ?? c.monthly.last?.photo ?? c.highlights.first?.photos.first ?? c.belly.last?.photo
        if let data = portrait, let img = UIImage(data: data) {
            let d: CGFloat = min(260, forPrint ? maxPoints(img).width : 260)
            let rect = CGRect(x: frame.midX - d / 2, y: y, width: d, height: d)
            let cg = ctx.cgContext
            cg.saveGState()
            UIBezierPath(ovalIn: rect).addClip()
            let s = max(d / img.size.width, d / img.size.height)
            img.draw(in: CGRect(x: rect.midX - img.size.width * s / 2, y: rect.midY - img.size.height * s / 2,
                                width: img.size.width * s, height: img.size.height * s))
            cg.restoreGState()
            y += d + 30
        } else {
            y += 120
        }
        text(c.child.name, serif(38, .medium), ink, align: .center, after: 6)
        if let b = c.child.birthDate {
            text("født \(Fmt.long(b))", serif(13, italic: true), muted, align: .center, after: 16)
        } else if let d = c.child.dueDate {
            text("termin \(Fmt.long(d))", serif(13, italic: true), muted, align: .center, after: 16)
        }
        rule(centered: true)
        text("Mindebog", serif(14), muted, align: .center)
    }

    private func tableOfContents() {
        newPage(numbered: true)
        kicker("Indhold", after: 18)
        // Første gennemløb kender ikke sidetallene endnu — siden reserveres, så tallene passer.
        for entry in toc {
            let a = attributed(entry.title, serif(13), ink)
            let n = attributed("\(entry.page)", serif(13), muted, align: .right)
            let h = height(a, width: frame.width - 40)
            ensure(h + 10)
            a.draw(with: CGRect(x: frame.minX, y: y, width: frame.width - 40, height: h), options: .usesLineFragmentOrigin, context: nil)
            n.draw(with: CGRect(x: frame.maxX - 40, y: y, width: 40, height: h), options: .usesLineFragmentOrigin, context: nil)
            sep.setFill()
            UIRectFill(CGRect(x: frame.minX, y: y + h + 5, width: frame.width, height: 0.5))
            y += h + 12
        }
    }

    private func chapterStart(_ title: String, number: String?, subtitle: String) {
        newPage(background: chapterPaper)
        chapterPages.append((title: title, page: page))
        y = frame.maxY - 170
        if let number { text(number, serif(64, .regular), rose, after: 0) }
        text(title, serif(26, .medium), ink, after: 6)
        if !subtitle.isEmpty { text(subtitle, serif(12, italic: true), muted) }
    }

    /// Start en sektion på en ny side med overskrift — eller fortsæt på siden, hvis der er god plads.
    private func section(_ title: String, minSpace: CGFloat = 220) {
        if remaining < minSpace || y > frame.minY + frame.height * 0.55 { newPage() } else { y += 18 }
        kicker(title, after: 4)
        rule(width: 20)
    }

    private func chapter(_ ch: BookContent.Chapter) {
        let number = ch.age.map { $0 == 0 ? "1" : "\($0)" }
        chapterStart(ch.title, number: ch.age == nil ? nil : number, subtitle: ch.range)
        newPage()

        // Det årlige interview hører til fødselsdagen — først i året.
        if !ch.interview.isEmpty, let age = ch.age {
            section("Det årlige interview · \(age) år")
            for q in Constants.interviewQuestions {
                guard let a = ch.interview.first(where: { $0.question == q.key }) else { continue }
                ensure(60)
                text(q.text, sans(9.5, .medium), muted, after: 3)
                text(a.text.isEmpty ? "(svar på lyd eller video)" : a.text, serif(13), ink, after: 12)
            }
        }
        if !ch.birthdays.isEmpty {
            section(ch.age.map { $0 == 0 ? "Fødselsdagen" : "\($0)-års fødselsdag" } ?? "Fødselsdag")
            let photos = ch.birthdays.compactMap { g in g.photo.map { (data: $0, caption: g.note) } }
            if photos.count == 1 { photo(photos[0].data, maxHeight: 320) } else { grid(photos, columns: photos.count <= 4 ? 2 : 3) }
        }
        if !ch.belly.isEmpty {
            section("Maven måned for måned")
            grid(ch.belly.compactMap { g in g.photo.map { (data: $0, caption: g.caption) } }, columns: 3)
        }

        for item in ch.entries {
            switch item.entry {
            case .highlight(let h): highlight(h)
            case .diary(let d): diaryEntry(d)
            }
        }

        if !ch.monthly.isEmpty {
            section("Måned for måned")
            grid(ch.monthly.compactMap { g in g.photo.map { (data: $0, caption: g.caption) } }, columns: 3)
        }
        if !ch.drawings.isEmpty {
            section("Tegninger")
            grid(ch.drawings.compactMap { g in g.photo.map { (data: $0, caption: g.caption) } }, columns: 2)
        }
    }

    private func dateLine(_ date: Date) -> String {
        guard let birth = content.child.birthDate, date >= birth else { return Fmt.long(date) }
        let age = ChildAge.at(content.child, date: date)
        return age.isEmpty ? Fmt.long(date) : "\(Fmt.long(date)) · \(age)"
    }

    private func highlight(_ h: Highlight) {
        let photos = h.photos
        // Sørg for, at overskrift og (det første) billede står sammen.
        ensure(photos.isEmpty ? 80 : 260)
        y += 6
        kicker(dateLine(h.date ?? h.createdAt), after: 6)
        if photos.count == 1 {
            photo(photos[0], maxHeight: 340, after: 10)
        } else if !photos.isEmpty {
            grid(photos.map { ($0, "") }, columns: photos.count <= 4 ? 2 : 3)
        }
        if !h.text.isEmpty { text(h.text, serif(13.5), ink, after: 6) }
        if let place = h.place?.name, !place.isEmpty { text(place, sans(9), muted, after: 4) }
        y += 16
    }

    private func diaryEntry(_ d: DiaryEntry) {
        let short = d.text.count < 160 && !d.text.contains("\n")
        if short && d.photo == nil {
            // Korte noter som citat med rosa streg.
            let a = attributed("\u{201C}\(d.text)\u{201D}", serif(14, italic: true), ink)
            let h = height(a, width: frame.width - 16)
            ensure(h + 30)
            y += 4
            rose.setFill()
            UIRectFill(CGRect(x: frame.minX, y: y, width: 2, height: h))
            a.draw(with: CGRect(x: frame.minX + 14, y: y, width: frame.width - 16, height: h),
                   options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            y += h + 4
            text("Dagbog · \(dateLine(d.date ?? d.createdAt))", sans(8.5), muted, after: 18, x: frame.minX + 14)
        } else {
            ensure(80)
            kicker("Dagbog · \(dateLine(d.date ?? d.createdAt))", color: muted, after: 6)
            if let p = d.photo { photo(p, maxHeight: 260, after: 10) }
            text(d.text, serif(13), ink, after: 18)
        }
    }

    private func aboutMe() {
        let a = content.answers
        guard !a.isEmpty else { return }
        chapterStart("Om dig", number: nil, subtitle: "Det, vi har skrevet om dig")
        newPage()
        for s in Constants.aboutMe {
            let qs = s.questions.filter { a[$0] != nil }
            guard !qs.isEmpty else { continue }
            section(s.title, minSpace: 160)
            for q in qs {
                ensure(56)
                text(q, sans(9.5, .medium), muted, after: 3)
                text(a[q] ?? "", serif(13), ink, after: 12)
            }
        }
    }

    private func milestones() {
        let ms = content.milestones
        let filled = Constants.milestones.filter { ms[$0.key]?.value != nil || ms[$0.key]?.photo != nil }
        guard !filled.isEmpty else { return }
        chapterStart("Milepæle", number: nil, subtitle: "\(filled.count) milepæle")
        newPage()
        // Kort i to kolonner: ikon og navn, værdien i serif. Milepæle med billede får billedet under.
        let gap: CGFloat = 12
        let w = (frame.width - gap) / 2
        var col = 0
        var rowH: CGFloat = 0
        for def in filled {
            let entry = ms[def.key]
            let value = entry?.value.map { MilestoneValue.display($0, kind: def.kind) } ?? ""
            let img = entry?.photo.flatMap(UIImage.init(data:))
            let label = attributed("\(def.icon)  \(def.label)", sans(9, .medium), muted)
            let val = attributed(value.isEmpty ? " " : value, serif(14), ink)
            let photoH: CGFloat = img == nil ? 0 : w * 0.66 + 8
            let h = 14 + height(label, width: w - 20) + 4 + height(val, width: w - 20) + photoH + 14
            if col == 0 { ensure(h) }
            let x = frame.minX + CGFloat(col) * (w + gap)
            let box = CGRect(x: x, y: y, width: w, height: h)
            UIColor.white.withAlphaComponent(0.6).setFill()
            UIBezierPath(roundedRect: box, cornerRadius: 6).fill()
            sep.setStroke()
            let path = UIBezierPath(roundedRect: box.insetBy(dx: 0.25, dy: 0.25), cornerRadius: 6)
            path.lineWidth = 0.5
            path.stroke()
            var iy = y + 12
            if let img {
                drawImage(img, in: CGRect(x: x + 10, y: iy, width: w - 20, height: w * 0.66 - 12), fill: true)
                iy += w * 0.66
            }
            label.draw(with: CGRect(x: x + 10, y: iy, width: w - 20, height: 40), options: .usesLineFragmentOrigin, context: nil)
            iy += height(label, width: w - 20) + 4
            val.draw(with: CGRect(x: x + 10, y: iy, width: w - 20, height: 200), options: .usesLineFragmentOrigin, context: nil)
            rowH = max(rowH, h)
            col += 1
            if col == 2 { col = 0; y += rowH + gap; rowH = 0 }
        }
        if col != 0 { y += rowH + gap }
    }

    private func vaccines() {
        let ms = content.milestones
        let given = VaccineProgram.all.compactMap { v -> (String, String, Date)? in
            guard let value = ms[v.key]?.value, let d = Fmt.parseIso(value) else { return nil }
            return (v.name, v.detail, d)
        }
        let custom = ms.compactMap { key, entry -> (String, String, Date)? in
            guard key.hasPrefix(CustomVaccine.prefix), let value = entry.value, let v = CustomVaccine.decode(value) else { return nil }
            return (v.name, v.note, v.date)
        }
        let all = (given + custom).sorted { $0.2 < $1.2 }
        guard !all.isEmpty else { return }
        newPage()
        kicker("Vaccinationer", after: 4)
        rule(width: 20)
        for (name, detail, date) in all {
            ensure(44)
            let left = attributed(name, serif(13), ink)
            let right = attributed(Fmt.long(date), sans(10), muted, align: .right)
            left.draw(with: CGRect(x: frame.minX, y: y, width: frame.width - 140, height: 20), options: .usesLineFragmentOrigin, context: nil)
            right.draw(with: CGRect(x: frame.maxX - 140, y: y + 2, width: 140, height: 20), options: .usesLineFragmentOrigin, context: nil)
            y += 19
            if !detail.isEmpty { text(detail, sans(9), muted, after: 4) }
            sep.setFill(); UIRectFill(CGRect(x: frame.minX, y: y + 2, width: frame.width, height: 0.5))
            y += 10
        }
    }

    private func growth() {
        let m = content.measurements
        guard !m.isEmpty else { return }
        section("Vækst", minSpace: 200)
        let cols: [(String, CGFloat)] = [("Dato", 0.34), ("Alder", 0.2), ("Vægt", 0.16), ("Højde", 0.15), ("Hoved", 0.15)]
        func row(_ cells: [String], font: UIFont, color: UIColor) {
            ensure(22)
            var x = frame.minX
            for (i, c) in cells.enumerated() {
                let w = frame.width * cols[i].1
                attributed(c, font, color, align: i == 0 ? .left : .right)
                    .draw(with: CGRect(x: x, y: y, width: w - 6, height: 18), options: .usesLineFragmentOrigin, context: nil)
                x += w
            }
            y += 18
            sep.setFill(); UIRectFill(CGRect(x: frame.minX, y: y, width: frame.width, height: 0.5))
            y += 5
        }
        row(cols.map(\.0), font: sans(8.5, .semibold), color: muted)
        for x in m {
            let weight = x.weightGrams.map { String(format: "%.2f kg", Double($0) / 1000).replacingOccurrences(of: ".", with: ",") } ?? "–"
            let height = x.heightCm.map { String(format: "%.1f cm", $0).replacingOccurrences(of: ".", with: ",") } ?? "–"
            let head = x.headCm.map { String(format: "%.1f cm", $0).replacingOccurrences(of: ".", with: ",") } ?? "–"
            row([Fmt.long(x.date), ChildAge.at(content.child, date: x.date), weight, height, head], font: sans(10), color: ink)
        }
    }

    private func letters() {
        let ls = content.letters
        guard !ls.isEmpty else { return }
        chapterStart("Breve til dig", number: nil, subtitle: ls.count == 1 ? "Ét brev" : "\(ls.count) breve")
        for l in ls {
            newPage(background: letterPaper)
            kicker(Fmt.long(l.writtenAt), after: 12)
            text(l.title.isEmpty ? "Kære \(content.child.name)" : l.title, serif(20, .medium), ink, after: 14)
            if let p = l.photo { photo(p, maxHeight: 220, after: 14) }
            text(l.text, serif(13, italic: true), ink, after: 18)
            text("Kærlig hilsen\n\(l.author)", serif(13), ink, align: .right)
        }
    }

    private func closing() {
        newPage(numbered: false)
        y = frame.midY - 40
        rule(centered: true)
        text("Lavet med kærlighed af \(content.familyName)", serif(13, italic: true), muted, align: .center, after: 6)
        text("Vores familie · \(Fmt.long(Date()))", sans(8.5), muted, align: .center)
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
