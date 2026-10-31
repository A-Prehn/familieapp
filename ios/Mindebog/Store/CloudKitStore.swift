import Foundation
import CloudKit
import CoreLocation
import CryptoKit
import Network

// CloudKit-implementering af Store — ægte lagring i brugerens egen iCloud.
//
// Model:
//   Hver familie ligger i sin egen record-zone i ejerens private database.
//   Zonen deles med partneren via CKShare (zone-deling) → partneren ser den
//   i sin "shared database". Alle records har en reference til Family/Child.
//   Fotos gemmes som CKAsset.
//
// Deling: createInvite returnerer share-URL'en; acceptInvite tager en URL.
// Identitet: iCloud-kontoen (CKContainer.userRecordID) — ingen egen server.
// actor (ikke class): flere skærme indlæser samtidig, og zoneCache må ikke
// skrives fra to tråde på én gang.
actor CloudKitStore: Store {
    private let container: CKContainer
    private var privateDB: CKDatabase { container.privateCloudDatabase }
    private var sharedDB: CKDatabase { container.sharedCloudDatabase }

    // familyId == zoneName. Husker hvilken database zonen ligger i.
    private var zoneCache: [String: (db: CKDatabase, zone: CKRecordZone.ID)] = [:]
    private let nameKey = "mindebog.displayName"

    // Den lokale kopi (#62): skærmene læser herfra; SyncEngine henter kun ændringer fra iCloud.
    private let local = LocalRecords()
    private let sync: SyncEngine

    init(containerIdentifier: String = "iCloud.net.prehn.mindebog") {
        self.container = CKContainer(identifier: containerIdentifier)
        self.sync = SyncEngine(container: container, local: local)
        // Thumbs fra sync lægges i billedcachen (CloudKits midlertidige fil forsvinder ellers).
        LocalRecords.keepAsset = { record, key in _ = AssetCache.store(record, key: key) }
        Self.clearUploadDir()   // ingen uploads kører endnu ved oprettelse
        Task.detached(priority: .background) { AssetCache.prune() }
    }

    // MARK: - Originaler eller thumbs (#62)
    // Lister får kun det lille forsidebillede (thumb) og originalerne fra cachen; det, der mangler,
    // hentes i baggrunden. Redigering, fuld skærm, eksport og film beder om originalerne med
    // `withOriginals { … }` — så ventes der på iCloud som før.

    static let thumbKey = LocalRecords.thumbKey
    @TaskLocal static var wantOriginals = false

    /// Kør `body` med originalerne hentet (fx før redigering eller fuld skærm).
    static func withOriginals<T>(_ body: () async throws -> T) async rethrows -> T {
        try await $wantOriginals.withValue(true) { try await body() }
    }

    /// Er alle originaler i `keys` i cachen (eller kendt tomme)? Så må modellen gemme billederne igen.
    private static func assetsLoaded(_ record: CKRecord, keys: [String]) -> Bool {
        keys.allSatisfy { AssetCache.read(record, key: $0) != nil }
    }

    /// Forsidebilledets data på en record (photos[coverIndex], ellers photo).
    private static func coverData(_ record: CKRecord) -> Data? {
        if let list = record["photos"] as? [CKAsset], !list.isEmpty {
            let i = (record["coverIndex"] as? Int64).map(Int.init) ?? 0
            let asset = list.indices.contains(i) ? list[i] : list[0]
            return asset.fileURL.flatMap { try? Data(contentsOf: $0) }
        }
        return assetData(record["photo"])
    }

    /// Lægger et thumb på recorden før gem: når der er nye billeder med (uploads), når den ikke
    /// har et endnu (ældre gem), eller når det er et lille fra 1.3. Uden billeder fjernes det.
    private static func addThumb(to record: CKRecord) {
        let prefix = uploadDir.standardizedFileURL.path
        var assets: [CKAsset] = []
        if let one = record["photo"] as? CKAsset { assets.append(one) }
        if let many = record["photos"] as? [CKAsset] { assets += many }
        let hasUpload = assets.contains { $0.fileURL?.standardizedFileURL.path.hasPrefix(prefix) == true }
        let data = coverData(record)
        guard hasUpload || record[thumbKey] == nil || isSmallThumb(record[thumbKey], original: data) else { return }
        guard let data else {
            if assets.isEmpty { record[thumbKey] = nil }
            return
        }
        guard let small = ImageTools.thumbnail(data), let asset = asset(from: small) else { return }
        record[thumbKey] = asset
    }

    /// Originaler, der mangler i cachen, hentes i baggrunden — så de er klar, når man åbner noget.
    private var prefetching: Set<CKRecord.ID> = []
    private func schedulePrefetch(_ records: [CKRecord], keys: [String], db: CKDatabase) {
        let ids = records.map(\.recordID).filter { !prefetching.contains($0) }
        guard !ids.isEmpty else { return }
        prefetching.formUnion(ids)
        Task(priority: .utility) { await self.prefetch(ids, keys: keys, db: db) }
    }

    private func prefetch(_ ids: [CKRecord.ID], keys: [String], db: CKDatabase) async {
        defer { for id in ids { prefetching.remove(id) } }
        var fetchedAny = false
        var i = 0
        while i < ids.count {
            let chunk = Array(ids[i..<min(i + 10, ids.count)])
            i += 10
            guard let fetched = try? await SyncLog.measure("billeder i baggrunden ×\(chunk.count)", {
                try await db.records(for: chunk, desiredKeys: keys)
            }, count: { $0.count }) else { continue }
            var stored: [CKRecord] = []
            for id in chunk {
                guard let full = try? fetched[id]?.get() else { continue }
                for k in keys { _ = AssetCache.store(full, key: k) }
                stored.append(full)
                fetchedAny = true
            }
            Self.refreshThumbs(stored)
        }
        // Listerne indlæser igen og får originalerne (fra cachen) — og kan nu redigere/vise i fuld skærm.
        if fetchedAny { await MainActor.run { NotificationCenter.default.post(name: .storeDidChange, object: nil) } }
    }

    /// Ældre records uden thumb i iCloud, eller med et lille fra 1.3: lav et af originalen, og gem det
    /// i cachen til næste gang. Originalerne hentes alligevel i baggrunden, så kopien opgraderes af sig selv.
    /// Kører uden for actoren: at afkode og genkode billeder for hver record ville ellers blokere alle
    /// andre kald til storen (lige efter opdateringen er alle thumbs fra 1.3 små). Lister får besked bagefter.
    private static func refreshThumbs(_ records: [CKRecord]) {
        guard !records.isEmpty else { return }
        Task.detached(priority: .utility) {
            var changed = false
            for record in records where cacheThumbIfMissing(record) { changed = true }
            if changed { await MainActor.run { NotificationCenter.default.post(name: .storeDidChange, object: nil) } }
        }
    }

    /// true = et nyt thumb blev lagt i cachen.
    @discardableResult
    private static func cacheThumbIfMissing(_ record: CKRecord) -> Bool {
        let cached = AssetCache.read(record, key: thumbKey)
        guard let data = coverData(record) else { return false }
        guard cached == nil || isSmallThumb(cached ?? nil, original: data),
              let small = ImageTools.thumbnail(data) else { return false }
        AssetCache.storeData(small, for: record, key: thumbKey)
        return true
    }

    private static func isSmallThumb(_ value: CKRecordValue?, original: Data?) -> Bool {
        guard let url = (value as? CKAsset)?.fileURL, let data = try? Data(contentsOf: url) else { return false }
        return ImageTools.isSmallThumb(data, original: original)
    }

    // MARK: - Sync (den lokale kopi)

    /// Hent ændringer fra iCloud nu (fx træk-for-at-opdatere). true = noget var ændret.
    @discardableResult
    func refresh() async throws -> Bool {
        try await sync.syncAll().anythingChanged
    }

    /// Hent ændringer, hvis det er mere end et minut siden (ved opstart og aktivering). Fejl sluges:
    /// kopien fra sidst er stadig god. true = noget var ændret, så skærmene bør indlæse igen.
    func syncIfStale(seconds: TimeInterval = 60) async -> Bool {
        (try? await sync.syncAll(throttle: seconds).anythingChanged) ?? false
    }

    /// "Hent alt igen" under Mere: smid kopien væk, og hent alt forfra. Intet i iCloud røres.
    func resetLocalCopy() async throws {
        await forgetLocalCopy()
        try await sync.syncAll()
    }

    /// Ved log ud: kopien hører til den bruger, der var logget ind.
    func forgetLocalCopy() async {
        await sync.reset()
        zoneCache.removeAll()
        UserDefaults.standard.removeObject(forKey: Self.zoneIndexKey)
        UserDefaults.standard.removeObject(forKey: Self.childZoneKey)
    }

    /// Stille push ved ændringer i iCloud (#62): så hentes nyt fra de andre i familien inden for sekunder,
    /// uden at brugeren behøver have notifikationer slået til. Oprettes én gang pr. installation.
    func registerSyncPush() async {
        let key = "mindebog.sync.push.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        func subscription(_ id: String) -> CKDatabaseSubscription {
            let sub = CKDatabaseSubscription(subscriptionID: id)
            let info = CKSubscription.NotificationInfo()
            info.shouldSendContentAvailable = true   // stille: ingen banner, ingen lyd
            sub.notificationInfo = info
            return sub
        }
        do {
            _ = try await privateDB.modifySubscriptions(saving: [subscription("mindebog-sync-private")], deleting: [])
            _ = try await sharedDB.modifySubscriptions(saving: [subscription("mindebog-sync-shared")], deleting: [])
            UserDefaults.standard.set(true, forKey: key)
        } catch {
            // Prøves igen ved næste opstart.
        }
    }

    /// Hvilken database en zone hører til: egne zoner har standard-ejeren, delte zoner ejerens id.
    private func database(for zone: CKRecordZone.ID) -> CKDatabase {
        zone.ownerName == CKCurrentUserDefaultName ? privateDB : sharedDB
    }

    /// Sørger for, at zonen findes i kopien. Første gang hentes hele zonen (brugeren venter, med banner);
    /// derefter er kopien altid klar, og nyt kommer via syncIfStale/refresh.
    private func ensureSynced(_ zoneID: CKRecordZone.ID, db: CKDatabase) async throws {
        if local.hasSnapshot(zoneID) { return }
        await SyncStatus.shared.started()
        do {
            try await sync.fetchZones([zoneID], db: db)
            await SyncStatus.shared.finished()
        } catch {
            await SyncStatus.shared.failed(error)
            throw error
        }
    }

    // MARK: - Auth

    func signIn(name: String) async throws -> AppUser {
        let recordID = try await container.userRecordID()
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let display = trimmed.isEmpty ? "Forælder" : trimmed
        UserDefaults.standard.set(display, forKey: nameKey)
        return AppUser(id: recordID.recordName, name: display)
    }

    func user(id: String) async throws -> AppUser? {
        let name = UserDefaults.standard.string(forKey: nameKey) ?? "Forælder"
        return AppUser(id: id, name: name)
    }

    // MARK: - Familie

    func families(for userId: String) async throws -> [Family] {
        // Familierne er zonerne i den lokale kopi. Først hentes ændringer fra iCloud (to små kald,
        // sprunget over hvis det lige er gjort). Fejler det, bruges kopien fra sidst — så en
        // bedsteforælders familie "forsvinder" ikke, bare fordi nettet var væk et øjeblik (#60).
        // Kun hvis der slet ingen kopi er, kastes fejlen videre.
        do {
            try await sync.syncAll(throttle: 3)
        } catch {
            if local.snapshotZones().isEmpty { throw error }
        }
        var result: [Family] = []
        for zoneID in local.snapshotZones() {
            let db = database(for: zoneID)
            // Barnezoner (børn delt med fx den anden forælder) huskes også, så locate() finder dem.
            if zoneID.zoneName.hasPrefix(Self.childZonePrefix) { remember(zoneID, in: db); continue }
            guard zoneID.zoneName.hasPrefix("family_"),
                  let record = local.record(CKRecord.ID(recordName: "family", zoneID: zoneID)) else { continue }
            remember(zoneID, in: db)
            result.append(Self.family(from: record, zoneName: zoneID.zoneName))
        }
        return result.sorted { $0.id < $1.id }
    }

    func createFamily(userId: String, name: String) async throws -> Family {
        let zoneName = newId("family")
        let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
        _ = try await privateDB.save(CKRecordZone(zoneID: zoneID))
        remember(zoneID, in: privateDB)

        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let record = CKRecord(recordType: "Family", recordID: CKRecord.ID(recordName: "family", zoneID: zoneID))
        record["name"] = (trimmed.isEmpty ? "Vores familie" : trimmed) as CKRecordValue
        record["ownerId"] = userId as CKRecordValue
        record["ownerName"] = (UserDefaults.standard.string(forKey: nameKey) ?? "Forælder") as CKRecordValue
        let saved = try await persist(record, in: privateDB)
        return Self.family(from: saved, zoneName: zoneName)
    }

    /// Sletter familiens zone (og zonerne for børn, der er flyttet til deres egen) i ejerens iCloud.
    /// iCloud fjerner så også delingen for alle, den var delt med.
    func deleteFamily(familyId: String) async throws {
        let (db, zoneID) = try await locate(familyId)
        guard db === privateDB else { throw StoreError.notOwner }
        let childZones = ((try? await all(db: db, zoneID: zoneID, type: "Child", keys: ["ownZone"])) ?? [])
            .compactMap { $0["ownZone"] as? String }.filter { !$0.isEmpty }
        // Familiezonen først: går det galt her, er intet slettet. Barnezonerne bagefter — de er
        // uden familie alligevel, og en fejl dér efterlader ingen halv familie.
        _ = try await privateDB.deleteRecordZone(withID: zoneID)
        forgetZone(familyId)
        for name in childZones {
            let id = CKRecordZone.ID(zoneName: name, ownerName: CKCurrentUserDefaultName)
            _ = try? await privateDB.deleteRecordZone(withID: id)
            forgetZone(name)
        }
    }

    /// Sletter barnet og alt dets indhold. Kun familiens ejer.
    /// I familiezonen har alt barnets indhold childRef med .deleteSelf, så CloudKit sletter det med barnet.
    /// Har barnet sin egen zone, slettes zonen (og dermed en evt. deling af barnet) og skiltet i familiezonen.
    func deleteChild(_ child: Child) async throws {
        let (db, familyZone) = try await locate(child.familyId)
        guard db === privateDB else { throw StoreError.notOwner }
        let id = CKRecord.ID(recordName: child.id, zoneID: familyZone)
        // Barnets egen zone står på skiltet i familiezonen — også hvis den blev lavet fra en anden telefon.
        let marker = try? await db.record(for: id)
        if let zoneName = marker?["ownZone"] as? String, !zoneName.isEmpty {
            let ownZone = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
            do { _ = try await privateDB.deleteRecordZone(withID: ownZone) }
            catch let error as CKError where error.code == .zoneNotFound {}
            forgetZone(zoneName)
        }
        do { try await remove(id, in: db) }
        catch let error as CKError where error.code == .unknownItem {}
        var map = UserDefaults.standard.dictionary(forKey: Self.childZoneKey) as? [String: String] ?? [:]
        map[child.id] = nil
        UserDefaults.standard.set(map, forKey: Self.childZoneKey)
    }

    private func forgetZone(_ zoneName: String) {
        zoneCache[zoneName] = nil
        local.purge(named: zoneName)
        var index = UserDefaults.standard.dictionary(forKey: Self.zoneIndexKey) as? [String: String] ?? [:]
        index[zoneName] = nil
        UserDefaults.standard.set(index, forKey: Self.zoneIndexKey)
        var map = UserDefaults.standard.dictionary(forKey: Self.childZoneKey) as? [String: String] ?? [:]
        map = map.filter { $0.value != zoneName }
        UserDefaults.standard.set(map, forKey: Self.childZoneKey)
    }

    func members(familyId: String) async throws -> [AppUser] {
        let (db, zoneID) = try await locate(familyId)
        var members: [AppUser] = []
        if let share = try? await fetchShare(db: db, zoneID: zoneID) {
            // Ejeren er selv en "deltager" i en CKShare. Navne: først det medlemmet selv har
            // gemt under "Dit navn" (Member-records), så iCloud-navn, så mail/telefon.
            let me = share.currentUserParticipant
            let myId = UserDefaults.standard.string(forKey: "mindebog.userId")
            let myName = UserDefaults.standard.string(forKey: nameKey)
            var savedNames: [String: String] = [:]
            for r in (try? await all(db: db, zoneID: zoneID, type: "Member")) ?? [] {
                if let uid = r["userId"] as? String, let n = r["name"] as? String, !n.isEmpty { savedNames[uid] = n }
            }
            // Til notifikations-udvidelsen: "Sheila har tilføjet …".
            SharedNames.members = SharedNames.members.merging(savedNames) { _, new in new }
            for p in share.participants.sorted(by: { $0.role == .owner && $1.role != .owner }) {
                let identity = p.userIdentity
                // For en selv er recordName ofte "__defaultOwner__" — brug det rigtige bruger-id.
                let uid = (p == me ? myId : nil) ?? identity.userRecordID?.recordName
                var name = uid.flatMap { savedNames[$0] } ?? ""
                if name.isEmpty {
                    name = identity.nameComponents
                        .map { PersonNameComponentsFormatter.localizedString(from: $0, style: .default) } ?? ""
                }
                if p == me, name.isEmpty, let myName, myName != "Forælder" { name = myName }
                if name.isEmpty {
                    name = identity.lookupInfo?.emailAddress ?? identity.lookupInfo?.phoneNumber ?? ""
                }
                if name.isEmpty { name = p.role == .owner ? "Ejer" : "Deltager" }

                // Kun det, der er nyttigt at se: "dig", "kun visning" og "inviteret" — ikke "ejer".
                var tags: [String] = []
                if p == me { tags.append("dig") }
                if p.role != .owner && p.permission == .readOnly { tags.append("kun visning") }
                if p.acceptanceStatus == .pending { tags.append("inviteret") }
                let label = tags.isEmpty ? name : "\(name) (\(tags.joined(separator: ", ")))"

                let id = identity.userRecordID?.recordName ?? UUID().uuidString
                members.append(AppUser(id: id, name: label))
            }
        }
        if members.isEmpty {
            let family = try await familyRecord(db: db, zoneID: zoneID)
            members.append(AppUser(id: family["ownerId"] as? String ?? "owner",
                                   name: family["ownerName"] as? String ?? "Forælder"))
        }
        return members
    }

    func canEdit(familyId: String) async -> Bool {
        // Ejeren (familien ligger i egen private database) kan altid redigere.
        guard let (db, zoneID) = try? await locate(familyId), db === sharedDB else { return true }
        guard let share = try? await fetchShare(db: db, zoneID: zoneID),
              let me = share.currentUserParticipant else { return true }
        return me.permission != .readOnly
    }

    func setMemberName(familyId: String, userId: String, name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != "Forælder" else { return }
        let (db, zoneID) = try await locate(familyId)
        let recordID = CKRecord.ID(recordName: "member_\(userId)", zoneID: zoneID)
        let record = (try? await db.record(for: recordID)) ?? CKRecord(recordType: "Member", recordID: recordID)
        guard (record["name"] as? String) != trimmed else { return }   // uændret → intet at gemme
        record["familyRef"] = familyRef(zoneID)
        record["userId"] = userId as CKRecordValue
        record["name"] = trimmed as CKRecordValue
        _ = try await persist(record, in: db)
    }

    /// Returnerer share-URL (som tekst). Partneren åbner linket, eller indsætter det.
    func createInvite(userId: String, familyId: String) async throws -> String {
        let (db, zoneID) = try await locate(familyId)
        if let existing = try? await fetchShare(db: db, zoneID: zoneID), let url = existing.url {
            return url.absoluteString
        }
        let share = CKShare(recordZoneID: zoneID)
        share[CKShare.SystemFieldKey.title] = "Vores familie" as CKRecordValue
        share.publicPermission = .none
        let (saveResults, _) = try await db.modifyRecords(saving: [share], deleting: [])
        guard let saved = try saveResults[share.recordID]?.get() as? CKShare, let url = saved.url else {
            throw StoreError.notFound
        }
        return url.absoluteString
    }

    /// Familiens zone-deling til Apples delingsark (UICloudSharingController), hvor ejeren
    /// inviterer personer og vælger "kun inviterede" eller "alle med linket".
    /// Delingens tilstand til Mere-skærmen: ét opslag, ingen skrivning (#58). nil = ikke delt endnu.
    func shareInfo(familyId: String) async -> (isPublic: Bool, url: String?)? {
        guard let (db, zoneID) = try? await locate(familyId),
              let share = try? await fetchShare(db: db, zoneID: zoneID) else { return nil }
        return (share.publicPermission != .none, share.url?.absoluteString)
    }

    func shareForSharing(familyId: String) async throws -> (CKShare, CKContainer) {
        let (db, zoneID) = try await locate(familyId)
        // Navnet folk ser i invitationen: familiens navn (ældre delinger hed "Mindebog").
        let title = shareTitle((try? await familyRecord(db: db, zoneID: zoneID))?["name"] as? String)
        if let existing = try? await fetchShare(db: db, zoneID: zoneID) {
            if db === privateDB, existing[CKShare.SystemFieldKey.title] as? String != title {
                existing[CKShare.SystemFieldKey.title] = title as CKRecordValue
                if let (saved, _) = try? await db.modifyRecords(saving: [existing], deleting: []),
                   let updated = try? saved[existing.recordID]?.get() as? CKShare {
                    return (updated, container)
                }
            }
            return (existing, container)
        }
        let share = CKShare(recordZoneID: zoneID)
        share[CKShare.SystemFieldKey.title] = title as CKRecordValue
        share.publicPermission = .none
        let (saveResults, _) = try await db.modifyRecords(saving: [share], deleting: [])
        guard let saved = try saveResults[share.recordID]?.get() as? CKShare else { throw StoreError.notFound }
        return (saved, container)
    }

    /// Findes familien stadig for denne bruger? true = ja, false = væk (zonen/posten findes ikke, eller
    /// adgangen er fjernet), nil = kunne ikke afgøres lige nu (netværk, iCloud) — så beholdes den (#60).
    func familyStatus(familyId: String) async -> Bool? {
        guard let (db, zoneID) = try? await locate(familyId) else { return nil }
        do {
            _ = try await familyRecord(db: db, zoneID: zoneID)
            return true
        } catch let error as CKError where [.zoneNotFound, .unknownItem, .permissionFailure, .participantMayNeedVerification].contains(error.code) {
            return false
        } catch {
            return nil
        }
    }

    /// Husk en delt zone, iOS lige har accepteret, så familien kan slås op, før den delte database lister den.
    func rememberSharedZone(zoneName: String, ownerName: String) {
        remember(CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName), in: sharedDB)
    }

    /// Tager en share-URL og tilslutter brugeren til familien.
    func acceptInvite(userId: String, code: String) async throws -> Family {
        guard let url = URL(string: code.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw StoreError.invalidInvite
        }
        let metadata = try await container.shareMetadata(for: url)
        // Er delingen allerede accepteret (fx bedsteforældre, der indsætter linket igen), kan accept fejle —
        // familien hentes alligevel; har man ikke adgang, fejler opslaget nedenfor.
        _ = try? await container.accept(metadata)
        let zoneID = metadata.share.recordID.zoneID
        remember(zoneID, in: sharedDB)
        let record = try await familyRecord(db: sharedDB, zoneID: zoneID)
        return Self.family(from: record, zoneName: zoneID.zoneName)
    }

    // MARK: - Børn

    func children(familyId: String) async throws -> [Child] {
        let (db, zoneID) = try await locate(familyId)
        let records = try await all(db: db, zoneID: zoneID, type: "Child",
                                    keys: ["familyRef", "name", "gender", "birthDate", "dueDate", "ownZone", "shareURL", "linkedUserId"],
                                    assetKeys: ["photo"])
        var kids: [Child] = []
        for r in records {
            var kid = Self.child(from: r, familyId: familyId)
            if let zoneName = r["ownZone"] as? String, !zoneName.isEmpty {
                // Barnet bor i sin egen zone (delt med den anden forælder). Sørg for at have adgang,
                // og tag navn/billede derfra, så ændringer fra den anden forælder ses.
                kid.ownZone = zoneName
                await ensureChildZoneAccess(zoneName: zoneName, shareURL: r["shareURL"] as? String)
                rememberChild(kid.id, zoneName: zoneName)
                if let fresh = try? await childRecord(kid.id) {
                    var updated = Self.child(from: fresh, familyId: familyId)
                    updated.ownZone = zoneName
                    kid = updated
                }
            } else {
                rememberChild(kid.id, zoneName: familyId)
            }
            kids.append(kid)
        }
        return kids.sorted { $0.name < $1.name }
    }

    /// Børn, der er delt med én direkte (fx fra den anden forælders familie) — uden at man er med i familien.
    func sharedChildren() async throws -> [Child] {
        _ = try? await sync.syncAll(throttle: 10)
        var out: [Child] = []
        for zoneID in local.snapshotZones()
        where zoneID.zoneName.hasPrefix(Self.childZonePrefix) && zoneID.ownerName != CKCurrentUserDefaultName {
            remember(zoneID, in: sharedDB)
            let childId = String(zoneID.zoneName.dropFirst(Self.childZonePrefix.count))
            rememberChild(childId, zoneName: zoneID.zoneName)
            guard let r = try? await childRecord(childId) else { continue }
            var kid = Self.child(from: r, familyId: Child.sharedFamilyId)
            kid.ownZone = zoneID.zoneName
            out.append(kid)
        }
        return out.sorted { $0.name < $1.name }
    }

    /// Barnets record fra kopien (med billedet fra cachen).
    private func childRecord(_ childId: String) async throws -> CKRecord {
        let (db, zoneID) = try await locateChild(childId)
        try await ensureSynced(zoneID, db: db)
        guard let record = local.record(CKRecord.ID(recordName: childId, zoneID: zoneID)) else { throw StoreError.notFound }
        return await fillAssets([record.copy() as! CKRecord], keys: ["photo"], db: db)[0]
    }

    // MARK: - Barnezoner (del ét barn med den anden forælder)
    // Et barn kan flyttes til sin egen zone ("child_<id>") i ejerens private database og deles
    // for sig: den anden forælder ser kun det barn, mens familien ser alt som før. Familiens
    // Child-record bliver liggende som "skilt" med ownZone + shareURL, så partnerens telefon
    // selv kan acceptere delingen af barnezonen i baggrunden.

    static let childZonePrefix = "child_"

    /// Partner i familien: accepter barnezonens deling, hvis vi ikke allerede ser zonen.
    private func ensureChildZoneAccess(zoneName: String, shareURL: String?) async {
        if (try? await locate(zoneName)) != nil { return }
        guard let shareURL, let url = URL(string: shareURL) else { return }
        guard let metadata = try? await container.shareMetadata(for: url) else { return }
        if metadata.participantStatus != .accepted {
            // Husk kun zonen, når accepten lykkedes — ellers ville locate() pege på en zone, vi ikke kan læse.
            guard (try? await container.accept(metadata)) != nil else { return }
        }
        remember(metadata.share.recordID.zoneID, in: sharedDB)
    }

    /// Typer, der hører til ét barn (alle har childRef).
    private static let childRecordTypes = ["Highlight", "Diary", "GalleryItem", "Milestone", "Answer", "Letter", "Measurement", "Interview"]

    /// Er barnet allerede i sin egen zone?
    func childHasOwnZone(childId: String) async -> Bool {
        let map = UserDefaults.standard.dictionary(forKey: Self.childZoneKey) as? [String: String] ?? [:]
        return map[childId]?.hasPrefix(Self.childZonePrefix) == true
    }

    /// Flytter barnet til sin egen zone: kopiér alt, bekræft antal, skift markøren, slet originalerne.
    /// Kan køres igen, hvis den stoppes midtvejs (kopierne overskrives bare).
    func moveChildToOwnZone(childId: String, familyId: String) async throws {
        let (db, familyZone) = try await locate(familyId)
        guard db === privateDB else { throw StoreError.notOwner }
        let zoneName = Self.childZonePrefix + childId
        let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
        _ = try await privateDB.save(CKRecordZone(zoneID: zoneID))
        remember(zoneID, in: privateDB)

        // 1) Barnet selv (navn, køn, datoer, billede) — uden familyRef, zonen har ingen Family.
        let source = try await db.record(for: CKRecord.ID(recordName: childId, zoneID: familyZone))
        if (source["ownZone"] as? String)?.isEmpty == false {
            try await cleanupMovedChild(childId: childId, familyZone: familyZone)   // tidligere kørsel: kun oprydning
            return
        }
        let childCopy = CKRecord(recordType: "Child", recordID: CKRecord.ID(recordName: childId, zoneID: zoneID))
        for key in ["name", "gender", "birthDate", "dueDate", "photo", "linkedUserId"] { childCopy[key] = source[key] }
        _ = try await privateDB.modifyRecords(saving: [childCopy], deleting: [], savePolicy: .allKeys)

        // 2) Alle barnets records, i bidder af 20 (billeder/video følger med som CKAsset).
        let ref = childRef(childId, familyZone)
        var copiedIds: [String: [CKRecord.ID]] = [:]
        for type in Self.childRecordTypes {
            // Direkte fra iCloud med billeder/video — kopien har ingen filer.
            let records = try await queryAll(db: db, zoneID: familyZone, type: type,
                                             predicate: NSPredicate(format: "childRef == %@", ref))
            copiedIds[type] = records.map { CKRecord.ID(recordName: $0.recordID.recordName, zoneID: zoneID) }
            var batch: [CKRecord] = []
            for r in records {
                let copy = CKRecord(recordType: type, recordID: CKRecord.ID(recordName: r.recordID.recordName, zoneID: zoneID))
                for key in r.allKeys() where key != "childRef" {
                    if let asset = r[key] as? CKAsset, let url = asset.fileURL { copy[key] = CKAsset(fileURL: url) }
                    else if let list = r[key] as? [CKAsset] { copy[key] = list.compactMap { $0.fileURL.map { CKAsset(fileURL: $0) } } as CKRecordValue }
                    else if r[key] is CKRecord.Reference { continue }   // kun childRef bruges; sættes nedenfor
                    else { copy[key] = r[key] }
                }
                copy["childRef"] = childRef(childId, zoneID)
                batch.append(copy)
                if batch.count == 20 { try await saveBatch(batch, in: privateDB); batch = [] }
            }
            if !batch.isEmpty { try await saveBatch(batch, in: privateDB) }
        }

        // 3) Bekræft: hver kopieret record kan hentes på sit id i den nye zone. (Ikke med en søgning —
        //    iClouds søgeindeks halter nogle sekunder efter, og så ville antallet se for lille ud.)
        for type in Self.childRecordTypes {
            let ids = copiedIds[type] ?? []
            var i = 0
            while i < ids.count {
                let chunk = Array(ids[i..<min(i + 50, ids.count)])
                i += 50
                let fetched = try await privateDB.records(for: chunk, desiredKeys: ["childRef"])
                for id in chunk {
                    guard (try? fetched[id]?.get()) != nil else { throw StoreError.moveIncomplete(type) }
                }
            }
        }

        // 4) Markér barnet som flyttet — herfra læser alle fra den nye zone.
        source["ownZone"] = zoneName as CKRecordValue
        _ = try await persist(source, in: db)
        rememberChild(childId, zoneName: zoneName)

        // 5) Slet originalerne i familiezonen.
        try await cleanupMovedChild(childId: childId, familyZone: familyZone)
    }

    private func saveBatch(_ records: [CKRecord], in db: CKDatabase) async throws {
        let (results, _) = try await db.modifyRecords(saving: records, deleting: [], savePolicy: .allKeys)
        for (_, result) in results { _ = try result.get() }
    }

    /// Fjerner barnets gamle records fra familiezonen (barnet selv bliver som markør).
    private func cleanupMovedChild(childId: String, familyZone: CKRecordZone.ID) async throws {
        let ref = childRef(childId, familyZone)
        for type in Self.childRecordTypes {
            let ids = try await queryAll(db: privateDB, zoneID: familyZone, type: type, keys: ["childRef"],
                                         predicate: NSPredicate(format: "childRef == %@", ref)).map(\.recordID)
            var i = 0
            while i < ids.count {
                let chunk = Array(ids[i..<min(i + 50, ids.count)])
                i += 50
                _ = try await privateDB.modifyRecords(saving: [], deleting: chunk)
                local.apply(changed: [], deleted: chunk, in: familyZone, createIfMissing: false)
            }
        }
        // Barnet bor nu i sin egen zone: hent begge zoner forfra, så kopien passer.
        local.purge(familyZone)
        local.purge(CKRecordZone.ID(zoneName: Self.childZonePrefix + childId, ownerName: CKCurrentUserDefaultName))
    }

    /// Barnezonens deling: oprettes første gang, og familiens medlemmer lægges på med samme adgang,
    /// så partneren stadig ser barnet. Linket gemmes på familiens Child-record til de andre telefoner.
    func shareChild(childId: String, familyId: String) async throws -> (CKShare, CKContainer) {
        if !(await childHasOwnZone(childId: childId)) {
            try await moveChildToOwnZone(childId: childId, familyId: familyId)
        }
        let (db, zoneID) = try await locateChild(childId)
        guard db === privateDB else { throw StoreError.notOwner }
        let name = (try? await db.record(for: CKRecord.ID(recordName: childId, zoneID: zoneID)))?["name"] as? String ?? "Barn"
        let share: CKShare
        if let existing = try? await fetchShare(db: db, zoneID: zoneID) {
            share = existing
        } else {
            let fresh = CKShare(recordZoneID: zoneID)
            fresh[CKShare.SystemFieldKey.title] = "\(name) · Vores familie" as CKRecordValue
            fresh.publicPermission = .none
            let (saved, _) = try await db.modifyRecords(saving: [fresh], deleting: [])
            guard let s = try saved[fresh.recordID]?.get() as? CKShare else { throw StoreError.notFound }
            share = s
        }
        try await syncFamilyMembers(onto: share, familyId: familyId, db: db)
        if let url = share.url {
            let (fdb, fzone) = try await locate(familyId)
            let marker = try await fdb.record(for: CKRecord.ID(recordName: childId, zoneID: fzone))
            if marker["shareURL"] as? String != url.absoluteString {
                marker["shareURL"] = url.absoluteString as CKRecordValue
                _ = try await persist(marker, in: fdb)
            }
        }
        return (share, container)
    }

    /// Familiens deltagere (partner, bedsteforældre) lægges på barnets deling med samme adgang.
    private func syncFamilyMembers(onto share: CKShare, familyId: String, db: CKDatabase) async throws {
        let (fdb, fzone) = try await locate(familyId)
        guard let familyShare = try? await fetchShare(db: fdb, zoneID: fzone) else { return }
        let existing = Set(share.participants.compactMap { $0.userIdentity.userRecordID?.recordName })
        var changed = false
        for p in familyShare.participants where p.role != .owner {
            guard let id = p.userIdentity.userRecordID, !existing.contains(id.recordName),
                  let fresh = try? await container.shareParticipant(forUserRecordID: id) else { continue }
            fresh.permission = p.permission
            share.addParticipant(fresh)
            changed = true
        }
        if changed {
            let (saved, _) = try await db.modifyRecords(saving: [share], deleting: [], savePolicy: .changedKeys)
            _ = try saved[share.recordID]?.get()
        }
    }

    /// Deltagere på barnets deling — til "Del barn"-skærmen.
    func childParticipants(childId: String) async throws -> [FamilyParticipant] {
        let (db, zoneID) = try await locateChild(childId)
        guard let share = try? await fetchShare(db: db, zoneID: zoneID) else { return [] }
        return participants(of: share, db: db, zoneID: zoneID, namesFrom: nil)
    }

    func isChildZoneOwner(childId: String) async -> Bool {
        guard let (db, _) = try? await locateChild(childId) else { return false }
        return db === privateDB
    }

    func setChildParticipant(childId: String, id: String, readOnly: Bool) async throws {
        let (db, zoneID) = try await locateChild(childId)
        let share = try await fetchShare(db: db, zoneID: zoneID)
        guard let p = share.participants.first(where: { Self.participantKey($0, in: share) == id }), p.role != .owner else { return }
        p.permission = readOnly ? .readOnly : .readWrite
        let (saved, _) = try await db.modifyRecords(saving: [share], deleting: [], savePolicy: .changedKeys)
        _ = try saved[share.recordID]?.get()
    }

    func removeChildParticipant(childId: String, id: String) async throws {
        let (db, zoneID) = try await locateChild(childId)
        let share = try await fetchShare(db: db, zoneID: zoneID)
        guard let p = share.participants.first(where: { Self.participantKey($0, in: share) == id }), p.role != .owner else { return }
        share.removeParticipant(p)
        let (saved, _) = try await db.modifyRecords(saving: [share], deleting: [], savePolicy: .changedKeys)
        _ = try saved[share.recordID]?.get()
    }

    /// Må man redigere dette barn? Familiens børn følger familien; et delt barn følger barnets deling.
    func canEditChild(childId: String) async -> Bool {
        guard let (db, zoneID) = try? await locateChild(childId), db === sharedDB,
              let share = try? await fetchShare(db: db, zoneID: zoneID),
              let me = share.currentUserParticipant else { return true }
        return me.permission != .readOnly
    }

    func createChild(familyId: String, name: String, gender: Gender,
                     birthDate: Date?, dueDate: Date?) async throws -> Child {
        let (db, zoneID) = try await locate(familyId)
        let record = CKRecord(recordType: "Child", recordID: CKRecord.ID(recordName: newId("child"), zoneID: zoneID))
        record["familyRef"] = familyRef(zoneID)
        record["name"] = name.trimmingCharacters(in: .whitespaces) as CKRecordValue
        record["gender"] = gender.rawValue as CKRecordValue
        if let birthDate { record["birthDate"] = birthDate as CKRecordValue }
        if let dueDate { record["dueDate"] = dueDate as CKRecordValue }
        let saved = try await persist(record, in: db)
        let child = Self.child(from: saved, familyId: familyId)
        rememberChild(child.id, zoneName: familyId)
        if let birthDate { try await setMilestone(childId: child.id, key: "birth_date", value: Fmt.iso(birthDate), photos: PhotoSet()) }
        if let dueDate { try await setMilestone(childId: child.id, key: "due_date", value: Fmt.iso(dueDate), photos: PhotoSet()) }
        return child
    }

    func updateChild(_ child: Child) async throws -> Child {
        let (db, zoneID) = try await locateChild(child.id)
        let record = try await db.record(for: CKRecord.ID(recordName: child.id, zoneID: zoneID))
        record["name"] = child.name.trimmingCharacters(in: .whitespaces) as CKRecordValue
        record["gender"] = child.gender.rawValue as CKRecordValue
        record["birthDate"] = child.birthDate as CKRecordValue?
        record["dueDate"] = child.dueDate as CKRecordValue?
        if child.photoLoaded { record["photo"] = child.photo.flatMap { Self.asset(from: $0) } }   // ellers urørt (#62)
        // Feltet er nyt (#48): rør det kun, når det bruges, så redigering virker, selv før skemaet er deployet.
        if child.linkedUserId != nil || record["linkedUserId"] != nil { record["linkedUserId"] = child.linkedUserId as CKRecordValue? }
        let saved = try await persist(record, in: db)
        // Barn i egen zone: familiens "skilt" får også de nye oplysninger (navnet vises derfra, hvis zonen er utilgængelig).
        if child.ownZone != nil, child.familyId != Child.sharedFamilyId,
           let (fdb, fzone) = try? await locate(child.familyId),
           let marker = try? await fdb.record(for: CKRecord.ID(recordName: child.id, zoneID: fzone)) {
            for key in ["name", "gender", "birthDate", "dueDate", "linkedUserId"] { marker[key] = record[key] }
            if child.photoLoaded { marker["photo"] = child.photo.flatMap { Self.asset(from: $0) } }
            _ = try? await persist(marker, in: fdb)
        }
        // Fødsels-/terminsdato ligger også i milepælene (som på websitet).
        if let birth = child.birthDate {
            try await setMilestoneValue(childId: child.id, key: "birth_date", value: Fmt.iso(birth), db: db, zoneID: zoneID)
        }
        if let due = child.dueDate {
            try await setMilestoneValue(childId: child.id, key: "due_date", value: Fmt.iso(due), db: db, zoneID: zoneID)
        }
        var updated = Self.child(from: saved, familyId: child.familyId)
        updated.ownZone = child.ownZone
        return updated
    }

    /// Opdaterer kun milepælens værdi — et evt. billede på milepælen bevares.
    private func setMilestoneValue(childId: String, key: String, value: String,
                                   db: CKDatabase, zoneID: CKRecordZone.ID) async throws {
        let recordID = CKRecord.ID(recordName: "ms_\(childId)_\(key)", zoneID: zoneID)
        let record = (try? await db.record(for: recordID)) ?? CKRecord(recordType: "Milestone", recordID: recordID)
        record["childRef"] = childRef(childId, zoneID)
        record["key"] = key as CKRecordValue
        record["value"] = value as CKRecordValue
        _ = try await persist(record, in: db)
    }

    // MARK: - Højdepunkter

    func highlights(childId: String) async throws -> [Highlight] {
        // Bevidst uden "video"/"audio" — de hentes først ved afspilning (highlightMedia).
        let records = try await childRecords(childId, type: "Highlight",
                                              keys: ["childRef", "date", "text", "videoDuration", "audioDuration", "coverIndex",
                                                     "placeName", "placeAddress", "location"],
                                              assetKeys: ["photos"])
        return records.map { r in
            Highlight(id: r.recordID.recordName,
                      date: r["date"] as? Date,
                      text: r["text"] as? String ?? "",
                      photos: Self.assetsData(r["photos"]),
                      createdAt: r.creationDate ?? Date(),
                      videoDuration: r["videoDuration"] as? Double,
                      audioDuration: r["audioDuration"] as? Double,
                      cover: (r["coverIndex"] as? Int64).map(Int.init) ?? 0,
                      place: Self.place(from: r),
                      thumb: Self.assetData(r[Self.thumbKey]),
                      photosLoaded: Self.assetsLoaded(r, keys: ["photos"]))
        }.sorted { ($0.date ?? $0.createdAt) > ($1.date ?? $1.createdAt) }
    }

    func setHighlightMedia(childId: String, id: String, video: MediaChange, audio: MediaChange) async throws {
        if case .keep = video, case .keep = audio { return }
        let (db, zoneID) = try await locateChild(childId)
        let recordID = CKRecord.ID(recordName: id, zoneID: zoneID)
        // Hent kun varighederne — gem sender kun de ændrede felter.
        let results = try await db.records(for: [recordID], desiredKeys: ["videoDuration", "audioDuration"])
        guard let record = try results[recordID]?.get() else { throw StoreError.notFound }
        func apply(_ change: MediaChange, asset key: String, duration durationKey: String) {
            switch change {
            case .keep: break
            case .remove:
                record[key] = nil
                record[durationKey] = nil
            case .set(let url, let seconds):
                record[key] = Self.uploadAsset(copying: url)
                record[durationKey] = seconds as CKRecordValue
            }
        }
        apply(video, asset: "video", duration: "videoDuration")
        apply(audio, asset: "audio", duration: "audioDuration")
        _ = try await persist(record, in: db)
    }

    func highlightMedia(childId: String, id: String) async throws -> (video: URL?, audio: URL?) {
        let (db, zoneID) = try await locateChild(childId)
        let recordID = CKRecord.ID(recordName: id, zoneID: zoneID)
        let results = try await db.records(for: [recordID], desiredKeys: ["video", "audio"])
        guard let record = try results[recordID]?.get() else { return (nil, nil) }
        // Kopiér ud af CloudKits cache, så afspilleren har en stabil fil.
        func local(_ key: String, ext: String) -> URL? {
            guard let source = (record[key] as? CKAsset)?.fileURL else { return nil }
            let target = MediaFiles.dir.appendingPathComponent("\(id)-\(key).\(ext)")
            try? FileManager.default.removeItem(at: target)
            return (try? FileManager.default.copyItem(at: source, to: target)) != nil ? target : nil
        }
        return (local("video", ext: "mp4"), local("audio", ext: "m4a"))
    }

    func addHighlight(childId: String, date: Date?, text: String, photos: [Data], cover: Int, place: Place?) async throws -> Highlight {
        let (db, zoneID) = try await locateChild(childId)
        let record = CKRecord(recordType: "Highlight", recordID: CKRecord.ID(recordName: newId("hl"), zoneID: zoneID))
        record["childRef"] = childRef(childId, zoneID)
        if let date { record["date"] = date as CKRecordValue }
        record["text"] = text.trimmingCharacters(in: .whitespaces) as CKRecordValue
        let assets = photos.compactMap { Self.asset(from: $0) }
        if !assets.isEmpty { record["photos"] = assets as CKRecordValue }
        if cover > 0 { record["coverIndex"] = Int64(cover) as CKRecordValue }
        Self.setPlace(place, on: record)
        let saved = try await persist(record, in: db)
        return Highlight(id: saved.recordID.recordName, date: date, text: text, photos: photos, createdAt: Date(),
                         cover: cover, place: place)
    }

    func updateHighlight(childId: String, _ highlight: Highlight) async throws {
        let (db, zoneID) = try await locateChild(childId)
        let record = try await db.record(for: CKRecord.ID(recordName: highlight.id, zoneID: zoneID))
        record["date"] = highlight.date as CKRecordValue?
        record["text"] = highlight.text.trimmingCharacters(in: .whitespaces) as CKRecordValue
        let assets = highlight.photos.compactMap { Self.asset(from: $0) }
        record["photos"] = assets.isEmpty ? nil : assets as CKRecordValue
        record["coverIndex"] = Int64(highlight.coverIndex) as CKRecordValue
        Self.setPlace(highlight.place, on: record)
        _ = try await persist(record, in: db)
    }

    func deleteHighlight(childId: String, id: String) async throws {
        let (db, zoneID) = try await locateChild(childId)
        try await remove(CKRecord.ID(recordName: id, zoneID: zoneID), in: db)
    }

    // MARK: - Milepæle

    func milestones(childId: String) async throws -> [String: MilestoneEntry] {
        let records = try await childRecords(childId, type: "Milestone",
                                              keys: ["childRef", "key", "value", "captions", "coverIndex"], assetKeys: ["photo", "photos"])
        var result: [String: MilestoneEntry] = [:]
        for r in records {
            guard let key = r["key"] as? String else { continue }
            result[key] = MilestoneEntry(value: r["value"] as? String, photos: Self.photoSet(from: r))
        }
        return result
    }

    func setMilestone(childId: String, key: String, value: String?, photos: PhotoSet) async throws {
        let (db, zoneID) = try await locateChild(childId)
        let recordID = CKRecord.ID(recordName: "ms_\(childId)_\(key)", zoneID: zoneID)
        let cleanValue = value?.trimmingCharacters(in: .whitespaces)
        if (cleanValue?.isEmpty ?? true) && photos.isEmpty {
            try? await remove(recordID, in: db)
            return
        }
        let record = (try? await db.record(for: recordID)) ?? CKRecord(recordType: "Milestone", recordID: recordID)
        record["childRef"] = childRef(childId, zoneID)
        record["key"] = key as CKRecordValue
        if let v = cleanValue, !v.isEmpty {
            record["value"] = v as CKRecordValue
        } else {
            record["value"] = nil
        }
        Self.setPhotos(photos, on: record)
        _ = try await persist(record, in: db)
    }

    // MARK: Billedsæt (flere billeder + forside + billedtekster)
    // "photos" LIST<ASSET>, "captions" LIST<STRING>, "coverIndex" INT64.
    // Forsiden skrives også i det gamle "photo"-felt, så ældre builds stadig viser et billede.
    private static func photoSet(from record: CKRecord) -> PhotoSet {
        let thumb = assetData(record[thumbKey])
        let loaded = assetsLoaded(record, keys: ["photos", "photo"])
        let list = assetsData(record["photos"])
        if list.isEmpty { return PhotoSet(single: assetData(record["photo"]), thumb: thumb, loaded: loaded) }
        let captions = record["captions"] as? [String] ?? []
        let cover = (record["coverIndex"] as? Int64).map(Int.init) ?? 0
        return PhotoSet(photos: list, captions: captions, cover: cover, thumb: thumb, loaded: loaded)
    }

    private static func setPhotos(_ set: PhotoSet, on record: CKRecord) {
        // Originalerne blev aldrig hentet (listen havde kun thumbs): rør ikke billederne i iCloud (#62).
        guard set.loaded else { return }
        guard !set.isEmpty else {
            record["photos"] = nil
            record["captions"] = nil
            record["coverIndex"] = nil
            record["photo"] = nil
            return
        }
        let assets = set.photos.compactMap { asset(from: $0) }
        record["photos"] = assets as CKRecordValue
        record["captions"] = set.photos.indices.map { set.caption(at: $0) } as CKRecordValue
        record["coverIndex"] = Int64(set.coverIndex) as CKRecordValue
        record["photo"] = set.coverPhoto.flatMap { asset(from: $0) }
    }

    // MARK: - Om dig

    /// Record-navnet for et svar: "ans_<barn>_<stabilt hash af spørgsmålet>".
    /// Hashet er SHA-256 (ikke `hashValue`, som Swift sår tilfældigt ved hver app-start — det gav
    /// et nyt id pr. start, altså dubletter i iCloud og sletninger, der ramte ved siden af).
    static func answerRecordName(childId: String, question: String) -> String {
        let digest = SHA256.hash(data: Data(question.utf8))
        let hash = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        return "ans_\(childId)_\(hash)"
    }

    func answers(childId: String) async throws -> [String: String] {
        let records = try await childRecords(childId, type: "Answer")
        // Ældre builds kunne gemme samme spørgsmål flere gange (se answerRecordName) — det nyeste svar vinder.
        var newest: [String: Date] = [:]
        var result: [String: String] = [:]
        for r in records {
            guard let q = r["question"] as? String, let a = r["answer"] as? String else { continue }
            let modified = r.modificationDate ?? .distantPast
            if modified >= (newest[q] ?? .distantPast) {
                newest[q] = modified
                result[q] = a
            }
        }
        return result
    }

    func setAnswer(childId: String, question: String, answer: String) async throws {
        let (db, zoneID) = try await locateChild(childId)
        let recordID = CKRecord.ID(recordName: Self.answerRecordName(childId: childId, question: question), zoneID: zoneID)
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        // Alle records for spørgsmålet, også dubletter fra ældre builds ("question" er ikke søgbar i skemaet,
        // så barnets svar hentes og filtreres her — det er få, små poster).
        let existing = ((try? await childRecords(childId, type: "Answer", keys: ["childRef", "question"])) ?? [])
            .filter { ($0["question"] as? String) == question }
        if trimmed.isEmpty {
            try? await remove(recordID, in: db)
            for r in existing where r.recordID != recordID { try? await remove(r.recordID, in: db) }
            return
        }
        let record = (try? await db.record(for: recordID)) ?? CKRecord(recordType: "Answer", recordID: recordID)
        record["childRef"] = childRef(childId, zoneID)
        record["question"] = question as CKRecordValue
        record["answer"] = trimmed as CKRecordValue
        _ = try await persist(record, in: db)
        // Ryd op i dubletter, når det nye svar er gemt.
        for r in existing where r.recordID != recordID { try? await remove(r.recordID, in: db) }
    }

    // MARK: - Dagbog

    func diary(childId: String) async throws -> [DiaryEntry] {
        let records = try await childRecords(childId, type: "Diary", keys: ["childRef", "date", "text"], assetKeys: ["photo"])
        return records.map { r in
            DiaryEntry(id: r.recordID.recordName,
                       date: r["date"] as? Date,
                       text: r["text"] as? String ?? "",
                       photo: Self.assetData(r["photo"]),
                       createdAt: r.creationDate ?? Date(),
                       thumb: Self.assetData(r[Self.thumbKey]),
                       photoLoaded: Self.assetsLoaded(r, keys: ["photo"]))
        }.sorted { ($0.date ?? $0.createdAt) > ($1.date ?? $1.createdAt) }
    }

    func addDiary(childId: String, date: Date?, text: String, photo: Data?) async throws -> DiaryEntry {
        let (db, zoneID) = try await locateChild(childId)
        let record = CKRecord(recordType: "Diary", recordID: CKRecord.ID(recordName: newId("diary"), zoneID: zoneID))
        record["childRef"] = childRef(childId, zoneID)
        if let date { record["date"] = date as CKRecordValue }
        record["text"] = text.trimmingCharacters(in: .whitespaces) as CKRecordValue
        record["photo"] = photo.flatMap { Self.asset(from: $0) }
        let saved = try await persist(record, in: db)
        return DiaryEntry(id: saved.recordID.recordName, date: date, text: text, photo: photo, createdAt: Date())
    }

    func updateDiary(childId: String, _ entry: DiaryEntry) async throws {
        let (db, zoneID) = try await locateChild(childId)
        let record = try await db.record(for: CKRecord.ID(recordName: entry.id, zoneID: zoneID))
        record["date"] = entry.date as CKRecordValue?
        record["text"] = entry.text.trimmingCharacters(in: .whitespaces) as CKRecordValue
        if entry.photoLoaded { record["photo"] = entry.photo.flatMap { Self.asset(from: $0) } }   // ellers urørt (#62)
        _ = try await persist(record, in: db)
    }

    func deleteDiary(childId: String, id: String) async throws {
        let (db, zoneID) = try await locateChild(childId)
        try await remove(CKRecord.ID(recordName: id, zoneID: zoneID), in: db)
    }

    // MARK: - Gallerier

    func gallery(childId: String, kind: GalleryKind) async throws -> [GalleryItem] {
        // Kun den ønskede serie hentes (kind er indekseret), og billederne kommer fra cachen.
        let records = try await childRecords(childId, type: "GalleryItem",
                                              keys: ["childRef", "kind", "caption", "note", "date"], assetKeys: ["photo"],
                                              extraMatch: { ($0["kind"] as? String) == kind.rawValue })
        return records
            .map { r in
                GalleryItem(id: r.recordID.recordName,
                            caption: r["caption"] as? String ?? "",
                            note: r["note"] as? String ?? "",
                            date: r["date"] as? Date,
                            photo: Self.assetData(r["photo"]),
                            createdAt: r.creationDate ?? Date(),
                            thumb: Self.assetData(r[Self.thumbKey]),
                            photoLoaded: Self.assetsLoaded(r, keys: ["photo"]))
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func addGalleryItem(childId: String, kind: GalleryKind, caption: String, photo: Data?) async throws -> GalleryItem {
        let (db, zoneID) = try await locateChild(childId)
        let record = CKRecord(recordType: "GalleryItem", recordID: CKRecord.ID(recordName: newId("gal"), zoneID: zoneID))
        record["childRef"] = childRef(childId, zoneID)
        record["kind"] = kind.rawValue as CKRecordValue
        record["caption"] = caption.trimmingCharacters(in: .whitespaces) as CKRecordValue
        record["photo"] = photo.flatMap { Self.asset(from: $0) }
        let saved = try await persist(record, in: db)
        return GalleryItem(id: saved.recordID.recordName, caption: caption, photo: photo, createdAt: Date())
    }

    func updateGalleryItem(childId: String, _ item: GalleryItem) async throws {
        let (db, zoneID) = try await locateChild(childId)
        let record = try await db.record(for: CKRecord.ID(recordName: item.id, zoneID: zoneID))
        record["caption"] = item.caption.trimmingCharacters(in: .whitespaces) as CKRecordValue
        record["note"] = item.note.trimmingCharacters(in: .whitespacesAndNewlines) as CKRecordValue
        record["date"] = item.date as CKRecordValue?
        if item.photoLoaded { record["photo"] = item.photo.flatMap { Self.asset(from: $0) } }   // ellers urørt (#62)
        _ = try await persist(record, in: db)
    }

    func deleteGalleryItem(childId: String, id: String) async throws {
        let (db, zoneID) = try await locateChild(childId)
        try await remove(CKRecord.ID(recordName: id, zoneID: zoneID), in: db)
    }

    // MARK: - Vækst

    func measurements(childId: String) async throws -> [Measurement] {
        try await childRecords(childId, type: "Measurement").compactMap { r in
            guard let date = r["date"] as? Date else { return nil }
            return Measurement(id: r.recordID.recordName, date: date,
                               weightGrams: (r["weightGrams"] as? Int64).map(Int.init),
                               heightCm: r["heightCm"] as? Double,
                               headCm: r["headCm"] as? Double)
        }
        .sorted { $0.date < $1.date }
    }

    func saveMeasurement(childId: String, _ m: Measurement) async throws {
        let (db, zoneID) = try await locateChild(childId)
        let id = CKRecord.ID(recordName: m.id, zoneID: zoneID)
        let record = (try? await db.record(for: id)) ?? CKRecord(recordType: "Measurement", recordID: id)
        record["childRef"] = childRef(childId, zoneID)
        record["date"] = m.date as CKRecordValue
        record["weightGrams"] = m.weightGrams.map { Int64($0) as CKRecordValue }
        record["heightCm"] = m.heightCm as CKRecordValue?
        record["headCm"] = m.headCm as CKRecordValue?
        _ = try await persist(record, in: db)
    }

    func deleteMeasurement(childId: String, id: String) async throws {
        let (db, zoneID) = try await locateChild(childId)
        try await remove(CKRecord.ID(recordName: id, zoneID: zoneID), in: db)
    }

    // MARK: - Breve til barnet

    /// Barnet selv (#48) ser kun breve, der er åbnet — forseglede breve filtreres fra her.
    func letters(childId: String) async throws -> [Letter] {
        MeChild.visibleLetters(try await allLetters(childId: childId), childId: childId)
    }

    private func allLetters(childId: String) async throws -> [Letter] {
        // Bevidst uden "video" — den hentes først ved afspilning (letterVideo).
        try await childRecords(childId, type: "Letter",
                               keys: ["childRef", "title", "text", "author", "writtenAt", "openDate", "videoDuration"],
                               assetKeys: ["photo"]).map { r in
            Letter(id: r.recordID.recordName,
                   title: r["title"] as? String ?? "",
                   text: r["text"] as? String ?? "",
                   author: r["author"] as? String ?? "",
                   writtenAt: r["writtenAt"] as? Date ?? r.creationDate ?? Date(),
                   openDate: r["openDate"] as? Date,
                   photo: Self.assetData(r["photo"]),
                   thumb: Self.assetData(r[Self.thumbKey]),
                   photoLoaded: Self.assetsLoaded(r, keys: ["photo"]),
                   videoDuration: r["videoDuration"] as? Double)
        }
        .sorted { $0.writtenAt > $1.writtenAt }
    }

    func addLetter(childId: String, _ letter: Letter) async throws {
        let (db, zoneID) = try await locateChild(childId)
        let record = CKRecord(recordType: "Letter", recordID: CKRecord.ID(recordName: letter.id, zoneID: zoneID))
        record["childRef"] = childRef(childId, zoneID)
        Self.fill(record, with: letter)
        _ = try await persist(record, in: db)
    }

    func updateLetter(childId: String, _ letter: Letter) async throws {
        let (db, zoneID) = try await locateChild(childId)
        let record = try await db.record(for: CKRecord.ID(recordName: letter.id, zoneID: zoneID))
        Self.fill(record, with: letter)
        _ = try await persist(record, in: db)
    }

    func deleteLetter(childId: String, id: String) async throws {
        let (db, zoneID) = try await locateChild(childId)
        try await remove(CKRecord.ID(recordName: id, zoneID: zoneID), in: db)
    }

    private static func fill(_ record: CKRecord, with letter: Letter) {
        record["title"] = letter.title.trimmingCharacters(in: .whitespaces) as CKRecordValue
        record["text"] = letter.text as CKRecordValue
        record["author"] = letter.author as CKRecordValue
        record["writtenAt"] = letter.writtenAt as CKRecordValue
        record["openDate"] = letter.openDate as CKRecordValue?
        if letter.photoLoaded { record["photo"] = letter.photo.flatMap { asset(from: $0) } }   // ellers urørt (#62)
    }

    // MARK: - Familie-indhold

    func events(familyId: String) async throws -> [FamilyEvent] {
        let (db, zoneID) = try await locate(familyId)
        return try await all(db: db, zoneID: zoneID, type: "Event",
                             keys: ["familyRef", "title", "date", "details", "placeName", "placeAddress", "location", "captions", "coverIndex",
                                    "childIds", "personIds"],
                             assetKeys: ["photo", "photos"]).map { r in
            FamilyEvent(id: r.recordID.recordName,
                        title: r["title"] as? String ?? "",
                        date: r["date"] as? Date,
                        details: r["details"] as? String ?? "",
                        photos: Self.photoSet(from: r),
                        place: Self.place(from: r),
                        childIds: r["childIds"] as? [String] ?? [],
                        personIds: r["personIds"] as? [String] ?? [])
        }.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    func addEvent(familyId: String, title: String, date: Date?, details: String,
                  photos: PhotoSet, place: Place?, childIds: [String], personIds: [String]) async throws -> FamilyEvent {
        let (db, zoneID) = try await locate(familyId)
        let record = CKRecord(recordType: "Event", recordID: CKRecord.ID(recordName: newId("ev"), zoneID: zoneID))
        record["familyRef"] = familyRef(zoneID)
        record["title"] = title.trimmingCharacters(in: .whitespaces) as CKRecordValue
        if let date { record["date"] = date as CKRecordValue }
        record["details"] = details.trimmingCharacters(in: .whitespaces) as CKRecordValue
        Self.setPhotos(photos, on: record)
        Self.setPlace(place, on: record)
        Self.setAbout(childIds: childIds, personIds: personIds, on: record)
        let saved = try await persist(record, in: db)
        return FamilyEvent(id: saved.recordID.recordName, title: title, date: date, details: details,
                           photos: photos, place: place, childIds: childIds, personIds: personIds)
    }

    /// "Handler om": børn og voksne. Tomme lister fjerner felterne.
    private static func setAbout(childIds: [String], personIds: [String], on record: CKRecord) {
        record["childIds"] = childIds.isEmpty ? nil : childIds as CKRecordValue
        record["personIds"] = personIds.isEmpty ? nil : personIds as CKRecordValue
    }

    func vacations(familyId: String) async throws -> [Vacation] {
        let (db, zoneID) = try await locate(familyId)
        return try await all(db: db, zoneID: zoneID, type: "Vacation",
                             keys: ["familyRef", "title", "startDate", "endDate", "details", "placeName", "placeAddress", "location", "captions", "coverIndex",
                                    "childIds", "personIds"],
                             assetKeys: ["photo", "photos"]).map { r in
            Vacation(id: r.recordID.recordName,
                     title: r["title"] as? String ?? "",
                     startDate: r["startDate"] as? Date,
                     endDate: r["endDate"] as? Date,
                     details: r["details"] as? String ?? "",
                     photos: Self.photoSet(from: r),
                     place: Self.place(from: r),
                     childIds: r["childIds"] as? [String] ?? [],
                     personIds: r["personIds"] as? [String] ?? [])
        }.sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
    }

    func addVacation(familyId: String, title: String, start: Date?, end: Date?,
                     details: String, photos: PhotoSet, place: Place?, childIds: [String], personIds: [String]) async throws -> Vacation {
        let (db, zoneID) = try await locate(familyId)
        let record = CKRecord(recordType: "Vacation", recordID: CKRecord.ID(recordName: newId("vac"), zoneID: zoneID))
        record["familyRef"] = familyRef(zoneID)
        record["title"] = title.trimmingCharacters(in: .whitespaces) as CKRecordValue
        if let start { record["startDate"] = start as CKRecordValue }
        if let end { record["endDate"] = end as CKRecordValue }
        record["details"] = details.trimmingCharacters(in: .whitespaces) as CKRecordValue
        Self.setPhotos(photos, on: record)
        Self.setPlace(place, on: record)
        Self.setAbout(childIds: childIds, personIds: personIds, on: record)
        let saved = try await persist(record, in: db)
        return Vacation(id: saved.recordID.recordName, title: title, startDate: start, endDate: end,
                        details: details, photos: photos, place: place, childIds: childIds, personIds: personIds)
    }

    func updateEvent(familyId: String, _ event: FamilyEvent) async throws -> FamilyEvent {
        let (db, zoneID) = try await locate(familyId)
        let record = try await db.record(for: CKRecord.ID(recordName: event.id, zoneID: zoneID))
        record["title"] = event.title.trimmingCharacters(in: .whitespaces) as CKRecordValue
        record["date"] = event.date as CKRecordValue?
        record["details"] = event.details.trimmingCharacters(in: .whitespaces) as CKRecordValue
        Self.setPhotos(event.photos, on: record)
        Self.setPlace(event.place, on: record)
        Self.setAbout(childIds: event.childIds, personIds: event.personIds, on: record)
        _ = try await persist(record, in: db)
        return event
    }

    func deleteEvent(familyId: String, id: String) async throws {
        let (db, zoneID) = try await locate(familyId)
        try await remove(CKRecord.ID(recordName: id, zoneID: zoneID), in: db)
    }

    func updateVacation(familyId: String, _ vacation: Vacation) async throws -> Vacation {
        let (db, zoneID) = try await locate(familyId)
        let record = try await db.record(for: CKRecord.ID(recordName: vacation.id, zoneID: zoneID))
        record["title"] = vacation.title.trimmingCharacters(in: .whitespaces) as CKRecordValue
        record["startDate"] = vacation.startDate as CKRecordValue?
        record["endDate"] = vacation.endDate as CKRecordValue?
        record["details"] = vacation.details.trimmingCharacters(in: .whitespaces) as CKRecordValue
        Self.setPhotos(vacation.photos, on: record)
        Self.setPlace(vacation.place, on: record)
        Self.setAbout(childIds: vacation.childIds, personIds: vacation.personIds, on: record)
        _ = try await persist(record, in: db)
        return vacation
    }

    func deleteVacation(familyId: String, id: String) async throws {
        let (db, zoneID) = try await locate(familyId)
        try await remove(CKRecord.ID(recordName: id, zoneID: zoneID), in: db)
    }

    // Sted: navn + adresse som tekst, koordinat som CloudKit LOCATION. nil fjerner stedet.
    private static func setPlace(_ place: Place?, on record: CKRecord) {
        guard let place else {
            record["placeName"] = nil
            record["placeAddress"] = nil
            record["location"] = nil
            return
        }
        record["placeName"] = place.name as CKRecordValue
        record["placeAddress"] = place.address as CKRecordValue
        record["location"] = CLLocation(latitude: place.latitude, longitude: place.longitude)
    }

    private static func place(from record: CKRecord) -> Place? {
        guard let location = record["location"] as? CLLocation else { return nil }
        return Place(name: record["placeName"] as? String ?? "",
                     address: record["placeAddress"] as? String ?? "",
                     latitude: location.coordinate.latitude,
                     longitude: location.coordinate.longitude)
    }

    // MARK: - Hjem: lette oversigter
    // Fire forespørgsler for hele familien (i stedet for to pr. barn), og kun tekst/dato —
    // billederne hentes bagefter med coverPhoto, kun for de minder der faktisk vises.

    func memorySummaries(familyId: String) async throws -> [MemorySummary] {
        let (db, zoneID) = try await locate(familyId)
        var out: [MemorySummary] = []
        func childId(_ r: CKRecord) -> String? { (r["childRef"] as? CKRecord.Reference)?.recordID.recordName }
        /// Ekstra tekstfelter samlet til søgningen (tomme felter springes over).
        func searchText(_ r: CKRecord, _ keys: [String]) -> String? {
            let parts = keys.compactMap { r[$0] as? String }.filter { !$0.isEmpty }
            return parts.isEmpty ? nil : parts.joined(separator: " ")
        }

        // Opslagene kører samtidig. Kun tekst: beskrivelser og stednavne følger med til søgningen.
        async let highlights = all(db: db, zoneID: zoneID, type: "Highlight", keys: ["childRef", "date", "text", "placeName"])
        async let diary = all(db: db, zoneID: zoneID, type: "Diary", keys: ["childRef", "date", "text"])
        async let events = all(db: db, zoneID: zoneID, type: "Event", keys: ["title", "date", "details", "placeName"])
        async let vacations = all(db: db, zoneID: zoneID, type: "Vacation", keys: ["title", "startDate", "details", "placeName"])
        async let photos = all(db: db, zoneID: zoneID, type: "GalleryItem", keys: ["childRef", "kind", "caption", "note", "date"])
        async let interviews = all(db: db, zoneID: zoneID, type: "Interview", keys: ["childRef", "question", "age", "date", "text"])
        async let traditions = all(db: db, zoneID: zoneID, type: "Tradition", keys: ["title", "when", "details"])
        async let letters = all(db: db, zoneID: zoneID, type: "Letter", keys: ["childRef", "title", "writtenAt", "openDate"])
        async let freeMemories = all(db: db, zoneID: zoneID, type: "Memory", keys: ["title", "date", "text", "placeName"])

        var highlightsR = try await highlights
        var diaryR = try await diary
        var photosR = (try? await photos) ?? []
        var interviewsR = (try? await interviews) ?? []
        var lettersR = (try? await letters) ?? []

        // Børn i egen zone (delt med den anden forælder): deres minder ligger dér, ikke i familiezonen.
        let moved = ((try? await all(db: db, zoneID: zoneID, type: "Child", keys: ["ownZone"])) ?? [])
            .compactMap { r -> (id: String, zone: String)? in
                guard let z = r["ownZone"] as? String, !z.isEmpty else { return nil }
                return (r.recordID.recordName, z)
            }
        if !moved.isEmpty {
            let movedIds = Set(moved.map(\.id))
            highlightsR.removeAll { movedIds.contains(childId($0) ?? "") }
            diaryR.removeAll { movedIds.contains(childId($0) ?? "") }
            photosR.removeAll { movedIds.contains(childId($0) ?? "") }
            interviewsR.removeAll { movedIds.contains(childId($0) ?? "") }
            lettersR.removeAll { movedIds.contains(childId($0) ?? "") }
            for (_, zone) in moved {
                guard let (cdb, cz) = try? await locate(zone) else { continue }
                highlightsR += (try? await all(db: cdb, zoneID: cz, type: "Highlight", keys: ["childRef", "date", "text", "placeName"])) ?? []
                diaryR += (try? await all(db: cdb, zoneID: cz, type: "Diary", keys: ["childRef", "date", "text"])) ?? []
                photosR += (try? await all(db: cdb, zoneID: cz, type: "GalleryItem", keys: ["childRef", "kind", "caption", "note", "date"])) ?? []
                interviewsR += (try? await all(db: cdb, zoneID: cz, type: "Interview", keys: ["childRef", "question", "age", "date", "text"])) ?? []
                lettersR += (try? await all(db: cdb, zoneID: cz, type: "Letter", keys: ["childRef", "title", "writtenAt", "openDate"])) ?? []
            }
        }

        for r in highlightsR {
            out.append(MemorySummary(id: r.recordID.recordName, kind: .highlight, childId: childId(r),
                                     date: r["date"] as? Date, createdAt: r.creationDate ?? Date(),
                                     text: r["text"] as? String ?? "", modifiedAt: r.modificationDate ?? .distantPast,
                                     search: searchText(r, ["placeName"])))
        }
        for r in diaryR {
            out.append(MemorySummary(id: r.recordID.recordName, kind: .diary, childId: childId(r),
                                     date: r["date"] as? Date, createdAt: r.creationDate ?? Date(),
                                     text: r["text"] as? String ?? "", modifiedAt: r.modificationDate ?? .distantPast))
        }
        for r in try await events {
            out.append(MemorySummary(id: r.recordID.recordName, kind: .event, childId: nil,
                                     date: r["date"] as? Date, createdAt: r.creationDate ?? Date(),
                                     text: r["title"] as? String ?? "", modifiedAt: r.modificationDate ?? .distantPast,
                                     search: searchText(r, ["details", "placeName"])))
        }
        for r in try await vacations {
            out.append(MemorySummary(id: r.recordID.recordName, kind: .vacation, childId: nil,
                                     date: r["startDate"] as? Date, createdAt: r.creationDate ?? Date(),
                                     text: r["title"] as? String ?? "", modifiedAt: r.modificationDate ?? .distantPast,
                                     search: searchText(r, ["details", "placeName"])))
        }
        // De nyere typer: kun til "Seneste i familien" — en fejl her må ikke tømme forsiden.
        for r in photosR {
            let caption = r["caption"] as? String ?? ""
            let note = r["note"] as? String ?? ""
            out.append(MemorySummary(id: r.recordID.recordName, kind: .photo, childId: childId(r),
                                     date: (r["date"] as? Date) ?? r.creationDate, createdAt: r.creationDate ?? Date(),
                                     text: [caption, note].filter { !$0.isEmpty }.joined(separator: " · "),
                                     modifiedAt: r.modificationDate ?? .distantPast,
                                     detail: r["kind"] as? String ?? ""))
        }
        for r in interviewsR {
            let age = Int(r["age"] as? Int64 ?? 0)
            out.append(MemorySummary(id: r.recordID.recordName, kind: .interview, childId: childId(r),
                                     date: r["date"] as? Date, createdAt: r.creationDate ?? Date(),
                                     text: "\(age == 1 ? "1 år" : "\(age) år"): \(Constants.interviewQuestion(r["question"] as? String ?? ""))",
                                     modifiedAt: r.modificationDate ?? .distantPast,
                                     search: searchText(r, ["text"])))
        }
        for r in (try? await traditions) ?? [] {
            out.append(MemorySummary(id: r.recordID.recordName, kind: .tradition, childId: nil,
                                     date: nil, createdAt: r.creationDate ?? Date(),
                                     text: r["title"] as? String ?? "", modifiedAt: r.modificationDate ?? .distantPast,
                                     search: searchText(r, ["when", "details"])))
        }
        for r in (try? await freeMemories) ?? [] {
            out.append(MemorySummary(id: r.recordID.recordName, kind: .memory, childId: nil,
                                     date: r["date"] as? Date, createdAt: r.creationDate ?? Date(),
                                     text: r["title"] as? String ?? "", modifiedAt: r.modificationDate ?? .distantPast,
                                     search: searchText(r, ["text", "placeName"])))
        }
        for r in lettersR {
            let title = r["title"] as? String ?? ""
            let sealed = (r["openDate"] as? Date).map { $0 > Date() } ?? false
            if sealed, MeChild.id != nil, childId(r) == MeChild.id { continue }   // barnet selv (#48) ser ikke forseglede breve
            out.append(MemorySummary(id: r.recordID.recordName, kind: .letter, childId: childId(r),
                                     date: r["writtenAt"] as? Date, createdAt: r.creationDate ?? Date(),
                                     text: (title.isEmpty ? "Et brev" : title) + (sealed ? " (forseglet)" : ""),
                                     modifiedAt: r.modificationDate ?? .distantPast))
        }
        return out
    }

    /// Henter kun billedfelterne for ét minde og returnerer forsidebilledet.
    func coverPhoto(familyId: String, memory: MemorySummary) async throws -> Data? {
        // Et barns minde ligger i barnets zone, hvis barnet er flyttet dertil.
        let (db, zoneID) = memory.childId != nil ? try await locateChild(memory.childId!) : try await locate(familyId)
        let id = CKRecord.ID(recordName: memory.id, zoneID: zoneID)
        let keys: [CKRecord.FieldKey]
        switch memory.kind {
        case .highlight: keys = ["photos"]
        case .diary, .photo: keys = ["photo"]
        case .event, .vacation, .tradition, .memory: keys = ["photos", "photo", "coverIndex"]
        case .interview: return nil
        case .letter:
            // Et forseglet brev viser ikke sit billede, før det må åbnes.
            if memory.text.hasSuffix("(forseglet)") { return nil }
            keys = ["photo"]
        }
        func cover(_ record: CKRecord) -> Data? {
            switch memory.kind {
            case .highlight: return Self.assetsData(record["photos"]).first
            case .diary, .photo, .letter: return Self.assetData(record["photo"])
            case .event, .vacation, .tradition, .memory: return Self.photoSet(from: record).coverPhoto
            case .interview: return nil
            }
        }
        // Fra billedcachen, hvis mindet ikke er ændret, siden forsiden sidst blev hentet.
        func cachedCover() -> Data? {
            guard memory.modifiedAt > .distantPast else { return nil }
            let cached = CKRecord(recordType: "cover", recordID: id)
            for k in keys {
                guard let v = AssetCache.read(id: id, modified: memory.modifiedAt, key: k) else { return nil }
                cached[k] = v
            }
            return cover(cached)
        }
        // Thumb (synkroniseret med kopien) er nok til kortene på Hjem — ingen original hentes (#62).
        // Fuld skærm fra Hjem beder om originalen (`withOriginals`). Et lille thumb fra 1.3 dur kun,
        // hvis originalen selv er så lille; ellers hentes den, og thumbet laves om.
        if !Self.wantOriginals, memory.modifiedAt > .distantPast,
           let thumb = AssetCache.read(id: id, modified: memory.modifiedAt, key: Self.thumbKey) as? CKAsset,
           let data = thumb.fileURL.flatMap({ try? Data(contentsOf: $0) }) {
            if !ImageTools.isSmallThumb(data) { return data }
            if let original = cachedCover() {
                return ImageTools.isSmallThumb(data, original: original) ? original : data
            }
        }
        if let original = cachedCover() { return original }
        let results = try await db.records(for: [id], desiredKeys: keys)
        guard let record = try results[id]?.get() else { return nil }
        for k in keys { record[k] = AssetCache.store(record, key: k) }
        Self.refreshThumbs([record])   // næste gang er thumbet nok
        return cover(record)
    }

    func birthdays(familyId: String) async throws -> [CustomBirthday] {
        let (db, zoneID) = try await locate(familyId)
        return try await all(db: db, zoneID: zoneID, type: "Birthday").compactMap { r in
            guard let date = r["date"] as? Date else { return nil }
            return CustomBirthday(id: r.recordID.recordName,
                                  name: r["name"] as? String ?? "",
                                  date: date,
                                  emoji: r["emoji"] as? String ?? "🎂")
        }
    }

    func addBirthday(familyId: String, name: String, date: Date, emoji: String) async throws -> CustomBirthday {
        let (db, zoneID) = try await locate(familyId)
        let record = CKRecord(recordType: "Birthday", recordID: CKRecord.ID(recordName: newId("bday"), zoneID: zoneID))
        record["familyRef"] = familyRef(zoneID)
        record["name"] = name.trimmingCharacters(in: .whitespaces) as CKRecordValue
        record["date"] = date as CKRecordValue
        let trimmedEmoji = emoji.trimmingCharacters(in: .whitespaces)
        record["emoji"] = (trimmedEmoji.isEmpty ? "🎂" : trimmedEmoji) as CKRecordValue
        let saved = try await persist(record, in: db)
        return CustomBirthday(id: saved.recordID.recordName, name: name, date: date, emoji: trimmedEmoji.isEmpty ? "🎂" : trimmedEmoji)
    }

    func updateBirthday(familyId: String, _ birthday: CustomBirthday) async throws {
        let (db, zoneID) = try await locate(familyId)
        let record = try await db.record(for: CKRecord.ID(recordName: birthday.id, zoneID: zoneID))
        record["name"] = birthday.name.trimmingCharacters(in: .whitespaces) as CKRecordValue
        record["date"] = birthday.date as CKRecordValue
        let trimmedEmoji = birthday.emoji.trimmingCharacters(in: .whitespaces)
        record["emoji"] = (trimmedEmoji.isEmpty ? "🎂" : trimmedEmoji) as CKRecordValue
        _ = try await persist(record, in: db)
    }

    func deleteBirthday(familyId: String, id: String) async throws {
        let (db, zoneID) = try await locate(familyId)
        try await remove(CKRecord.ID(recordName: id, zoneID: zoneID), in: db)
    }

    // MARK: - Video/lyd på en vilkårlig record (højdepunkt, brev, interview, tradition)

    /// Sætter/fjerner video- og lydfelter på en record uden at hente de andre felter.
    private func setMedia(recordID: CKRecord.ID, in db: CKDatabase, video: MediaChange, audio: MediaChange) async throws {
        if case .keep = video, case .keep = audio { return }
        let results = try await db.records(for: [recordID], desiredKeys: ["videoDuration", "audioDuration"])
        guard let record = try results[recordID]?.get() else { throw StoreError.notFound }
        func apply(_ change: MediaChange, asset key: String, duration durationKey: String) {
            switch change {
            case .keep: break
            case .remove:
                record[key] = nil
                record[durationKey] = nil
            case .set(let url, let seconds):
                record[key] = Self.uploadAsset(copying: url)
                record[durationKey] = seconds as CKRecordValue
            }
        }
        apply(video, asset: "video", duration: "videoDuration")
        apply(audio, asset: "audio", duration: "audioDuration")
        _ = try await persist(record, in: db)
    }

    /// Henter video/lyd til lokale filer, klar til afspilning.
    private func media(recordID: CKRecord.ID, in db: CKDatabase) async throws -> (video: URL?, audio: URL?) {
        let results = try await db.records(for: [recordID], desiredKeys: ["video", "audio"])
        guard let record = try results[recordID]?.get() else { return (nil, nil) }
        let id = recordID.recordName
        func local(_ key: String, ext: String) -> URL? {
            guard let source = (record[key] as? CKAsset)?.fileURL else { return nil }
            let target = MediaFiles.dir.appendingPathComponent("\(id)-\(key).\(ext)")
            try? FileManager.default.removeItem(at: target)
            return (try? FileManager.default.copyItem(at: source, to: target)) != nil ? target : nil
        }
        return (local("video", ext: "mp4"), local("audio", ext: "m4a"))
    }

    func setLetterVideo(childId: String, id: String, video: MediaChange) async throws {
        let (db, zoneID) = try await locateChild(childId)
        try await setMedia(recordID: CKRecord.ID(recordName: id, zoneID: zoneID), in: db, video: video, audio: .keep)
    }

    func letterVideo(childId: String, id: String) async throws -> URL? {
        let (db, zoneID) = try await locateChild(childId)
        return try await media(recordID: CKRecord.ID(recordName: id, zoneID: zoneID), in: db).video
    }

    // MARK: - Det årlige interview

    func interviews(childId: String) async throws -> [InterviewAnswer] {
        try await childRecords(childId, type: "Interview",
                               keys: ["childRef", "age", "question", "text", "date", "audioDuration", "videoDuration"])
        .map { r in
            InterviewAnswer(id: r.recordID.recordName,
                            age: Int(r["age"] as? Int64 ?? 0),
                            question: r["question"] as? String ?? "",
                            text: r["text"] as? String ?? "",
                            date: r["date"] as? Date ?? r.creationDate ?? Date(),
                            audioDuration: r["audioDuration"] as? Double,
                            videoDuration: r["videoDuration"] as? Double)
        }
    }

    func saveInterviewAnswer(childId: String, _ answer: InterviewAnswer, audio: MediaChange, video: MediaChange) async throws {
        let (db, zoneID) = try await locateChild(childId)
        let recordID = CKRecord.ID(recordName: answer.id, zoneID: zoneID)
        let record: CKRecord
        if let existing = try? await db.records(for: [recordID], desiredKeys: ["age"])[recordID]?.get() {
            record = existing
        } else {
            record = CKRecord(recordType: "Interview", recordID: recordID)
            record["childRef"] = childRef(childId, zoneID)
        }
        record["age"] = Int64(answer.age) as CKRecordValue
        record["question"] = answer.question as CKRecordValue
        record["text"] = answer.text as CKRecordValue
        record["date"] = answer.date as CKRecordValue
        // Tekst og video/lyd gemmes i ét hug — så en fejl undervejs ikke efterlader et halvt svar.
        Self.applyMedia(video, asset: "video", duration: "videoDuration", to: record)
        Self.applyMedia(audio, asset: "audio", duration: "audioDuration", to: record)
        _ = try await persist(record, in: db)
    }

    private static func applyMedia(_ change: MediaChange, asset key: String, duration durationKey: String, to record: CKRecord) {
        switch change {
        case .keep: break
        case .remove:
            record[key] = nil
            record[durationKey] = nil
        case .set(let url, let seconds):
            record[key] = uploadAsset(copying: url)
            record[durationKey] = seconds as CKRecordValue
        }
    }

    func deleteInterviewAnswer(childId: String, id: String) async throws {
        let (db, zoneID) = try await locateChild(childId)
        try await remove(CKRecord.ID(recordName: id, zoneID: zoneID), in: db)
    }

    func interviewMedia(childId: String, id: String) async throws -> (video: URL?, audio: URL?) {
        let (db, zoneID) = try await locateChild(childId)
        return try await media(recordID: CKRecord.ID(recordName: id, zoneID: zoneID), in: db)
    }

    // MARK: - Traditioner

    func traditions(familyId: String) async throws -> [Tradition] {
        let (db, zoneID) = try await locate(familyId)
        return try await all(db: db, zoneID: zoneID, type: "Tradition",
                             keys: ["familyRef", "title", "when", "details", "captions", "coverIndex", "audioDuration"],
                             assetKeys: ["photos", "photo"])
        .map { r in
            Tradition(id: r.recordID.recordName,
                      title: r["title"] as? String ?? "",
                      when: r["when"] as? String ?? "",
                      details: r["details"] as? String ?? "",
                      photos: Self.photoSet(from: r),
                      audioDuration: r["audioDuration"] as? Double)
        }
        .sorted { $0.title < $1.title }
    }

    func saveTradition(familyId: String, _ tradition: Tradition, audio: MediaChange) async throws {
        let (db, zoneID) = try await locate(familyId)
        let recordID = CKRecord.ID(recordName: tradition.id, zoneID: zoneID)
        let record: CKRecord
        if let existing = try? await db.records(for: [recordID], desiredKeys: ["title"])[recordID]?.get() {
            record = existing
        } else {
            record = CKRecord(recordType: "Tradition", recordID: recordID)
            record["familyRef"] = familyRef(zoneID)
        }
        record["title"] = tradition.title.trimmingCharacters(in: .whitespaces) as CKRecordValue
        record["when"] = tradition.when as CKRecordValue
        record["details"] = tradition.details as CKRecordValue
        Self.setPhotos(tradition.photos, on: record)
        _ = try await persist(record, in: db)
        try await setMedia(recordID: recordID, in: db, video: .keep, audio: audio)
    }

    func deleteTradition(familyId: String, id: String) async throws {
        let (db, zoneID) = try await locate(familyId)
        try await remove(CKRecord.ID(recordName: id, zoneID: zoneID), in: db)
    }

    func traditionAudio(familyId: String, id: String) async throws -> URL? {
        let (db, zoneID) = try await locate(familyId)
        return try await media(recordID: CKRecord.ID(recordName: id, zoneID: zoneID), in: db).audio
    }

    // MARK: - Premium for familien

    func familyPremium(familyId: String) async -> Date? {
        guard let (db, zoneID) = try? await locate(familyId) else { return nil }
        let id = CKRecord.ID(recordName: "family", zoneID: zoneID)
        let record = try? await db.records(for: [id], desiredKeys: ["premiumUntil"])[id]?.get()
        return record?["premiumUntil"] as? Date
    }

    func setFamilyPremium(familyId: String, until: Date?) async throws {
        let (db, zoneID) = try await locate(familyId)
        let id = CKRecord.ID(recordName: "family", zoneID: zoneID)
        guard let record = try await db.records(for: [id], desiredKeys: ["premiumUntil"])[id]?.get() else { return }
        // Skriv kun, hvis datoen bliver senere — så et udløbet abonnement på én telefon ikke
        // overskriver et engangskøb fra en anden.
        let current = record["premiumUntil"] as? Date
        guard let until, until > (current ?? .distantPast) else { return }
        record["premiumUntil"] = until as CKRecordValue
        _ = try await persist(record, in: db)
    }

    // MARK: - Minder

    func memories(familyId: String) async throws -> [FamilyMemory] {
        let (db, zoneID) = try await locate(familyId)
        return try await all(db: db, zoneID: zoneID, type: "Memory",
                             keys: ["familyRef", "title", "date", "endDate", "text", "childIds", "personIds", "captions", "coverIndex",
                                    "placeName", "placeAddress", "location"],
                             assetKeys: ["photos", "photo"]).map { r in
            FamilyMemory(id: r.recordID.recordName,
                         title: r["title"] as? String ?? "",
                         date: r["date"] as? Date,
                         endDate: r["endDate"] as? Date,
                         text: r["text"] as? String ?? "",
                         photos: Self.photoSet(from: r),
                         childIds: r["childIds"] as? [String] ?? [],
                         personIds: r["personIds"] as? [String] ?? [],
                         place: Self.place(from: r))
        }
        .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    func saveMemory(familyId: String, _ memory: FamilyMemory) async throws {
        let (db, zoneID) = try await locate(familyId)
        let recordID = CKRecord.ID(recordName: memory.id, zoneID: zoneID)
        let record: CKRecord
        if let existing = try? await db.records(for: [recordID], desiredKeys: ["title"])[recordID]?.get() {
            record = existing
        } else {
            record = CKRecord(recordType: "Memory", recordID: recordID)
            record["familyRef"] = familyRef(zoneID)
        }
        record["title"] = memory.title.trimmingCharacters(in: .whitespaces) as CKRecordValue
        record["date"] = memory.date as CKRecordValue?
        record["endDate"] = memory.endDate as CKRecordValue?
        record["text"] = memory.text as CKRecordValue
        record["childIds"] = memory.childIds.isEmpty ? nil : memory.childIds as CKRecordValue
        record["personIds"] = memory.personIds.isEmpty ? nil : memory.personIds as CKRecordValue
        Self.setPhotos(memory.photos, on: record)
        Self.setPlace(memory.place, on: record)
        _ = try await persist(record, in: db)
    }

    func deleteMemory(familyId: String, id: String) async throws {
        let (db, zoneID) = try await locate(familyId)
        try await remove(CKRecord.ID(recordName: id, zoneID: zoneID), in: db)
    }

    // MARK: - Opskrifter

    func recipes(familyId: String) async throws -> [Recipe] {
        let (db, zoneID) = try await locate(familyId)
        return try await all(db: db, zoneID: zoneID, type: "Recipe",
                             keys: ["familyRef", "title", "fromWhom", "servings", "ingredients", "method", "story", "category",
                                    "captions", "coverIndex"],
                             assetKeys: ["photos", "photo"]).map { r in
            Recipe(id: r.recordID.recordName,
                   title: r["title"] as? String ?? "",
                   fromWhom: r["fromWhom"] as? String ?? "",
                   servings: r["servings"] as? String ?? "",
                   ingredients: r["ingredients"] as? String ?? "",
                   method: r["method"] as? String ?? "",
                   story: r["story"] as? String ?? "",
                   category: r["category"] as? String ?? "",
                   photos: Self.photoSet(from: r))
        }
        .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
    }

    func saveRecipe(familyId: String, _ recipe: Recipe) async throws {
        let (db, zoneID) = try await locate(familyId)
        let recordID = CKRecord.ID(recordName: recipe.id, zoneID: zoneID)
        let record: CKRecord
        if let existing = try? await db.records(for: [recordID], desiredKeys: ["title"])[recordID]?.get() {
            record = existing
        } else {
            record = CKRecord(recordType: "Recipe", recordID: recordID)
            record["familyRef"] = familyRef(zoneID)
        }
        record["title"] = recipe.title.trimmingCharacters(in: .whitespaces) as CKRecordValue
        record["fromWhom"] = recipe.fromWhom.trimmingCharacters(in: .whitespaces) as CKRecordValue
        record["servings"] = recipe.servings.trimmingCharacters(in: .whitespaces) as CKRecordValue
        record["ingredients"] = recipe.ingredients as CKRecordValue
        record["method"] = recipe.method as CKRecordValue
        record["story"] = recipe.story as CKRecordValue
        record["category"] = recipe.category as CKRecordValue
        Self.setPhotos(recipe.photos, on: record)
        _ = try await persist(record, in: db)
    }

    func deleteRecipe(familyId: String, id: String) async throws {
        let (db, zoneID) = try await locate(familyId)
        try await remove(CKRecord.ID(recordName: id, zoneID: zoneID), in: db)
    }

    // MARK: - Reaktioner og kommentarer

    func comments(familyId: String) async throws -> [Comment] {
        let (db, zoneID) = try await locate(familyId)
        return try await all(db: db, zoneID: zoneID, type: "Comment",
                             keys: ["familyRef", "targetId", "text", "emoji", "authorId", "authorName"]).map { r in
            Comment(id: r.recordID.recordName,
                    targetId: r["targetId"] as? String ?? "",
                    text: r["text"] as? String ?? "",
                    emoji: r["emoji"] as? String ?? "",
                    authorId: r["authorId"] as? String ?? "",
                    authorName: r["authorName"] as? String ?? "",
                    createdAt: r.creationDate ?? Date())
        }
        .sorted { $0.createdAt < $1.createdAt }
    }

    func addComment(familyId: String, _ comment: Comment) async throws {
        let (db, zoneID) = try await locate(familyId)
        let record = CKRecord(recordType: "Comment", recordID: CKRecord.ID(recordName: comment.id, zoneID: zoneID))
        record["familyRef"] = familyRef(zoneID)
        record["targetId"] = comment.targetId as CKRecordValue
        record["text"] = comment.text as CKRecordValue
        record["emoji"] = comment.emoji as CKRecordValue
        record["authorId"] = comment.authorId as CKRecordValue
        record["authorName"] = comment.authorName as CKRecordValue
        _ = try await persist(record, in: db)
    }

    func deleteComment(familyId: String, id: String) async throws {
        let (db, zoneID) = try await locate(familyId)
        try await remove(CKRecord.ID(recordName: id, zoneID: zoneID), in: db)
    }

    // MARK: - Familietræ

    func persons(familyId: String) async throws -> [Person] {
        let (db, zoneID) = try await locate(familyId)
        return try await all(db: db, zoneID: zoneID, type: "Person",
                             keys: ["familyRef", "name", "birthDate", "deathDate", "role", "parentIds", "partnerIds", "childId"],
                             assetKeys: ["photo"]).map { r in
            Person(id: r.recordID.recordName,
                   name: r["name"] as? String ?? "",
                   birthDate: r["birthDate"] as? Date,
                   deathDate: r["deathDate"] as? Date,
                   role: r["role"] as? String ?? "",
                   photo: Self.assetData(r["photo"]),
                   thumb: Self.assetData(r[Self.thumbKey]),
                   photoLoaded: Self.assetsLoaded(r, keys: ["photo"]),
                   parentIds: r["parentIds"] as? [String] ?? [],
                   partnerIds: r["partnerIds"] as? [String] ?? [],
                   childId: r["childId"] as? String)
        }
    }

    func savePerson(familyId: String, _ person: Person) async throws {
        let (db, zoneID) = try await locate(familyId)
        let recordID = CKRecord.ID(recordName: person.id, zoneID: zoneID)
        let record: CKRecord
        if let existing = try? await db.record(for: recordID) {
            record = existing
        } else {
            record = CKRecord(recordType: "Person", recordID: recordID)
            record["familyRef"] = familyRef(zoneID)
        }
        record["name"] = person.name.trimmingCharacters(in: .whitespaces) as CKRecordValue
        record["birthDate"] = person.birthDate as CKRecordValue?
        record["deathDate"] = person.deathDate as CKRecordValue?
        record["role"] = person.role as CKRecordValue
        if person.photoLoaded { record["photo"] = person.photo.flatMap { Self.asset(from: $0) } }   // ellers urørt (#62)
        record["parentIds"] = person.parentIds.isEmpty ? nil : person.parentIds as CKRecordValue
        record["partnerIds"] = person.partnerIds.isEmpty ? nil : person.partnerIds as CKRecordValue
        record["childId"] = person.childId as CKRecordValue?
        _ = try await persist(record, in: db)
    }

    func deletePerson(familyId: String, id: String) async throws {
        let (db, zoneID) = try await locate(familyId)
        try await remove(CKRecord.ID(recordName: id, zoneID: zoneID), in: db)
    }



    // MARK: - Billedcache på telefonen
    // Lister hentes uden billeder (hurtigt). Billederne tages fra en cache på disken, og kun
    // dem, der mangler eller er ændret (ny modificationDate), hentes fra iCloud — i bundter.
    // Filnavnet indeholder recordens ændringstidspunkt, så en redigering giver nye filer.
    private enum AssetCache {
        static let dir: URL = {
            let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            let dir = base.appendingPathComponent("AssetCache", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }()

        private static func base(id: CKRecord.ID, modified: Date?, key: String) -> String {
            let ts = Int((modified ?? .distantPast).timeIntervalSince1970)
            return "\(id.zoneID.zoneName)__\(id.recordName)__\(key)__\(ts)"
        }
        private static func base(_ record: CKRecord, _ key: String) -> String {
            base(id: record.recordID, modified: record.modificationDate, key: key)
        }

        /// Læser et asset-felt fra cachen. `.some(nil)` = vi ved, feltet er tomt; `nil` = ikke i cachen.
        static func read(_ record: CKRecord, key: String) -> CKRecordValue?? {
            read(id: record.recordID, modified: record.modificationDate, key: key)
        }

        static func read(id: CKRecord.ID, modified: Date?, key: String) -> CKRecordValue?? {
            let b = base(id: id, modified: modified, key: key)
            let fm = FileManager.default
            if fm.fileExists(atPath: dir.appendingPathComponent(b + "__none").path) { return .some(nil) }
            // Små tal (fx coverIndex) gemmes også, så forsidevalget følger med.
            if let s = try? String(contentsOf: dir.appendingPathComponent(b + "__int"), encoding: .utf8),
               let n = Int64(s.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return .some(n as CKRecordValue)
            }
            let single = dir.appendingPathComponent(b + ".bin")
            if fm.fileExists(atPath: single.path) { return .some(CKAsset(fileURL: single)) }
            if let s = try? String(contentsOf: dir.appendingPathComponent(b + "__count"), encoding: .utf8),
               let n = Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) {
                let urls = (0..<n).map { dir.appendingPathComponent(b + "__\($0).bin") }
                guard urls.allSatisfy({ fm.fileExists(atPath: $0.path) }) else { return nil }
                return .some(urls.map { CKAsset(fileURL: $0) } as CKRecordValue)
            }
            return nil
        }

        /// Lægger færdige data (fx et thumb lavet på telefonen) i cachen for recorden.
        static func storeData(_ data: Data, for record: CKRecord, key: String) {
            try? data.write(to: dir.appendingPathComponent(base(record, key) + ".bin"), options: .atomic)
        }

        /// Lægger feltets asset(s) fra `record` i cachen og returnerer værdien, recorden skal pege på.
        @discardableResult
        static func store(_ record: CKRecord, key: String) -> CKRecordValue? {
            let b = base(record, key)
            let fm = FileManager.default
            func copy(_ src: URL, to name: String) -> URL? {
                let dst = dir.appendingPathComponent(name)
                try? fm.removeItem(at: dst)
                return (try? fm.copyItem(at: src, to: dst)) != nil ? dst : nil
            }
            if let asset = record[key] as? CKAsset {
                guard let src = asset.fileURL, let dst = copy(src, to: b + ".bin") else { return record[key] }
                return CKAsset(fileURL: dst)
            }
            if let list = record[key] as? [CKAsset] {
                var out: [CKAsset] = []
                for (i, a) in list.enumerated() {
                    guard let src = a.fileURL, let dst = copy(src, to: b + "__\(i).bin") else { return record[key] }
                    out.append(CKAsset(fileURL: dst))
                }
                try? "\(out.count)".write(to: dir.appendingPathComponent(b + "__count"), atomically: true, encoding: .utf8)
                return out as CKRecordValue
            }
            if let n = record[key] as? Int64 {
                try? "\(n)".write(to: dir.appendingPathComponent(b + "__int"), atomically: true, encoding: .utf8)
                return n as CKRecordValue
            }
            try? Data().write(to: dir.appendingPathComponent(b + "__none"))
            return nil
        }

        /// Rydder filer, der ikke er brugt i 60 dage (gamle versioner af redigerede billeder).
        static func prune() {
            let fm = FileManager.default
            let cutoff = Date().addingTimeInterval(-60 * 86_400)
            guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentAccessDateKey]) else { return }
            for f in files {
                let accessed = (try? f.resourceValues(forKeys: [.contentAccessDateKey]))?.contentAccessDate ?? .distantPast
                if accessed < cutoff { try? fm.removeItem(at: f) }
            }
        }
    }

    /// Udfylder billedfelterne på records fra kopien: altid `thumb` (fra cachen), originalerne fra cachen —
    /// og fra iCloud kun, når de skal bruges (`withOriginals`), eller når der ikke er et thumb at vise.
    /// Originaler, der mangler, hentes bagefter i baggrunden.
    private func fillAssets(_ records: [CKRecord], keys: [String], db: CKDatabase) async -> [CKRecord] {
        guard !keys.isEmpty, !records.isEmpty else { return records }
        let wantOriginals = Self.wantOriginals
        var missing: [CKRecord] = []
        var pending: [CKRecord] = []
        for r in records {
            if let thumb = AssetCache.read(r, key: Self.thumbKey) { r[Self.thumbKey] = thumb }
            var complete = true
            for k in keys {
                if let cached = AssetCache.read(r, key: k) { r[k] = cached } else { complete = false }
            }
            guard !complete else { continue }
            if wantOriginals || (r[Self.thumbKey] as? CKAsset) == nil { missing.append(r) } else { pending.append(r) }
        }
        var i = 0
        while i < missing.count {
            let chunk = Array(missing[i..<min(i + 20, missing.count)])
            i += 20
            guard let fetched = try? await SyncLog.measure("billeder ×\(chunk.count)", {
                try await db.records(for: chunk.map(\.recordID), desiredKeys: keys)
            }, count: { $0.count }) else { continue }
            var stored: [CKRecord] = []
            for r in chunk {
                guard let full = try? fetched[r.recordID]?.get() else { continue }
                for k in keys { r[k] = AssetCache.store(full, key: k) }
                stored.append(full)
            }
            // Thumbs laves i baggrunden; indtil da viser listen originalen (listPhoto falder tilbage på den).
            Self.refreshThumbs(stored)
        }
        if !pending.isEmpty { schedulePrefetch(pending, keys: keys, db: db) }
        return records
    }
    // MARK: - Gem og slet
    // Et gem lægges i den lokale kopi med det samme, det er bekræftet af iCloud — så lister er
    // rigtige med det samme, uden at vente på en ny sync.

    /// Gemmer én record. Store filer (video) kan tage minutter at uploade, så ventetiden er
    /// sat op (iCloud giver ellers op efter ca. et minut og melder "netværksfejl"), og
    /// midlertidige fejl prøves igen op til tre gange — med den ventetid, iCloud selv beder om.
    private func saveWithRetry(_ record: CKRecord, in db: CKDatabase) async throws -> CKRecord {
        var attempt = 0
        while true {
            // Uden netværk venter CloudKit ellers på forbindelsen (op til 30 min for store videoer) —
            // sig det med det samme i stedet for et evigt "Gemmer…".
            guard NetworkWatch.shared.isOnline else { throw CKError(.networkUnavailable) }
            do {
                return try await saveOnce(record, in: db)
            } catch let error as CKError where attempt < 3 && Self.isRetryable(error) {
                attempt += 1
                let wait = error.retryAfterSeconds ?? Double(attempt * 2)
                try await Task.sleep(for: .seconds(min(wait, 30)))
            }
        }
    }

    private static func isRetryable(_ error: CKError) -> Bool {
        switch error.code {
        case .networkFailure, .networkUnavailable, .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return true
        default:
            return false
        }
    }

    private func saveOnce(_ record: CKRecord, in db: CKDatabase) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { continuation in
            let op = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
            op.savePolicy = .changedKeys
            op.qualityOfService = .userInitiated
            let config = CKOperation.Configuration()
            config.timeoutIntervalForRequest = 120       // pr. netværksforespørgsel
            config.timeoutIntervalForResource = 30 * 60  // hele uploaden, fx en video på mobilnet
            op.configuration = config
            var saved: CKRecord?
            var recordError: Error?
            op.perRecordSaveBlock = { _, result in
                switch result {
                case .success(let r): saved = r
                case .failure(let e): recordError = e
                }
            }
            op.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    if let saved { continuation.resume(returning: saved) }
                    // Fejlen på selve recorden (fx et billede, der ikke kunne uploades) må ikke gå tabt.
                    else { continuation.resume(throwing: recordError ?? CKError(.internalError)) }
                case .failure(let error):
                    continuation.resume(throwing: Self.unwrapped(error))
                }
            }
            db.add(op)
        }
    }

    /// Ved "delvis fejl" (kode 2) ligger den rigtige fejl pr. record indeni — den er mere sigende.
    private static func unwrapped(_ error: Error) -> Error {
        guard let ck = error as? CKError, ck.code == .partialFailure,
              let inner = ck.partialErrorsByItemID?.values.first else { return error }
        return inner
    }

    /// Sletter en record i iCloud og fjerner den fra kopien.
    private func remove(_ id: CKRecord.ID, in db: CKDatabase) async throws {
        try await SyncLog.measure("slet") { _ = try await db.deleteRecord(withID: id) }
        local.apply(changed: [], deleted: [id], in: id.zoneID, createIfMissing: false)
    }
    // MARK: - Hjælpere

    // Zone-placeringer gemmes på enheden, så opstart ikke skal slå alle zoner op
    // over netværket før første skærm kan vises.
    private static let zoneIndexKey = "mindebog.zoneIndex"     // zoneName -> "private|<owner>" / "shared|<owner>"
    private static let childZoneKey = "mindebog.childZones"    // childId -> zoneName

    private func remember(_ zoneID: CKRecordZone.ID, in db: CKDatabase) {
        zoneCache[zoneID.zoneName] = (db, zoneID)
        var index = UserDefaults.standard.dictionary(forKey: Self.zoneIndexKey) as? [String: String] ?? [:]
        let scope = db === sharedDB ? "shared" : "private"
        index[zoneID.zoneName] = "\(scope)|\(zoneID.ownerName)"
        UserDefaults.standard.set(index, forKey: Self.zoneIndexKey)
    }

    private func rememberChild(_ childId: String, zoneName: String) {
        var map = UserDefaults.standard.dictionary(forKey: Self.childZoneKey) as? [String: String] ?? [:]
        guard map[childId] != zoneName else { return }
        map[childId] = zoneName
        UserDefaults.standard.set(map, forKey: Self.childZoneKey)
    }

    private func restore(_ zoneName: String) -> (CKDatabase, CKRecordZone.ID)? {
        let index = UserDefaults.standard.dictionary(forKey: Self.zoneIndexKey) as? [String: String] ?? [:]
        guard let entry = index[zoneName] else { return nil }
        let parts = entry.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        let db = parts[0] == "shared" ? sharedDB : privateDB
        let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: parts[1])
        zoneCache[zoneName] = (db, zoneID)
        return (db, zoneID)
    }

    private func locate(_ familyId: String) async throws -> (CKDatabase, CKRecordZone.ID) {
        if let cached = zoneCache[familyId] { return (cached.db, cached.zone) }
        if let restored = restore(familyId) { return restored }
        _ = try await families(for: "")
        guard let cached = zoneCache[familyId] else { throw StoreError.notFound }
        return (cached.db, cached.zone)
    }

    // Barne-id'er er unikke. Kendt barn → dets zone direkte; ellers slå op i alle kendte zoner.
    private func locateChild(_ childId: String) async throws -> (CKDatabase, CKRecordZone.ID) {
        let map = UserDefaults.standard.dictionary(forKey: Self.childZoneKey) as? [String: String] ?? [:]
        if let zoneName = map[childId], let found = try? await locate(zoneName) { return found }
        if zoneCache.isEmpty { _ = try await families(for: "") }
        // Et barn i egen zone findes også som "skilt" i familiezonen — barnets egen zone vinder altid.
        if let own = try? await locate(Self.childZonePrefix + childId) {
            rememberChild(childId, zoneName: own.1.zoneName)
            return own
        }
        for (_, entry) in zoneCache where entry.zone.zoneName.hasPrefix("family_") {
            let id = CKRecord.ID(recordName: childId, zoneID: entry.zone)
            guard let record = try? await entry.db.record(for: id) else { continue }
            if let zoneName = record["ownZone"] as? String, !zoneName.isEmpty, let own = try? await locate(zoneName) {
                rememberChild(childId, zoneName: zoneName)
                return own
            }
            rememberChild(childId, zoneName: entry.zone.zoneName)
            return (entry.db, entry.zone)
        }
        throw StoreError.notFound
    }

    private func familyRecord(db: CKDatabase, zoneID: CKRecordZone.ID) async throws -> CKRecord {
        try await db.record(for: CKRecord.ID(recordName: "family", zoneID: zoneID))
    }

    private func shareTitle(_ familyName: String?) -> String {
        let name = (familyName ?? "").trimmingCharacters(in: .whitespaces)
        return name.isEmpty || name == "Vores familie" ? "Vores familie" : "Vores familie · \(name)"
    }

    // MARK: - Adgang (deltagere i delingen)

    /// Alle i den delte familie med deres adgang — til "Familie og adgang".
    func participants(familyId: String) async throws -> [FamilyParticipant] {
        let (db, zoneID) = try await locate(familyId)
        guard let share = try? await fetchShare(db: db, zoneID: zoneID) else { return [] }
        var savedNames: [String: String] = [:]
        for r in (try? await all(db: db, zoneID: zoneID, type: "Member")) ?? [] {
            if let uid = r["userId"] as? String, let n = r["name"] as? String, !n.isEmpty { savedNames[uid] = n }
        }
        return participants(of: share, db: db, zoneID: zoneID, namesFrom: savedNames)
    }

    /// Deltagerne i en deling (familie eller barn) med navne og adgang.
    private func participants(of share: CKShare, db: CKDatabase, zoneID: CKRecordZone.ID,
                              namesFrom: [String: String]?) -> [FamilyParticipant] {
        let me = share.currentUserParticipant
        let myId = UserDefaults.standard.string(forKey: "mindebog.userId")
        let myName = UserDefaults.standard.string(forKey: nameKey)
        // Navne fra familien (Member-records) bruges også for barnets deling.
        let savedNames = namesFrom ?? SharedNames.members
        return share.participants.map { p in
            let identity = p.userIdentity
            let uid = (p == me ? myId : nil) ?? identity.userRecordID?.recordName
            var name = uid.flatMap { savedNames[$0] } ?? ""
            if name.isEmpty {
                name = identity.nameComponents.map { PersonNameComponentsFormatter.localizedString(from: $0, style: .default) } ?? ""
            }
            if p == me, name.isEmpty, let myName, myName != "Forælder" { name = myName }
            let contact = identity.lookupInfo?.emailAddress ?? identity.lookupInfo?.phoneNumber ?? ""
            if name.isEmpty { name = contact.isEmpty ? (p.role == .owner ? "Ejer" : "Inviteret") : contact }
            let access: FamilyParticipant.Access = p.role == .owner ? .owner : (p.permission == .readOnly ? .viewer : .editor)
            return FamilyParticipant(id: Self.participantKey(p, in: share), name: name, contact: contact == name ? "" : contact,
                                     access: access, pending: p.acceptanceStatus == .pending, isMe: p == me)
        }
        .sorted { ($0.access.rank, $0.name) < ($1.access.rank, $1.name) }
    }

    /// Kun ejeren kan ændre adgang og fjerne folk.
    func isShareOwner(familyId: String) async -> Bool {
        guard let (db, _) = try? await locate(familyId) else { return false }
        return db === privateDB
    }

    func setParticipant(familyId: String, id: String, readOnly: Bool) async throws {
        try await changeShare(familyId: familyId) { share in
            guard let p = share.participants.first(where: { Self.participantKey($0, in: share) == id }), p.role != .owner else { return }
            p.permission = readOnly ? .readOnly : .readWrite
        }
    }

    func removeParticipant(familyId: String, id: String) async throws {
        try await changeShare(familyId: familyId) { share in
            guard let p = share.participants.first(where: { Self.participantKey($0, in: share) == id }), p.role != .owner else { return }
            share.removeParticipant(p)
        }
    }

    private func changeShare(familyId: String, _ change: (CKShare) -> Void) async throws {
        let (db, zoneID) = try await locate(familyId)
        let share = try await fetchShare(db: db, zoneID: zoneID)
        change(share)
        let (saved, _) = try await db.modifyRecords(saving: [share], deleting: [], savePolicy: .changedKeys)
        _ = try saved[share.recordID]?.get()
    }

    /// Et id for deltageren, der er det samme fra gang til gang (#37). Uden bruger-id, mail eller telefon
    /// (typisk en afventende invitation) bruges rolle, rettighed, status og pladsen i listen — ikke hashValue,
    /// som skifter mellem app-starter.
    private static func participantKey(_ p: CKShare.Participant, in share: CKShare) -> String {
        let identity = p.userIdentity
        if let key = identity.userRecordID?.recordName
            ?? identity.lookupInfo?.emailAddress
            ?? identity.lookupInfo?.phoneNumber { return key }
        let index = share.participants.firstIndex(of: p) ?? 0
        return "p-\(p.role.rawValue)-\(p.permission.rawValue)-\(p.acceptanceStatus.rawValue)-\(index)"
    }

    private func fetchShare(db: CKDatabase, zoneID: CKRecordZone.ID) async throws -> CKShare {
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        guard let share = try await SyncLog.measure("deling", { try await db.record(for: shareID) }) as? CKShare else {
            throw StoreError.notFound
        }
        return share
    }

    /// Alle records af en type i zonen — fra den lokale kopi (#62). `keys` er uden betydning nu (kopien
    /// har alle tekstfelter) og står kun som dokumentation af, hvad skærmen bruger.
    /// `assetKeys`: billedfelter, der tages fra cachen (og hentes fra iCloud, hvis de mangler).
    private func all(db: CKDatabase, zoneID: CKRecordZone.ID, type: String,
                     keys: [CKRecord.FieldKey]? = nil, assetKeys: [String] = [],
                     matching: (CKRecord) -> Bool = { _ in true }) async throws -> [CKRecord] {
        try await ensureSynced(zoneID, db: db)
        // Kopier, så billedfelterne ikke ender i kopien i hukommelsen.
        let records = local.records(in: zoneID, type: type).filter(matching).map { $0.copy() as! CKRecord }
        return await fillAssets(records, keys: assetKeys, db: db)
    }

    /// Et barns records af en type — fra den lokale kopi.
    private func childRecords(_ childId: String, type: String,
                              keys: [CKRecord.FieldKey]? = nil, assetKeys: [String] = [],
                              extraMatch: ((CKRecord) -> Bool)? = nil) async throws -> [CKRecord] {
        let (db, zoneID) = try await locateChild(childId)
        let ref = childRef(childId, zoneID)
        return try await all(db: db, zoneID: zoneID, type: type, keys: keys, assetKeys: assetKeys) { r in
            (r["childRef"] as? CKRecord.Reference)?.recordID == ref.recordID && (extraMatch?(r) ?? true)
        }
    }

    /// Søgning direkte i iCloud (med filer). Bruges kun, hvor kopien ikke rækker: flytning af et barn
    /// til egen zone, hvor billeder og video skal kopieres med.
    private func queryAll(db: CKDatabase, zoneID: CKRecordZone.ID, type: String,
                          keys: [CKRecord.FieldKey]? = nil,
                          predicate: NSPredicate = NSPredicate(value: true)) async throws -> [CKRecord] {
        try await SyncLog.measure("søgning \(type)", {
            let query = CKQuery(recordType: type, predicate: predicate)
            var results: [CKRecord] = []
            var (matches, cursor) = try await db.records(matching: query, inZoneWith: zoneID,
                                                         desiredKeys: keys, resultsLimit: 200)
            results.append(contentsOf: matches.compactMap { try? $0.1.get() })
            while let c = cursor {
                (matches, cursor) = try await db.records(continuingMatchFrom: c, desiredKeys: keys, resultsLimit: 200)
                results.append(contentsOf: matches.compactMap { try? $0.1.get() })
            }
            return results
        }, count: { $0.count })
    }

    private func familyRef(_ zoneID: CKRecordZone.ID) -> CKRecord.Reference {
        CKRecord.Reference(recordID: CKRecord.ID(recordName: "family", zoneID: zoneID), action: .deleteSelf)
    }

    private func childRef(_ childId: String, _ zoneID: CKRecordZone.ID) -> CKRecord.Reference {
        CKRecord.Reference(recordID: CKRecord.ID(recordName: childId, zoneID: zoneID), action: .deleteSelf)
    }

    private static func family(from record: CKRecord, zoneName: String) -> Family {
        Family(id: zoneName,
               name: record["name"] as? String ?? "Vores familie",
               ownerId: record["ownerId"] as? String ?? "",
               memberIds: [record["ownerId"] as? String ?? ""])
    }

    private static func child(from record: CKRecord, familyId: String) -> Child {
        Child(id: record.recordID.recordName,
              familyId: familyId,
              name: record["name"] as? String ?? "",
              birthDate: record["birthDate"] as? Date,
              dueDate: record["dueDate"] as? Date,
              gender: Gender(rawValue: record["gender"] as? String ?? "") ?? .unspecified,
              photo: assetData(record["photo"]),
              thumb: assetData(record[thumbKey]),
              photoLoaded: assetsLoaded(record, keys: ["photo"]),
              linkedUserId: (record["linkedUserId"] as? String).flatMap { $0.isEmpty ? nil : $0 })
    }

    // CKAsset <-> Data
    // Billeder til upload skrives i en egen mappe og slettes, så snart recorden er gemt
    // (persist). Rester fra et afbrudt forsøg ryddes ved opstart.
    private static let uploadDir: URL = {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("CKUploads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static func asset(from data: Data) -> CKAsset? {
        let url = uploadDir.appendingPathComponent(UUID().uuidString + ".jpg")
        do {
            try data.write(to: url)
            return CKAsset(fileURL: url)
        } catch {
            return nil
        }
    }

    /// Kopiér en fil (video/lyd) til upload-mappen, så den ryddes op efter gem.
    private static func uploadAsset(copying source: URL) -> CKAsset? {
        let target = uploadDir.appendingPathComponent(UUID().uuidString + "." + source.pathExtension)
        do {
            try FileManager.default.copyItem(at: source, to: target)
            return CKAsset(fileURL: target)
        } catch {
            return nil
        }
    }

    /// Gem en record og slet bagefter de midlertidige billedfiler, den blev uploadet fra.
    private func persist(_ record: CKRecord, in db: CKDatabase) async throws -> CKRecord {
        defer { Self.removeUploadFiles(of: record) }
        Self.addThumb(to: record)
        let saved = try await SyncLog.measure("gem \(record.recordType)") { try await saveWithRetry(record, in: db) }
        // Billeder lægges i cachen med det samme (upload-filerne slettes lige om lidt).
        for key in saved.allKeys() where saved[key] is CKAsset || saved[key] is [CKAsset] {
            saved[key] = AssetCache.store(saved, key: key)
        }
        // … og recorden i den lokale kopi (uden filer), så den er med i næste liste.
        local.apply(changed: [saved], deleted: [], in: saved.recordID.zoneID, createIfMissing: false)
        return saved
    }

    private static func removeUploadFiles(of record: CKRecord) {
        let prefix = uploadDir.standardizedFileURL.path
        for key in record.allKeys() {
            let assets: [CKAsset]
            switch record[key] {
            case let one as CKAsset: assets = [one]
            case let many as [CKAsset]: assets = many
            default: continue
            }
            for url in assets.compactMap(\.fileURL) where url.standardizedFileURL.path.hasPrefix(prefix) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    /// Ryd rester fra tidligere (fx hvis appen blev lukket midt i en upload).
    private static func clearUploadDir() {
        let fm = FileManager.default
        for url in (try? fm.contentsOfDirectory(at: uploadDir, includingPropertiesForKeys: nil)) ?? [] {
            try? fm.removeItem(at: url)
        }
    }

    private static func assetData(_ value: Any?) -> Data? {
        guard let asset = value as? CKAsset, let url = asset.fileURL else { return nil }
        return try? Data(contentsOf: url)
    }

    private static func assetsData(_ value: Any?) -> [Data] {
        (value as? [CKAsset] ?? []).compactMap { $0.fileURL.flatMap { try? Data(contentsOf: $0) } }
    }
}

/// Holder øje med, om telefonen har netværk (Wi-Fi eller mobil). Bruges til at fejle hurtigt ved gem.
final class NetworkWatch: @unchecked Sendable {
    static let shared = NetworkWatch()
    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var online = true   // antag ja, indtil første opdatering

    var isOnline: Bool { lock.lock(); defer { lock.unlock() }; return online }

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lock.lock(); self.online = path.status == .satisfied; self.lock.unlock()
        }
        monitor.start(queue: DispatchQueue(label: "net.prehn.mindebog.network"))
    }
}
