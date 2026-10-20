import Foundation

// Indbakken mellem "Del → Vores familie" i Fotos og appen. Udvidelsen gemmer billederne og teksten
// her i App Group'en; appen henter dem, næste gang den åbnes, og gemmer dem som højdepunkter i iCloud.
// Sådan behøver udvidelsen hverken iCloud-adgang eller at vente på upload (den har kun få sekunder).
//
// En pakke er en mappe: share_inbox/<uuid>/meta.json + 1.jpg, 2.jpg …
enum ShareInbox {
    struct Meta: Codable {
        var childIds: [String]
        var text: String
        var date: Date?          // billedets optagelsesdato (det ældste billede), ellers nil
        var created: Date
        var photoCount: Int
    }

    struct Package {
        let folder: URL
        let meta: Meta
        var photos: [Data] {
            (1...max(meta.photoCount, 1)).compactMap { try? Data(contentsOf: folder.appendingPathComponent("\($0).jpg")) }
        }
    }

    static var root: URL? { AppGroup.containerURL?.appendingPathComponent("share_inbox", isDirectory: true) }

    /// Kaldes af udvidelsen. Meta skrives til sidst, så appen aldrig ser en halvfærdig pakke.
    static func add(childIds: [String], text: String, date: Date?, photos: [Data]) throws {
        guard let root else { throw CocoaError(.fileNoSuchFile) }
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (i, data) in photos.enumerated() {
            try data.write(to: folder.appendingPathComponent("\(i + 1).jpg"), options: .atomic)
        }
        let meta = Meta(childIds: childIds, text: text, date: date, created: Date(), photoCount: photos.count)
        try JSONEncoder().encode(meta).write(to: folder.appendingPathComponent("meta.json"), options: .atomic)
    }

    /// Kaldes af appen: de pakker, der venter, ældste først.
    static func pending() -> [Package] {
        guard let root, let folders = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        else { return [] }
        return folders.compactMap { folder in
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("meta.json")),
                  let meta = try? JSONDecoder().decode(Meta.self, from: data) else { return nil }
            return Package(folder: folder, meta: meta)
        }
        .sorted { $0.meta.created < $1.meta.created }
    }

    static func remove(_ package: Package) {
        try? FileManager.default.removeItem(at: package.folder)
    }
}
