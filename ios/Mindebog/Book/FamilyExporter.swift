import Foundation
import UIKit

// "Eksportér alt": samler hele familiens indhold i én ZIP-fil på telefonen — uden server.
// Billeder, video og lyd i den kvalitet, de er gemt i; tekster som læsbare .txt-filer,
// målinger som CSV, en PDF-mindebog pr. barn og alt samlet i data.json, så indholdet
// kan læses af andre programmer, også hvis appen en dag ikke findes mere.
//
// Struktur:
//   Vores familie – eksport 2026-10-16/
//     LÆS MIG.txt, data.json
//     Familie/   Fødselsdage.txt, Begivenheder/, Ferier/
//     Børn/<navn>/  Oversigt.txt, Mindebog.pdf, Højdepunkter/, Dagbog/, Milepæle/,
//                   Maven måned for måned/, Måned for måned/, Breve/, Målinger.csv
@MainActor
final class FamilyExport: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var status = ""
    @Published private(set) var progress: Double = 0
    @Published private(set) var resultURL: URL?
    @Published var errorMessage: String?

    private var done = 0
    private var total = 1
    private let fm = FileManager.default

    func run(store: Store, familyId: String, familyName: String) async {
        guard !running else { return }
        running = true
        resultURL = nil
        errorMessage = nil
        progress = 0
        UIApplication.shared.isIdleTimerDisabled = true   // skærmen må ikke slukke midt i eksporten
        defer {
            running = false
            UIApplication.shared.isIdleTimerDisabled = false
        }
        do {
            let folder = try await build(store: store, familyId: familyId, familyName: familyName)
            step("Pakker ZIP-filen…")
            let zip = try await Task.detached(priority: .userInitiated) { try FamilyExport.zip(folder) }.value
            try? fm.removeItem(at: folder)
            progress = 1
            status = "Færdig"
            resultURL = zip
        } catch {
            errorMessage = "Eksporten fejlede: \(error.localizedDescription)"
            status = ""
        }
    }

    // MARK: - Opbygning

    private func build(store: Store, familyId: String, familyName: String) async throws -> URL {
        let root = fm.temporaryDirectory.appendingPathComponent("Eksport", isDirectory: true)
        try? fm.removeItem(at: root)
        let title = "\(familyName.isEmpty ? "Vores familie" : familyName) – eksport \(Fmt.iso(Date()))"
        let base = root.appendingPathComponent(Self.safe(title), isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)

        step("Henter børn…")
        // Også børn, som en anden forælder har delt med én (de ligger i deres egen zone).
        var children = try await store.children(familyId: familyId)
        for c in (try? await store.sharedChildren()) ?? [] where !children.contains(where: { $0.id == c.id }) { children.append(c) }
        total = children.count * 8 + 4
        var json: [String: Any] = ["familie": familyName,
                                   "eksporteret": ISO8601DateFormatter().string(from: Date()),
                                   "app": "Vores familie"]

        // Børn
        var childrenJSON: [[String: Any]] = []
        for child in children {
            childrenJSON.append(try await exportChild(child, store: store, familyName: familyName,
                                                      into: base.appendingPathComponent("Børn", isDirectory: true)))
        }
        json["børn"] = childrenJSON

        // Fælles for familien
        let familyDir = base.appendingPathComponent("Familie", isDirectory: true)
        try fm.createDirectory(at: familyDir, withIntermediateDirectories: true)

        step("Fødselsdage…")
        let birthdays = (try? await store.birthdays(familyId: familyId)) ?? []
        var bdayText = "FØDSELSDAGE\n\n"
        for child in children { if let b = child.birthDate { bdayText += "\(child.name): \(Fmt.long(b))\n" } }
        for b in birthdays.sorted(by: { $0.name < $1.name }) { bdayText += "\(b.name): \(Fmt.long(b.date))\n" }
        try write(bdayText, to: familyDir.appendingPathComponent("Fødselsdage.txt"))
        json["fødselsdage"] = birthdays.map { ["navn": $0.name, "dato": Fmt.iso($0.date)] }

        step("Familietræ…")
        let persons = (try? await store.persons(familyId: familyId)) ?? []
        if !persons.isEmpty {
            let byId = Dictionary(persons.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let treeDir = familyDir.appendingPathComponent("Familietræ", isDirectory: true)
            var treeText = "FAMILIETRÆ\n\n"
            var treeJSON: [[String: Any]] = []
            for p in persons.sorted(by: FamilyTreeLayout.olderFirst) {
                let linked = p.childId.flatMap { id in children.first { $0.id == id } }
                let name = linked?.name ?? p.name
                let birth = linked?.birthDate ?? p.birthDate
                var line = name
                if !p.role.isEmpty { line += " (\(p.role))" }
                if let b = birth { line += ", født \(Fmt.long(b))" }
                if let d = p.deathDate { line += ", død \(Fmt.long(d))" }
                let parents = p.parentIds.compactMap { byId[$0]?.name }
                let partners = p.partnerIds.compactMap { byId[$0]?.name }
                if !parents.isEmpty { line += "\n  Forældre: " + parents.joined(separator: ", ") }
                if !partners.isEmpty { line += "\n  Partner: " + partners.joined(separator: ", ") }
                treeText += line + "\n\n"
                var files: [String] = []
                if let photo = linked?.photo ?? p.photo { files.append(try writePhoto(photo, to: treeDir, name: Self.safe(name))) }
                treeJSON.append(["id": p.id, "navn": name, "rolle": p.role, "født": birth.map(Fmt.iso) as Any,
                                 "død": p.deathDate.map(Fmt.iso) as Any, "forældre": p.parentIds,
                                 "partnere": p.partnerIds, "filer": files])
            }
            try write(treeText, to: treeDir.appendingPathComponent("Familietræ.txt"))
            json["familietræ"] = treeJSON
        }

        step("Traditioner…")
        let traditions = (try? await store.traditions(familyId: familyId)) ?? []
        if !traditions.isEmpty {
            let tDir = familyDir.appendingPathComponent("Traditioner", isDirectory: true)
            var tJSON: [[String: Any]] = []
            for t in traditions {
                let name = Self.safe(t.title)
                var files = try writePhotoSet(t.photos, name: name, in: tDir)
                if t.audioDuration != nil, let u = try? await store.traditionAudio(familyId: familyId, id: t.id) {
                    files.append(try copy(u, to: tDir, name: name + " (lyd)"))
                }
                var text = t.title + "\n"
                if !t.when.isEmpty { text += "Hvornår: \(t.when)\n" }
                if !t.details.isEmpty { text += "\n" + t.details + "\n" }
                try write(text, to: tDir.appendingPathComponent(name + ".txt"))
                tJSON.append(["titel": t.title, "hvornår": t.when, "beskrivelse": t.details, "filer": files])
            }
            json["traditioner"] = tJSON
        }

        step("Minder…")
        let freeMemories = (try? await store.memories(familyId: familyId)) ?? []
        if !freeMemories.isEmpty {
            let mDir = familyDir.appendingPathComponent("Minder", isDirectory: true)
            var mJSON: [[String: Any]] = []
            for m in freeMemories {
                let name = Self.prefix(m.date) + Self.safe(m.title)
                let files = try writePhotoSet(m.photos, name: name, in: mDir)
                let who = m.childIds.compactMap { id in children.first { $0.id == id }?.name }
                var text = m.title + "\n"
                if let d = m.dateText { text += d + "\n" }
                if !who.isEmpty { text += "Handler om: " + who.joined(separator: ", ") + "\n" }
                if !m.text.isEmpty { text += "\n" + m.text + "\n" }
                try write(text, to: mDir.appendingPathComponent(name + ".txt"))
                mJSON.append(["titel": m.title, "dato": m.date.map(Fmt.iso) as Any, "tekst": m.text,
                              "handler_om": who, "filer": files])
            }
            json["minder"] = mJSON
        }

        step("Opskrifter…")
        let recipes = (try? await store.recipes(familyId: familyId)) ?? []
        if !recipes.isEmpty {
            let rDir = familyDir.appendingPathComponent("Opskrifter", isDirectory: true)
            var rJSON: [[String: Any]] = []
            for r in recipes {
                let name = Self.safe(r.title)
                let files = try writePhotoSet(r.photos, name: name, in: rDir)
                var text = r.title + "\n"
                if !r.fromWhom.isEmpty { text += "Fra: \(r.fromWhom)\n" }
                if !r.category.isEmpty { text += "Kategori: \(r.category)\n" }
                if !r.servings.isEmpty { text += "Til: \(r.servings)\n" }
                if !r.ingredients.isEmpty { text += "\nINGREDIENSER\n" + r.ingredients + "\n" }
                if !r.method.isEmpty { text += "\nFREMGANGSMÅDE\n" + r.method + "\n" }
                if !r.story.isEmpty { text += "\nHISTORIEN BAG\n" + r.story + "\n" }
                try write(text, to: rDir.appendingPathComponent(name + ".txt"))
                rJSON.append(["titel": r.title, "fra": r.fromWhom, "kategori": r.category, "antal": r.servings,
                              "ingredienser": r.ingredientLines, "fremgangsmåde": r.method, "historie": r.story, "filer": files])
            }
            json["opskrifter"] = rJSON
        }

        step("Begivenheder…")
        let events = (try? await store.events(familyId: familyId)) ?? []
        let eventsDir = familyDir.appendingPathComponent("Begivenheder", isDirectory: true)
        json["begivenheder"] = try events.map { e -> [String: Any] in
            let name = Self.prefix(e.date) + Self.safe(e.title)
            let files = try writePhotoSet(e.photos, name: name, in: eventsDir)
            try write(Self.describe(title: e.title, date: e.date.map(Fmt.long), place: e.place,
                                    details: e.details, photos: e.photos),
                      to: eventsDir.appendingPathComponent(name + ".txt"))
            return ["titel": e.title, "dato": e.date.map(Fmt.iso) as Any, "beskrivelse": e.details,
                    "sted": Self.placeJSON(e.place) as Any, "filer": files]
        }

        step("Rejser…")
        let vacations = (try? await store.vacations(familyId: familyId)) ?? []
        let vacDir = familyDir.appendingPathComponent("Rejser", isDirectory: true)
        json["rejser"] = try vacations.map { v -> [String: Any] in
            let name = Self.prefix(v.startDate) + Self.safe(v.title)
            let files = try writePhotoSet(v.photos, name: name, in: vacDir)
            let period = [v.startDate, v.endDate].compactMap { $0.map(Fmt.long) }.joined(separator: " – ")
            try write(Self.describe(title: v.title, date: period.isEmpty ? nil : period, place: v.place,
                                    details: v.details, photos: v.photos),
                      to: vacDir.appendingPathComponent(name + ".txt"))
            return ["titel": v.title, "start": v.startDate.map(Fmt.iso) as Any, "slut": v.endDate.map(Fmt.iso) as Any,
                    "beskrivelse": v.details, "sted": Self.placeJSON(v.place) as Any, "filer": files]
        }

        step("Skriver data.json…")
        let data = try JSONSerialization.data(withJSONObject: Self.clean(json), options: [.prettyPrinted, .sortedKeys])
        try data.write(to: base.appendingPathComponent("data.json"))
        try write(Self.readme(familyName: familyName), to: base.appendingPathComponent("LÆS MIG.txt"))
        return base
    }

    private func exportChild(_ child: Child, store: Store, familyName: String, into parent: URL) async throws -> [String: Any] {
        let dir = parent.appendingPathComponent(Self.safe(child.name), isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        var out: [String: Any] = ["navn": child.name, "køn": child.gender.rawValue,
                                  "født": child.birthDate.map(Fmt.iso) as Any,
                                  "termin": child.dueDate.map(Fmt.iso) as Any]
        var overview = "\(child.name.uppercased())\n\n"
        if let b = child.birthDate { overview += "Født: \(Fmt.long(b))\n" }
        if let d = child.dueDate { overview += "Termin: \(Fmt.long(d))\n" }
        if let photo = child.photo { try writePhoto(photo, to: dir, name: "Profilbillede") }

        // Milepæle
        step("\(child.name): milepæle…")
        let ms = (try? await store.milestones(childId: child.id)) ?? [:]
        let msDir = dir.appendingPathComponent("Milepæle", isDirectory: true)
        var msJSON: [[String: Any]] = []
        var msText = ""
        for def in Constants.milestones {
            guard let entry = ms[def.key], entry.value != nil || !entry.photos.isEmpty else { continue }
            let value = entry.value.map { MilestoneValue.display($0, kind: def.kind) } ?? ""
            msText += "\(def.label): \(value)\n"
            let files = try writePhotoSet(entry.photos, name: Self.safe(def.label), in: msDir)
            msJSON.append(["milepæl": def.label, "værdi": value, "filer": files])
        }
        if !msText.isEmpty { overview += "\nMILEPÆLE\n" + msText }
        out["milepæle"] = msJSON

        // Vacciner (standardprogram + egne)
        var vacText = ""
        var vacJSON: [[String: Any]] = []
        for v in VaccineProgram.all {
            if let value = ms[v.key]?.value, let date = Fmt.parseIso(value) {
                vacText += "\(v.name) – \(v.detail): givet \(Fmt.long(date))\n"
                vacJSON.append(["vaccine": "\(v.name) – \(v.detail)", "dato": Fmt.iso(date)])
            }
        }
        let custom = ms.compactMap { key, entry -> CustomVaccine? in
            guard key.hasPrefix(CustomVaccine.prefix), let value = entry.value else { return nil }
            return CustomVaccine.decode(value)
        }.sorted { $0.date < $1.date }
        for v in custom {
            vacText += "\(v.name): givet \(Fmt.long(v.date))" + (v.note.isEmpty ? "" : " (\(v.note))") + "\n"
            vacJSON.append(["vaccine": v.name, "dato": Fmt.iso(v.date), "note": v.note])
        }
        if !vacText.isEmpty { overview += "\nVACCINATIONER\n" + vacText }
        out["vacciner"] = vacJSON

        // Om mig (spørgsmål og svar)
        step("\(child.name): om mig…")
        let answers = (try? await store.answers(childId: child.id)) ?? [:]
        var aboutText = ""
        for section in Constants.aboutMe {
            let filled = section.questions.filter { !(answers[$0] ?? "").isEmpty }
            guard !filled.isEmpty else { continue }
            aboutText += "\n\(section.title)\n"
            for q in filled { aboutText += "  \(q)\n  → \(answers[q] ?? "")\n" }
        }
        if !aboutText.isEmpty { overview += "\nOM MIG\n" + aboutText }
        out["om_mig"] = answers

        // Højdepunkter inkl. video og lyd
        step("\(child.name): højdepunkter…")
        let highlights = (try? await store.highlights(childId: child.id)) ?? []
        let hlDir = dir.appendingPathComponent("Højdepunkter", isDirectory: true)
        var hlJSON: [[String: Any]] = []
        for (i, h) in highlights.sorted(by: { ($0.date ?? $0.createdAt) < ($1.date ?? $1.createdAt) }).enumerated() {
            let name = Self.prefix(h.date ?? h.createdAt) + String(format: "%03d", i + 1)
            var files = try writePhotoSet(PhotoSet(photos: h.photos), name: name, in: hlDir)
            if h.videoDuration != nil || h.audioDuration != nil,
               let media = try? await store.highlightMedia(childId: child.id, id: h.id) {
                if let v = media.video { files.append(try copy(v, to: hlDir, name: name + " video")) }
                if let a = media.audio { files.append(try copy(a, to: hlDir, name: name + " lyd")) }
            }
            try write(h.text, to: hlDir.appendingPathComponent(name + ".txt"))
            hlJSON.append(["dato": (h.date ?? h.createdAt).isoDay, "tekst": h.text, "filer": files])
        }
        out["højdepunkter"] = hlJSON

        // Dagbog
        step("\(child.name): dagbog…")
        let diary = (try? await store.diary(childId: child.id)) ?? []
        let diaryDir = dir.appendingPathComponent(child.onTheWay ? "Svangerskabsdagbog" : "Dagbog", isDirectory: true)
        var diaryJSON: [[String: Any]] = []
        for (i, d) in diary.sorted(by: { ($0.date ?? $0.createdAt) < ($1.date ?? $1.createdAt) }).enumerated() {
            let name = Self.prefix(d.date ?? d.createdAt) + String(format: "%03d", i + 1)
            var files: [String] = []
            if let p = d.photo { files.append(try writePhoto(p, to: diaryDir, name: name)) }
            try write(d.text, to: diaryDir.appendingPathComponent(name + ".txt"))
            diaryJSON.append(["dato": (d.date ?? d.createdAt).isoDay, "tekst": d.text, "filer": files])
        }
        out["dagbog"] = diaryJSON

        // Billedserier
        step("\(child.name): billedserier…")
        for kind in [GalleryKind.belly, .monthly, .drawings, .birthday] {
            let items = (try? await store.gallery(childId: child.id, kind: kind)) ?? []
            let gDir = dir.appendingPathComponent(kind.title, isDirectory: true)
            var gJSON: [[String: Any]] = []
            for (i, item) in items.sorted(by: { $0.shownDate < $1.shownDate }).enumerated() {
                let name = String(format: "%02d", i + 1) + (item.caption.isEmpty ? "" : " " + Self.safe(item.caption))
                var files: [String] = []
                if let p = item.photo { files.append(try writePhoto(p, to: gDir, name: name)) }
                gJSON.append(["tekst": item.caption, "beskrivelse": item.note, "dato": Fmt.iso(item.shownDate), "filer": files])
            }
            let key: String
            switch kind {
            case .belly: key = "mavebilleder"
            case .monthly: key = "månedsbilleder"
            case .drawings: key = "tegninger"
            case .birthday: key = "fødselsdage"
            }
            out[key] = gJSON
        }

        // Det årlige interview — pr. alder en tekstfil og lyd/video-filer
        step("\(child.name): interview…")
        let ivAnswers = (try? await store.interviews(childId: child.id)) ?? []
        if !ivAnswers.isEmpty {
            let ivDir = dir.appendingPathComponent("Det årlige interview", isDirectory: true)
            var ivJSON: [[String: Any]] = []
            for age in Set(ivAnswers.map { $0.age }).sorted() {
                let ageName = age == 1 ? "1 år" : "\(age) år"
                var text = "\(child.name.uppercased()) – \(ageName)\n\n"
                for q in Constants.interviewQuestions {
                    guard let a = ivAnswers.first(where: { $0.age == age && $0.question == q.key }), a.hasAnswer else { continue }
                    text += "\(q.text)\n"
                    if !a.text.isEmpty { text += "  → \(a.text)\n" }
                    var files: [String] = []
                    if a.audioDuration != nil || a.videoDuration != nil,
                       let media = try? await store.interviewMedia(childId: child.id, id: a.id) {
                        let base = "\(ageName) – \(Self.safe(q.text))"
                        if let u = media.audio { files.append(try copy(u, to: ivDir, name: base + " (lyd)")) }
                        if let u = media.video { files.append(try copy(u, to: ivDir, name: base + " (video)")) }
                    }
                    if !files.isEmpty { text += "  (\(files.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")))\n" }
                    text += "\n"
                    ivJSON.append(["alder": age, "spørgsmål": q.text, "svar": a.text, "dato": Fmt.iso(a.date), "filer": files])
                }
                try write(text, to: ivDir.appendingPathComponent("\(ageName).txt"))
            }
            out["interview"] = ivJSON
        }

        // Målinger
        step("\(child.name): målinger…")
        let measurements = ((try? await store.measurements(childId: child.id)) ?? []).sorted { $0.date < $1.date }
        if !measurements.isEmpty {
            var csv = "dato;vægt (g);højde (cm);hovedomkreds (cm)\n"
            for m in measurements {
                csv += [Fmt.iso(m.date), m.weightGrams.map { String($0) } ?? "",
                        m.heightCm.map { String($0) } ?? "", m.headCm.map { String($0) } ?? ""].joined(separator: ";") + "\n"
            }
            try write(csv, to: dir.appendingPathComponent("Målinger.csv"))
        }
        out["målinger"] = measurements.map {
            ["dato": Fmt.iso($0.date), "vægt_g": $0.weightGrams as Any, "højde_cm": $0.heightCm as Any, "hoved_cm": $0.headCm as Any]
        }

        // Breve — forseglede lægges for sig, så de ikke læses ved et uheld
        step("\(child.name): breve…")
        let letters = (try? await store.letters(childId: child.id)) ?? []
        var lettersJSON: [[String: Any]] = []
        for l in letters.sorted(by: { $0.writtenAt < $1.writtenAt }) {
            let folder = l.isSealed
                ? "Forseglede breve – åbnes \(l.openDate.map(Fmt.long) ?? "senere")"
                : "Breve"
            let lDir = dir.appendingPathComponent(Self.safe(folder), isDirectory: true)
            let title = l.title.isEmpty ? "Brev til \(child.name)" : l.title
            let name = Self.prefix(l.writtenAt) + Self.safe(title)
            var files: [String] = []
            if let p = l.photo { files.append(try writePhoto(p, to: lDir, name: name)) }
            if l.videoDuration != nil, let v = try? await store.letterVideo(childId: child.id, id: l.id) {
                files.append(try copy(v, to: lDir, name: name + " (videobrev)"))
            }
            var text = "\(title)\nSkrevet af \(l.author), \(Fmt.long(l.writtenAt))\n"
            if let open = l.openDate { text += "Må åbnes: \(Fmt.long(open))\n" }
            text += "\n\(l.text)\n"
            try write(text, to: lDir.appendingPathComponent(name + ".txt"))
            lettersJSON.append(["titel": title, "forfatter": l.author, "skrevet": Fmt.iso(l.writtenAt),
                                "åbnes": l.openDate.map(Fmt.iso) as Any, "tekst": l.text, "filer": files])
        }
        out["breve"] = lettersJSON

        // PDF-mindebog
        step("\(child.name): mindebog (PDF)…")
        if let pdf = try? await BookExporter.make(child: child, store: store, familyName: familyName) {
            _ = try? copy(pdf, to: dir, name: "Mindebog – \(Self.safe(child.name))")
        }

        try write(overview, to: dir.appendingPathComponent("Oversigt.txt"))
        return out
    }

    // MARK: - Filer

    private func step(_ text: String) {
        status = text
        done += 1
        progress = min(0.97, Double(done) / Double(max(total, 1)))
    }

    private func write(_ text: String, to url: URL) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Skriver ét billede og returnerer stien relativt til eksport-roden (til data.json).
    @discardableResult
    private func writePhoto(_ data: Data, to dir: URL, name: String) throws -> String {
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = unique(dir.appendingPathComponent(name).appendingPathExtension(Self.imageExtension(data)))
        try data.write(to: url)
        return relative(url)
    }

    private func writePhotoSet(_ set: PhotoSet, name: String, in dir: URL) throws -> [String] {
        try set.photos.enumerated().map { i, data in
            try writePhoto(data, to: dir, name: set.count == 1 ? name : "\(name) \(i + 1)")
        }
    }

    private func copy(_ source: URL, to dir: URL, name: String) throws -> String {
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let ext = source.pathExtension.isEmpty ? "dat" : source.pathExtension
        let url = unique(dir.appendingPathComponent(name).appendingPathExtension(ext))
        try fm.copyItem(at: source, to: url)
        return relative(url)
    }

    private func unique(_ url: URL) -> URL {
        guard fm.fileExists(atPath: url.path) else { return url }
        let base = url.deletingPathExtension().lastPathComponent, ext = url.pathExtension
        var n = 2
        while true {
            let candidate = url.deletingLastPathComponent().appendingPathComponent("\(base) (\(n))").appendingPathExtension(ext)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }

    private func relative(_ url: URL) -> String {
        let parts = url.pathComponents
        guard let i = parts.firstIndex(of: "Eksport"), i + 2 < parts.count else { return url.lastPathComponent }
        return parts[(i + 2)...].joined(separator: "/")
    }

    // MARK: - Hjælpere

    /// iOS kan lave ZIP af en mappe via NSFileCoordinator (".forUploading") — ingen ekstra biblioteker.
    nonisolated static func zip(_ folder: URL) throws -> URL {
        var coordError: NSError?
        var copyError: Error?
        var result: URL?
        let dest = folder.deletingLastPathComponent().appendingPathComponent(folder.lastPathComponent + ".zip")
        NSFileCoordinator().coordinate(readingItemAt: folder, options: [.forUploading], error: &coordError) { zipURL in
            do {
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.copyItem(at: zipURL, to: dest)
                result = dest
            } catch { copyError = error }
        }
        if let e = coordError ?? copyError { throw e }
        guard let result else { throw StoreError.notFound }
        return result
    }

    /// Gør ordbogen klar til JSON: tomme valgfrie værdier bliver til null (ellers går JSONSerialization ned).
    nonisolated static func clean(_ value: Any) -> Any {
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional {
            guard let inner = mirror.children.first?.value else { return NSNull() }
            return clean(inner)
        }
        if let dict = value as? [String: Any] { return dict.mapValues { clean($0) } }
        if let array = value as? [Any] { return array.map { clean($0) } }
        return value
    }

    private static func imageExtension(_ data: Data) -> String {
        let b = [UInt8](data.prefix(12))
        if b.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if b.count >= 12, String(bytes: b[4..<12], encoding: .ascii)?.hasPrefix("ftyphei") == true { return "heic" }
        return "jpg"
    }

    private static func safe(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:?%*|\"<>\n\r\t")
        let cleaned = s.components(separatedBy: bad).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        let short = String(cleaned.prefix(60)).trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        return short.isEmpty ? "Uden navn" : short
    }

    private static func prefix(_ date: Date?) -> String {
        date.map { Fmt.iso($0) + " " } ?? ""
    }

    private static func placeJSON(_ p: Place?) -> [String: Any]? {
        p.map { ["navn": $0.name, "adresse": $0.address, "lat": $0.latitude, "lon": $0.longitude] }
    }

    private static func describe(title: String, date: String?, place: Place?, details: String, photos: PhotoSet) -> String {
        var t = title + "\n"
        if let date { t += date + "\n" }
        if let place { t += "Sted: \(place.name)" + (place.address.isEmpty ? "" : ", \(place.address)") + "\n" }
        if !details.isEmpty { t += "\n" + details + "\n" }
        let captions = photos.captions.enumerated().filter { !$0.element.isEmpty }
        if !captions.isEmpty {
            t += "\nBilledtekster\n"
            for (i, c) in captions { t += "  Billede \(i + 1): \(c)\n" }
        }
        return t
    }

    private static func readme(familyName: String) -> String {
        """
        \(familyName.isEmpty ? "Vores familie" : familyName) – eksport fra appen "Vores familie"
        Lavet \(Fmt.long(Date())).

        Her er alt, hvad I har gemt i appen:

        • Børn/ – en mappe pr. barn med højdepunkter, dagbog, milepæle, billedserier,
          breve, målinger (Målinger.csv kan åbnes i Excel/Numbers) og en PDF-mindebog.
          Oversigt.txt samler milepæle, vaccinationer og "Om mig".
        • Forseglede breve ligger i en mappe for sig med datoen for, hvornår de må åbnes.
        • Familie/ – fødselsdage, familietræ, traditioner, minder, opskrifter, begivenheder og rejser med billeder.
        • data.json – alt indhold i et maskinlæsbart format, som andre programmer kan bruge.

        Filnavnene starter med datoen (år-måned-dag), så de ligger i rækkefølge.
        """
    }
}

private extension Date {
    var isoDay: String { Fmt.iso(self) }
}
