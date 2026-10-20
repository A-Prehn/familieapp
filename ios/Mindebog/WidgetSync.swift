import Foundation
import WidgetKit
import UIKit

// Skriver det widgetten og notifikations-udvidelsen skal bruge til App Group'en:
// fødselsdage, termin, minder (kun tekst/dato) og barnenavne. Kaldes når Hjem indlæses.
enum WidgetSync {
    // Kører kun, når noget er gemt siden sidst, eller der er gået 10 minutter —
    // ellers koster hver åbning af Hjem tre ekstra opslag i iCloud.
    private static var lastRun: Date?
    private static var dirty = true
    private static let observer: Void = {
        NotificationCenter.default.addObserver(forName: .storeDidChange, object: nil, queue: nil) { _ in dirty = true }
    }()

    /// Kaldes ved opstart, så en gemt fødselsdag altid markerer widgetten som forældet —
    /// også hvis den gemmes, før Hjem første gang har opdateret widgetten.
    static func start() { _ = observer }

    static func refresh(store: Store, familyId: String, familyName: String, force: Bool = false) async {
        _ = observer
        if !force, !dirty, let last = lastRun, Date().timeIntervalSince(last) < 600 { return }
        dirty = false
        lastRun = Date()
        async let childrenTask = store.children(familyId: familyId)
        async let customTask = store.birthdays(familyId: familyId)
        async let summariesTask = store.memorySummaries(familyId: familyId)
        guard let children = try? await childrenTask else { dirty = true; return }
        let custom = (try? await customTask) ?? []
        let summaries = (try? await summariesTask) ?? []

        var snapshot = WidgetSnapshot()
        snapshot.familyName = familyName

        snapshot.children = children.map { .init(name: $0.name, birthDate: $0.birthDate, dueDate: $0.dueDate) }
        for child in children {
            if let birth = child.birthDate {
                let emoji = child.gender == .girl ? "👧" : (child.gender == .boy ? "👦" : "🧒")
                snapshot.birthdays.append(.init(name: child.name, emoji: emoji, date: birth))
            } else if let due = child.dueDate, due > Date() {
                snapshot.due.append(.init(name: child.name, dueDate: due))
            }
        }
        snapshot.birthdays += custom.map { .init(name: $0.name, emoji: $0.emoji, date: $0.date) }

        let names = Dictionary(uniqueKeysWithValues: children.map { ($0.id, $0.name) })
        snapshot.memories = summaries.compactMap { s in
            guard let date = s.date, !s.text.isEmpty else { return nil }
            let kind: String
            switch s.kind {
            case .highlight: kind = "Højdepunkt"
            case .diary: kind = "Dagbog"
            case .event: kind = "Begivenhed"
            case .vacation: kind = "Rejse"
            case .memory: kind = "Minde"
            default: return nil   // "På denne dag" bruger kun de klassiske minder
            }
            let who = s.childId.flatMap { names[$0] } ?? "Familie"
            return .init(who: who, kind: kind, text: s.text, date: date)
        }
        .suffix(2000)
        .map { $0 }

        // Små billeder til "På denne dag" de næste dage — widgetten kan ikke selv hente fra iCloud.
        snapshot.memories = await attachPhotos(snapshot.memories, summaries: summaries, store: store, familyId: familyId)

        snapshot.save()
        SharedNames.children = names
        _ = try? await store.members(familyId: familyId)   // opdaterer medlemsnavnene i App Group'en
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Henter forsidebilledet til de minder, der er "på denne dag" inden for de næste dage (højst otte),
    /// gemmer dem små i App Group'en og peger på filen fra snapshottet. Gamle filer ryddes.
    private static func attachPhotos(_ memories: [WidgetSnapshot.Memory], summaries: [MemorySummary],
                                     store: Store, familyId: String) async -> [WidgetSnapshot.Memory] {
        guard let dir = AppGroup.containerURL?.appendingPathComponent("widget_photos", isDirectory: true) else { return memories }
        let fm = FileManager.default
        try? fm.removeItem(at: dir)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let thisYear = cal.component(.year, from: today)
        func daysAhead(_ date: Date) -> Int? {
            guard cal.component(.year, from: date) < thisYear else { return nil }
            var c = cal.dateComponents([.month, .day], from: date); c.year = thisYear
            guard let d = cal.date(from: c), let n = cal.dateComponents([.day], from: today, to: d).day, (0...7).contains(n) else { return nil }
            return n
        }
        // Samme rækkefølge som widgetten: nærmeste dag først, så det nyeste år.
        let soon = summaries.filter { $0.date != nil && !$0.text.isEmpty && daysAhead($0.date!) != nil }
            .sorted { (daysAhead($0.date!)!, $1.date!) < (daysAhead($1.date!)!, $0.date!) }
            .prefix(8)
        var out = memories
        for s in soon {
            guard let i = out.firstIndex(where: { $0.text == s.text && $0.date == s.date }),
                  let data = try? await store.coverPhoto(familyId: familyId, memory: s),
                  let thumb = ImageTools.thumbnail(data, maxPixel: 400),
                  let jpeg = thumb.jpegData(compressionQuality: 0.8) else { continue }
            let name = s.id + ".jpg"
            if (try? jpeg.write(to: dir.appendingPathComponent(name), options: .atomic)) != nil {
                out[i].photoFile = "widget_photos/" + name
            }
        }
        return out
    }
}
