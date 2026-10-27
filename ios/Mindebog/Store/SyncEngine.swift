import CloudKit
import Foundation

// Henter "hvad er ændret siden sidst" fra iCloud og lægger det i den lokale kopi (#62).
// To trin, som Apple anbefaler: database-ændringer (hvilke zoner er nye/ændrede/slettede) og
// derefter zone-ændringer (records) med gemte change tokens. Første gang hentes alt.
//
// Tokens gemmes i appens egne UserDefaults — IKKE dem i App Group'en, som notifikations-
// udvidelsen bruger og "forbruger" (ChangeFeed).
//
// actor: to skærme, der beder om samme zone samtidig, deler én hentning (inflight) i stedet
// for at hente dobbelt og skrive tokens i forkert rækkefølge.
actor SyncEngine {
    let container: CKContainer
    let local: LocalRecords
    private var lastFullSync: Date = .distantPast
    private var inflightAll: Task<Outcome, Error>?
    private var inflightZones: [CKRecordZone.ID: Task<Int, Error>] = [:]

    init(container: CKContainer, local: LocalRecords) {
        self.container = container
        self.local = local
    }

    struct Outcome: Sendable {
        var changedZones: [CKRecordZone.ID] = []
        var deletedZones: [CKRecordZone.ID] = []
        var records = 0
        var anythingChanged: Bool { !changedZones.isEmpty || !deletedZones.isEmpty }
    }

    // MARK: Hele vejen rundt

    /// Begge databaser. `throttle`: spring over, hvis der er synkroniseret for nylig (fx ved hver aktivering).
    @discardableResult
    func syncAll(throttle: TimeInterval = 0, qos: QualityOfService = .userInitiated) async throws -> Outcome {
        if Date().timeIntervalSince(lastFullSync) < throttle { return Outcome() }
        if let running = inflightAll { return try await running.value }
        let task = Task<Outcome, Error> {
            var total = Outcome()
            var firstError: Error?
            for scope in [CKDatabase.Scope.private, .shared] {
                do {
                    let r = try await self.sync(scope: scope, qos: qos)
                    total.changedZones += r.changedZones
                    total.deletedZones += r.deletedZones
                    total.records += r.records
                } catch {
                    firstError = firstError ?? error
                }
            }
            if let firstError, !total.anythingChanged { throw firstError }
            return total
        }
        inflightAll = task
        defer { inflightAll = nil }
        do {
            let total = try await task.value
            lastFullSync = Date()
            await SyncStatus.shared.finished()
            return total
        } catch {
            await SyncStatus.shared.failed(error)
            throw error
        }
    }

    /// Én database: find ændrede zoner, hent deres ændringer.
    func sync(scope: CKDatabase.Scope, qos: QualityOfService = .userInitiated) async throws -> Outcome {
        let db = container.database(with: scope)
        let (changed, deleted, token) = try await SyncLog.measure("db-ændringer \(scope.label)") {
            try await databaseChanges(db: db, scope: scope, qos: qos)
        }
        var result = Outcome(changedZones: [], deletedZones: deleted)
        for zone in deleted {
            local.purge(zone)
            Self.setZoneToken(nil, zone)
        }
        let wanted = changed.filter { Self.isOurs($0) }
        if !wanted.isEmpty {
            result.records = try await fetchZones(wanted, db: db, qos: qos)
            result.changedZones = wanted
        }
        // Database-tokenet gemmes først, når zonerne er hentet — ellers kunne en ændring gå tabt.
        Self.setDatabaseToken(token, scope)
        return result
    }

    /// Hent bestemte zoner nu (fx første gang en skærm beder om en zone, der ikke er i kopien).
    /// Er en zone allerede ved at blive hentet, ventes der på den hentning.
    @discardableResult
    func fetchZones(_ zones: [CKRecordZone.ID], db: CKDatabase, qos: QualityOfService = .userInitiated) async throws -> Int {
        var fresh: [CKRecordZone.ID] = []
        var waitFor: [Task<Int, Error>] = []
        for zone in zones {
            if let running = inflightZones[zone] { waitFor.append(running) } else { fresh.append(zone) }
        }
        var total = 0
        if !fresh.isEmpty {
            let wanted = fresh
            let task = Task<Int, Error> {
                var sum = 0
                // CloudKit tager mange zoner i én operation, men ikke for mange ad gangen.
                for start in stride(from: 0, to: wanted.count, by: 8) {
                    let chunk = Array(wanted[start..<min(start + 8, wanted.count)])
                    sum += try await SyncLog.measure("zone-ændringer \(db.databaseScope.label) ×\(chunk.count)", {
                        try await self.zoneChanges(chunk, db: db, qos: qos)
                    }, count: { $0 })
                }
                return sum
            }
            for zone in fresh { inflightZones[zone] = task }
            defer { for zone in fresh { inflightZones[zone] = nil } }
            total = try await task.value
        }
        for t in waitFor { _ = try await t.value }
        return total
    }

    /// Familie- og barnezoner. Standardzonen og fremmede zoner springes over.
    static func isOurs(_ zone: CKRecordZone.ID) -> Bool {
        zone.zoneName.hasPrefix("family_") || zone.zoneName.hasPrefix(CloudKitStore.childZonePrefix)
    }

    // MARK: Database → zoner

    private func databaseChanges(db: CKDatabase, scope: CKDatabase.Scope, qos: QualityOfService) async throws
        -> (changed: [CKRecordZone.ID], deleted: [CKRecordZone.ID], token: CKServerChangeToken?) {
        try await withCheckedThrowingContinuation { continuation in
            let box = ZoneBox()
            let op = CKFetchDatabaseChangesOperation(previousServerChangeToken: Self.databaseToken(scope))
            op.fetchAllChanges = true
            op.qualityOfService = qos
            op.recordZoneWithIDChangedBlock = { box.changed.append($0) }
            op.recordZoneWithIDWasDeletedBlock = { box.deleted.append($0) }
            op.recordZoneWithIDWasPurgedBlock = { box.deleted.append($0) }
            op.recordZoneWithIDWasDeletedDueToUserEncryptedDataResetBlock = { box.deleted.append($0) }
            op.fetchDatabaseChangesResultBlock = { result in
                switch result {
                case .success(let (token, _)):
                    continuation.resume(returning: (box.changed, box.deleted, token))
                case .failure(let error):
                    if let ck = error as? CKError, ck.code == .changeTokenExpired {
                        // Forældet token: glem det, og begynd forfra næste gang (aldrig en tom liste).
                        Self.setDatabaseToken(nil, scope)
                    }
                    continuation.resume(throwing: error)
                }
            }
            db.add(op)
        }
    }

    // MARK: Zoner → records

    /// Henter ændringerne i zonerne og lægger dem i kopien. Returnerer antal ændrede records.
    private func zoneChanges(_ zones: [CKRecordZone.ID], db: CKDatabase, qos: QualityOfService) async throws -> Int {
        let first = try await zoneChangesOnce(zones, db: db, qos: qos)
        guard !first.expired.isEmpty else { return first.count }
        // Forældet zone-token: smid kopien af zonen væk, og hent den forfra.
        for zone in first.expired { local.purge(zone); Self.setZoneToken(nil, zone) }
        let again = try await zoneChangesOnce(first.expired, db: db, qos: qos)
        return first.count + again.count
    }

    private func zoneChangesOnce(_ zones: [CKRecordZone.ID], db: CKDatabase, qos: QualityOfService) async throws
        -> (count: Int, expired: [CKRecordZone.ID]) {
        let local = self.local
        return try await withCheckedThrowingContinuation { continuation in
            let box = RecordBox()
            var configs: [CKRecordZone.ID: CKFetchRecordZoneChangesOperation.ZoneConfiguration] = [:]
            for zone in zones {
                let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
                config.previousServerChangeToken = Self.zoneToken(zone)
                config.desiredKeys = LocalRecords.fieldKeys
                configs[zone] = config
            }
            let op = CKFetchRecordZoneChangesOperation(recordZoneIDs: zones, configurationsByRecordZoneID: configs)
            op.fetchAllChanges = true
            op.qualityOfService = qos
            op.recordWasChangedBlock = { id, result in
                if case .success(let record) = result {
                    box.changed[id.zoneID, default: []].append(record)
                    box.total += 1
                    if box.total % 50 == 0 { let n = box.total; Task { await SyncStatus.shared.progress(records: n) } }
                }
            }
            op.recordWithIDWasDeletedBlock = { id, _ in
                box.deleted[id.zoneID, default: []].append(id)
            }
            op.recordZoneFetchResultBlock = { zone, result in
                switch result {
                case .success(let (token, _, _)):
                    box.tokens[zone] = token
                case .failure(let error):
                    if let ck = error as? CKError, ck.code == .changeTokenExpired { box.expired.append(zone) }
                }
            }
            op.fetchRecordZoneChangesResultBlock = { result in
                switch result {
                case .success:
                    // Først records i kopien, så tokens — stopper appen midt i, hentes zonen bare igen.
                    for zone in zones where !box.expired.contains(zone) {
                        local.apply(changed: box.changed[zone] ?? [], deleted: box.deleted[zone] ?? [], in: zone)
                        if let token = box.tokens[zone] { Self.setZoneToken(token, zone) }
                    }
                    continuation.resume(returning: (box.total, box.expired))
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            db.add(op)
        }
    }

    /// Samler det, CloudKits blokke melder (de kaldes én ad gangen på operationens kø).
    private final class ZoneBox: @unchecked Sendable {
        var changed: [CKRecordZone.ID] = []
        var deleted: [CKRecordZone.ID] = []
    }
    private final class RecordBox: @unchecked Sendable {
        var changed: [CKRecordZone.ID: [CKRecord]] = [:]
        var deleted: [CKRecordZone.ID: [CKRecord.ID]] = [:]
        var tokens: [CKRecordZone.ID: CKServerChangeToken] = [:]
        var expired: [CKRecordZone.ID] = []
        var total = 0
    }

    // MARK: Tokens

    private static let prefix = "mindebog.sync."

    private static func databaseToken(_ scope: CKDatabase.Scope) -> CKServerChangeToken? {
        token(forKey: prefix + "db.\(scope.rawValue)")
    }
    private static func setDatabaseToken(_ token: CKServerChangeToken?, _ scope: CKDatabase.Scope) {
        setToken(token, forKey: prefix + "db.\(scope.rawValue)")
    }
    private static func zoneToken(_ zone: CKRecordZone.ID) -> CKServerChangeToken? {
        token(forKey: prefix + "zone.\(zone.zoneName).\(zone.ownerName)")
    }
    private static func setZoneToken(_ token: CKServerChangeToken?, _ zone: CKRecordZone.ID) {
        setToken(token, forKey: prefix + "zone.\(zone.zoneName).\(zone.ownerName)")
    }

    private static func token(forKey key: String) -> CKServerChangeToken? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }
    private static func setToken(_ token: CKServerChangeToken?, forKey key: String) {
        guard let token else { UserDefaults.standard.removeObject(forKey: key); return }
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// "Hent alt igen": glem tokens og kopien, så næste sync henter alt forfra.
    func reset() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(Self.prefix) {
            defaults.removeObject(forKey: key)
        }
        local.purgeAll()
        lastFullSync = .distantPast
    }
}

extension CKDatabase.Scope {
    var label: String {
        switch self {
        case .private: return "privat"
        case .shared: return "delt"
        case .public: return "offentlig"
        @unknown default: return "?"
        }
    }
}

/// Hvad sync laver lige nu — til banneret ("Henter familien … 120") og "Hent alt igen" under Mere.
@MainActor
final class SyncStatus: ObservableObject {
    static let shared = SyncStatus()

    /// En zone hentes for første gang — brugeren venter på den.
    @Published private(set) var fetching = false
    @Published private(set) var fetchedRecords = 0
    @Published private(set) var lastSync: Date?
    @Published private(set) var lastError: String?

    func started() {
        fetching = true
        fetchedRecords = 0
    }

    func progress(records: Int) {
        if fetching { fetchedRecords = records }
    }

    func finished() {
        fetching = false
        lastSync = Date()
        lastError = nil
    }

    func failed(_ error: Error) {
        fetching = false
        lastError = error.userMessage
    }
}
