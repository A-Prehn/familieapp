import Foundation

// Delt mellem appen, widgetten og notifikations-udvidelsen via App Group'en.
// Appen skriver; udvidelserne læser (de har ikke selv adgang til hele familiens data).
enum AppGroup {
    static let id = "group.net.prehn.mindebog"
    static var defaults: UserDefaults { UserDefaults(suiteName: id) ?? .standard }
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
    }
}

/// Det widgetten viser — skrevet af appen, hver gang Hjem indlæses.
struct WidgetSnapshot: Codable {
    struct Birthday: Codable, Hashable {
        var name: String
        var emoji: String
        var date: Date          // fødselsdato (år bruges til "fylder X")
    }
    struct Due: Codable, Hashable {
        var name: String
        var dueDate: Date
    }
    struct Memory: Codable, Hashable {
        var who: String         // barnets navn eller "Fælles"
        var kind: String        // "Højdepunkt", "Begivenhed" …
        var text: String
        var date: Date
    }

    struct ChildInfo: Codable, Hashable {
        var name: String
        var birthDate: Date?
        var dueDate: Date?
    }

    var familyName: String = "Vores familie"
    var birthdays: [Birthday] = []
    var due: [Due] = []
    var children: [ChildInfo] = []   // til "I dag"-kortet (månedsdag, graviditetsuge)
    var memories: [Memory] = []    // kun tekst og dato — widgetten finder selv "På denne dag"
    var updatedAt: Date = Date()

    private static var fileURL: URL? { AppGroup.containerURL?.appendingPathComponent("widget.json") }

    static func load() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        guard let url = Self.fileURL, let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

/// Navne til notifikationerne ("Sheila har tilføjet et højdepunkt for Theo").
enum SharedNames {
    private static let childKey = "names.children"     // childId -> navn
    private static let memberKey = "names.members"     // userRecordName -> navn

    static var children: [String: String] {
        get { AppGroup.defaults.dictionary(forKey: childKey) as? [String: String] ?? [:] }
        set { AppGroup.defaults.set(newValue, forKey: childKey) }
    }
    static var members: [String: String] {
        get { AppGroup.defaults.dictionary(forKey: memberKey) as? [String: String] ?? [:] }
        set { AppGroup.defaults.set(newValue, forKey: memberKey) }
    }
}

/// De seneste notifikationer — til klokken på Hjem. Notifikations-udvidelsen skriver, når der kommer
/// nyt fra familien; appen tilføjer påmindelser, når de vises. Højst 60, nyeste først.
struct NotificationLogEntry: Codable, Hashable, Identifiable {
    var id: String
    var date: Date
    var title: String
    var body: String
    /// CloudKit-recordtype ("Highlight", "Memory" …) eller "reminder".
    var kind: String
    var recordId: String? = nil
    var childId: String? = nil
    /// Til påmindelser: deep link-oplysninger (fx barn og spørgsmål).
    var info: [String: String] = [:]
}

enum NotificationLog {
    private static var fileURL: URL? { AppGroup.containerURL?.appendingPathComponent("notifications.json") }
    private static let seenKey = "notifications.lastSeen"

    static func load() -> [NotificationLogEntry] {
        guard let url = fileURL, let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([NotificationLogEntry].self, from: data) else { return [] }
        return list
    }

    static func append(_ entry: NotificationLogEntry) {
        var list = load().filter { $0.id != entry.id }
        list.insert(entry, at: 0)
        list.sort { $0.date > $1.date }
        save(Array(list.prefix(60)))
    }

    static func save(_ list: [NotificationLogEntry]) {
        guard let url = fileURL, let data = try? JSONEncoder().encode(list) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func clear() { save([]) }

    /// Hvornår klokken sidst blev åbnet — alt nyere tæller som ulæst.
    static var lastSeen: Date {
        get { AppGroup.defaults.object(forKey: seenKey) as? Date ?? .distantPast }
        set { AppGroup.defaults.set(newValue, forKey: seenKey) }
    }
    static var unreadCount: Int { load().filter { $0.date > lastSeen }.count }
}
