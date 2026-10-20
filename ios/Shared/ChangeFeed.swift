import Foundation
import CloudKit

// Henter hvad der er ændret i iCloud siden sidst (pr. database og zone), og husker
// "change tokens" i App Group'en. Bruges af notifikations-udvidelsen til at finde ud af,
// hvem der har lagt hvad op — og af appen til at "så" tokens første gang, så udvidelsen
// aldrig skal gennemgå hele familiens historik.
enum ChangeFeed {
    static let containerID = "iCloud.net.prehn.mindebog"

    /// Kun disse felter hentes — aldrig billeder/video (udvidelsen har meget lidt hukommelse).
    private static let keys: [CKRecord.FieldKey] = ["childRef", "title", "text", "name", "caption", "key", "kind"]

    /// Ændrede records siden sidste kald. Opdaterer tokens.
    static func changes(scope: CKDatabase.Scope) async -> [CKRecord] {
        let db = CKContainer(identifier: containerID).database(with: scope)
        let zones = await changedZones(db: db, scope: scope)
        guard !zones.isEmpty else { return [] }
        return await records(db: db, zones: zones)
    }

    /// Første gang (ingen tokens): hent blot de nyeste tokens, så næste kald kun ser nyt.
    static func seedIfNeeded() async {
        for scope in [CKDatabase.Scope.private, .shared] where databaseToken(scope) == nil {
            _ = await changes(scope: scope)
        }
    }

    // MARK: Database → ændrede zoner

    private static func changedZones(db: CKDatabase, scope: CKDatabase.Scope) async -> [CKRecordZone.ID] {
        await withCheckedContinuation { continuation in
            var zones: [CKRecordZone.ID] = []
            let op = CKFetchDatabaseChangesOperation(previousServerChangeToken: databaseToken(scope))
            op.fetchAllChanges = true
            op.recordZoneWithIDChangedBlock = { zones.append($0) }
            op.changeTokenUpdatedBlock = { setDatabaseToken($0, scope) }
            op.fetchDatabaseChangesResultBlock = { result in
                if case .success(let (token, _)) = result { setDatabaseToken(token, scope) }
                continuation.resume(returning: zones.filter { $0.zoneName.hasPrefix("family_") || $0.zoneName.hasPrefix("child_") })
            }
            db.add(op)
        }
    }

    // MARK: Zoner → ændrede records

    private static func records(db: CKDatabase, zones: [CKRecordZone.ID]) async -> [CKRecord] {
        await withCheckedContinuation { continuation in
            var changed: [CKRecord] = []
            var configs: [CKRecordZone.ID: CKFetchRecordZoneChangesOperation.ZoneConfiguration] = [:]
            for zone in zones {
                let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
                config.previousServerChangeToken = zoneToken(zone)
                config.desiredKeys = keys
                configs[zone] = config
            }
            let op = CKFetchRecordZoneChangesOperation(recordZoneIDs: zones, configurationsByRecordZoneID: configs)
            op.fetchAllChanges = true
            op.recordWasChangedBlock = { _, result in
                if case .success(let record) = result { changed.append(record) }
            }
            op.recordZoneChangeTokensUpdatedBlock = { zone, token, _ in setZoneToken(token, zone) }
            op.recordZoneFetchResultBlock = { zone, result in
                if case .success(let (token, _, _)) = result { setZoneToken(token, zone) }
            }
            op.fetchRecordZoneChangesResultBlock = { _ in continuation.resume(returning: changed) }
            db.add(op)
        }
    }

    // MARK: Tokens i App Group'en

    private static func databaseToken(_ scope: CKDatabase.Scope) -> CKServerChangeToken? {
        token(forKey: "token.db.\(scope.rawValue)")
    }
    private static func setDatabaseToken(_ token: CKServerChangeToken?, _ scope: CKDatabase.Scope) {
        setToken(token, forKey: "token.db.\(scope.rawValue)")
    }
    private static func zoneToken(_ zone: CKRecordZone.ID) -> CKServerChangeToken? {
        token(forKey: "token.zone.\(zone.zoneName).\(zone.ownerName)")
    }
    private static func setZoneToken(_ token: CKServerChangeToken?, _ zone: CKRecordZone.ID) {
        setToken(token, forKey: "token.zone.\(zone.zoneName).\(zone.ownerName)")
    }

    private static func token(forKey key: String) -> CKServerChangeToken? {
        guard let data = AppGroup.defaults.data(forKey: key) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }
    private static func setToken(_ token: CKServerChangeToken?, forKey key: String) {
        guard let token,
              let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
        else { return }
        AppGroup.defaults.set(data, forKey: key)
    }
}
