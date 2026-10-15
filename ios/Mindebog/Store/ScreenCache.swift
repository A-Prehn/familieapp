import Foundation

// Lille disk-cache til skærmdata: vis det sidst kendte med det samme,
// hent friske data fra iCloud bagefter. Ligger i Caches (iOS må rydde den).
enum ScreenCache {
    private static var directory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("ScreenCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func url(_ key: String) -> URL {
        let safe = key.replacingOccurrences(of: "/", with: "_")
        return directory.appendingPathComponent(safe + ".json")
    }

    static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = try? Data(contentsOf: url(key)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T, key: String) {
        let target = url(key)
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(value) else { return }
            try? data.write(to: target, options: .atomic)
        }
    }

    static func clear() {
        try? FileManager.default.removeItem(at: directory)
    }
}
