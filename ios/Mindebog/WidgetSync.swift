import Foundation
import WidgetKit

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
            case .vacation: kind = "Ferie"
            case .memory: kind = "Minde"
            default: return nil   // "På denne dag" bruger kun de klassiske minder
            }
            let who = s.childId.flatMap { names[$0] } ?? "Familie"
            return .init(who: who, kind: kind, text: s.text, date: date)
        }
        .suffix(2000)
        .map { $0 }

        snapshot.save()
        SharedNames.children = names
        _ = try? await store.members(familyId: familyId)   // opdaterer medlemsnavnene i App Group'en
        WidgetCenter.shared.reloadAllTimelines()
    }
}
