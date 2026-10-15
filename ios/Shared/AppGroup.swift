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

    var familyName: String = "Vores familie"
    var birthdays: [Birthday] = []
    var due: [Due] = []
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
