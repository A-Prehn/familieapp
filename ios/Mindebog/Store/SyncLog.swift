import Foundation
import os

// Måler, hvor lang tid hvert iCloud-kald tager (#61). De sidste 300 målinger ligger i hukommelsen
// og kan ses under Mere → "iCloud-tider" i TestFlight- og Debug-builds. Skrives også til Console
// (subsystem net.prehn.mindebog, kategori icloud). Ingen persondata: kun navn, varighed og antal.
enum SyncLog {
    struct Entry: Identifiable {
        let id = UUID()
        let name: String
        let seconds: Double
        let count: Int
        let failed: Bool
        let at: Date
    }

    private static let logger = Logger(subsystem: "net.prehn.mindebog", category: "icloud")
    private static let lock = NSLock()
    private static var entries: [Entry] = []
    private static let maxEntries = 300

    /// TestFlight (sandbox-kvittering) eller Debug: så vises målingerne i appen.
    static let isVisible: Bool = {
        #if DEBUG
        return true
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }()

    /// Kører `work`, måler tiden og husker resultatet. `count` = fx antal records (vises i tabellen).
    static func measure<T>(_ name: String, _ work: () async throws -> T, count: (T) -> Int = { _ in 0 }) async rethrows -> T {
        let start = ContinuousClock.now
        do {
            let result = try await work()
            note(name, start: start, count: count(result), failed: false)
            return result
        } catch {
            note(name, start: start, count: 0, failed: true)
            throw error
        }
    }

    static func note(_ name: String, start: ContinuousClock.Instant, count: Int, failed: Bool) {
        let elapsed = (ContinuousClock.now - start).components
        let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
        let entry = Entry(name: name, seconds: seconds, count: count, failed: failed, at: Date())
        lock.lock()
        entries.append(entry)
        if entries.count > maxEntries { entries.removeFirst(entries.count - maxEntries) }
        lock.unlock()
        logger.info("\(name, privacy: .public) \(Int(seconds * 1000)) ms \(count) stk\(failed ? " FEJL" : "", privacy: .public)")
    }

    /// Nyeste først.
    static var recent: [Entry] {
        lock.lock(); defer { lock.unlock() }
        return entries.reversed()
    }

    /// Opsummering pr. navn: antal kald, samlet tid, gennemsnit, største — sorteret efter samlet tid.
    struct Summary: Identifiable {
        var id: String { name }
        let name: String
        let calls: Int
        let total: Double
        let max: Double
        let failures: Int
        var average: Double { calls == 0 ? 0 : total / Double(calls) }
    }

    static var summary: [Summary] {
        lock.lock(); defer { lock.unlock() }
        var byName: [String: (calls: Int, total: Double, max: Double, failures: Int)] = [:]
        for e in entries {
            var s = byName[e.name] ?? (0, 0, 0, 0)
            s.calls += 1; s.total += e.seconds; s.max = Swift.max(s.max, e.seconds); if e.failed { s.failures += 1 }
            byName[e.name] = s
        }
        return byName.map { Summary(name: $0.key, calls: $0.value.calls, total: $0.value.total, max: $0.value.max, failures: $0.value.failures) }
            .sorted { $0.total > $1.total }
    }

    static func clear() {
        lock.lock(); entries.removeAll(); lock.unlock()
    }
}
