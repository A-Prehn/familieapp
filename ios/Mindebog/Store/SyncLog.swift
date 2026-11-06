import Foundation
import os

// Måler, hvor lang tid hvert iCloud-kald tager (#61) og skriver det til Console (subsystem
// net.prehn.mindebog, kategori icloud) — nyttigt ved fejlsøgning. Ingen persondata: kun navn,
// varighed og antal.
enum SyncLog {
    private static let logger = Logger(subsystem: "net.prehn.mindebog", category: "icloud")

    /// Kører `work`, måler tiden og logger resultatet. `count` = fx antal records.
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
        logger.info("\(name, privacy: .public) \(Int(seconds * 1000)) ms \(count) stk\(failed ? " FEJL" : "", privacy: .public)")
    }
}
