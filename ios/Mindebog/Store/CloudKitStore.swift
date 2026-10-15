import Foundation
import CloudKit
import CoreLocation

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
final class CloudKitStore: Store {
    private let container: CKContainer
    private var privateDB: CKDatabase { container.privateCloudDatabase }
    private var sharedDB: CKDatabase { container.sharedCloudDatabase }

    // familyId == zoneName. Husker hvilken database zonen ligger i.
    private var zoneCache: [String: (db: CKDatabase, zone: CKRecordZone.ID)] = [:]
    private let nameKey = "mindebog.displayName"

    init(containerIdentifier: String = "iCloud.net.prehn.mindebog") {
        self.container = CKContainer(identifier: containerIdentifier)
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
        var result: [Family] = []
        for db in [privateDB, sharedDB] {
            let zones = try await db.allRecordZones()
            for zone in zones where zone.zoneID.zoneName.hasPrefix("family_") {
                let query = CKQuery(recordType: "Family", predicate: NSPredicate(value: true))
                let (matches, _) = try await db.records(matching: query, inZoneWith: zone.zoneID, resultsLimit: 1)
                if let record = matches.compactMap({ try? $0.1.get() }).first {
                    remember(zone.zoneID, in: db)
                    result.append(Self.family(from: record, zoneName: zone.zoneID.zoneName))
                }
            }
        }
        return result
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
        let saved = try await privateDB.save(record)
        return Self.family(from: saved, zoneName: zoneName)
    }

    func members(familyId: String) async throws -> [AppUser] {
        let (db, zoneID) = try await locate(familyId)
        var members: [AppUser] = []
        if let share = try? await fetchShare(db: db, zoneID: zoneID) {
            for p in share.participants {
                let name = p.userIdentity.nameComponents.map {
                    PersonNameComponentsFormatter.localizedString(from: $0, style: .default)
                } ?? "Deltager"
                let id = p.userIdentity.userRecordID?.recordName ?? UUID().uuidString
                members.append(AppUser(id: id, name: name.isEmpty ? "Deltager" : name))
            }
        }
        if members.isEmpty {
            let family = try await familyRecord(db: db, zoneID: zoneID)
            members.append(AppUser(id: family["ownerId"] as? String ?? "owner",
                                   name: family["ownerName"] as? String ?? "Forælder"))
        }
        return members
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
    func shareForSharing(familyId: String) async throws -> (CKShare, CKContainer) {
        let (db, zoneID) = try await locate(familyId)
        if let existing = try? await fetchShare(db: db, zoneID: zoneID) {
            return (existing, container)
        }
        let share = CKShare(recordZoneID: zoneID)
        share[CKShare.SystemFieldKey.title] = "Vores familie" as CKRecordValue
        share.publicPermission = .none
        let (saveResults, _) = try await db.modifyRecords(saving: [share], deleting: [])
        guard let saved = try saveResults[share.recordID]?.get() as? CKShare else { throw StoreError.notFound }
        return (saved, container)
    }

    /// Tager en share-URL og tilslutter brugeren til familien.
    func acceptInvite(userId: String, code: String) async throws -> Family {
        guard let url = URL(string: code.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw StoreError.invalidInvite
        }
        let metadata = try await container.shareMetadata(for: url)
        _ = try await container.accept(metadata)
        let zoneID = metadata.share.recordID.zoneID
        remember(zoneID, in: sharedDB)
        let record = try await familyRecord(db: sharedDB, zoneID: zoneID)
        return Self.family(from: record, zoneName: zoneID.zoneName)
    }

    // MARK: - Børn

    func children(familyId: String) async throws -> [Child] {
        let (db, zoneID) = try await locate(familyId)
        let records = try await all(db: db, zoneID: zoneID, type: "Child")
        let kids = records.map { Self.child(from: $0, familyId: familyId) }
            .sorted { $0.name < $1.name }
        for kid in kids { rememberChild(kid.id, zoneName: familyId) }
        return kids
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
        let saved = try await db.save(record)
        let child = Self.child(from: saved, familyId: familyId)
        rememberChild(child.id, zoneName: familyId)
        if let birthDate { try await setMilestone(childId: child.id, key: "birth_date", value: Fmt.iso(birthDate), photo: nil) }
        if let dueDate { try await setMilestone(childId: child.id, key: "due_date", value: Fmt.iso(dueDate), photo: nil) }
        return child
    }

    func updateChild(_ child: Child) async throws -> Child {
        let (db, zoneID) = try await locateChild(child.id)
        let record = try await db.record(for: CKRecord.ID(recordName: child.id, zoneID: zoneID))
        record["name"] = child.name.trimmingCharacters(in: .whitespaces) as CKRecordValue
        record["gender"] = child.gender.rawValue as CKRecordValue
        record["birthDate"] = child.birthDate as CKRecordValue?
        record["dueDate"] = child.dueDate as CKRecordValue?
        let saved = try await db.save(record)
        // Fødsels-/terminsdato ligger også i milepælene (som på websitet).
        if let birth = child.birthDate {
            try await setMilestoneValue(childId: child.id, key: "birth_date", value: Fmt.iso(birth), db: db, zoneID: zoneID)
        }
        if let due = child.dueDate {
            try await setMilestoneValue(childId: child.id, key: "due_date", value: Fmt.iso(due), db: db, zoneID: zoneID)
        }
        return Self.child(from: saved, familyId: child.familyId)
    }

    /// Opdaterer kun milepælens værdi — et evt. billede på milepælen bevares.
    private func setMilestoneValue(childId: String, key: String, value: String,
                                   db: CKDatabase, zoneID: CKRecordZone.ID) async throws {
        let recordID = CKRecord.ID(recordName: "ms_\(childId)_\(key)", zoneID: zoneID)
        let record = (try? await db.record(for: recordID)) ?? CKRecord(recordType: "Milestone", recordID: recordID)
        record["childRef"] = childRef(childId, zoneID)
        record["key"] = key as CKRecordValue
        record["value"] = value as CKRecordValue
        _ = try await db.save(record)
    }

    // MARK: - Højdepunkter

    func highlights(childId: String) async throws -> [Highlight] {
        let records = try await childRecords(childId, type: "Highlight")
        return records.map { r in
            Highlight(id: r.recordID.recordName,
                      date: r["date"] as? Date,
                      text: r["text"] as? String ?? "",
                      photos: Self.assetsData(r["photos"]),
                      createdAt: r.creationDate ?? Date())
        }.sorted { ($0.date ?? $0.createdAt) > ($1.date ?? $1.createdAt) }
    }

    func addHighlight(childId: String, date: Date?, text: String, photos: [Data]) async throws -> Highlight {
        let (db, zoneID) = try await locateChild(childId)
        let record = CKRecord(recordType: "Highlight", recordID: CKRecord.ID(recordName: newId("hl"), zoneID: zoneID))
        record["childRef"] = childRef(childId, zoneID)
        if let date { record["date"] = date as CKRecordValue }
        record["text"] = text.trimmingCharacters(in: .whitespaces) as CKRecordValue
        let assets = photos.compactMap { Self.asset(from: $0) }
        if !assets.isEmpty { record["photos"] = assets as CKRecordValue }
        let saved = try await db.save(record)
        return Highlight(id: saved.recordID.recordName, date: date, text: text, photos: photos, createdAt: Date())
    }

    // MARK: - Milepæle

    func milestones(childId: String) async throws -> [String: MilestoneEntry] {
        let records = try await childRecords(childId, type: "Milestone")
        var result: [String: MilestoneEntry] = [:]
        for r in records {
            guard let key = r["key"] as? String else { continue }
            result[key] = MilestoneEntry(value: r["value"] as? String, photo: Self.assetData(r["photo"]))
        }
        return result
    }

    func setMilestone(childId: String, key: String, value: String?, photo: Data?) async throws {
        let (db, zoneID) = try await locateChild(childId)
        let recordID = CKRecord.ID(recordName: "ms_\(childId)_\(key)", zoneID: zoneID)
        let cleanValue = value?.trimmingCharacters(in: .whitespaces)
        if (cleanValue?.isEmpty ?? true) && photo == nil {
            _ = try? await db.deleteRecord(withID: recordID)
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
        if let photo, let asset = Self.asset(from: photo) {
            record["photo"] = asset
        } else {
            record["photo"] = nil
        }
        _ = try await db.save(record)
    }

    // MARK: - Om dig

    func answers(childId: String) async throws -> [String: String] {
        let records = try await childRecords(childId, type: "Answer")
        var result: [String: String] = [:]
        for r in records {
            if let q = r["question"] as? String, let a = r["answer"] as? String { result[q] = a }
        }
        return result
    }

    func setAnswer(childId: String, question: String, answer: String) async throws {
        let (db, zoneID) = try await locateChild(childId)
        let hash = String(question.hashValue, radix: 36).replacingOccurrences(of: "-", with: "n")
        let recordID = CKRecord.ID(recordName: "ans_\(childId)_\(hash)", zoneID: zoneID)
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            _ = try? await db.deleteRecord(withID: recordID)
            return
        }
        let record = (try? await db.record(for: recordID)) ?? CKRecord(recordType: "Answer", recordID: recordID)
        record["childRef"] = childRef(childId, zoneID)
        record["question"] = question as CKRecordValue
        record["answer"] = trimmed as CKRecordValue
        _ = try await db.save(record)
    }

    // MARK: - Dagbog

    func diary(childId: String) async throws -> [DiaryEntry] {
        let records = try await childRecords(childId, type: "Diary")
        return records.map { r in
            DiaryEntry(id: r.recordID.recordName,
                       date: r["date"] as? Date,
                       text: r["text"] as? String ?? "",
                       photo: Self.assetData(r["photo"]),
                       createdAt: r.creationDate ?? Date())
        }.sorted { ($0.date ?? $0.createdAt) > ($1.date ?? $1.createdAt) }
    }

    func addDiary(childId: String, date: Date?, text: String, photo: Data?) async throws -> DiaryEntry {
        let (db, zoneID) = try await locateChild(childId)
        let record = CKRecord(recordType: "Diary", recordID: CKRecord.ID(recordName: newId("diary"), zoneID: zoneID))
        record["childRef"] = childRef(childId, zoneID)
        if let date { record["date"] = date as CKRecordValue }
        record["text"] = text.trimmingCharacters(in: .whitespaces) as CKRecordValue
        record["photo"] = photo.flatMap { Self.asset(from: $0) }
        let saved = try await db.save(record)
        return DiaryEntry(id: saved.recordID.recordName, date: date, text: text, photo: photo, createdAt: Date())
    }

    // MARK: - Gallerier

    func gallery(childId: String, kind: GalleryKind) async throws -> [GalleryItem] {
        let records = try await childRecords(childId, type: "GalleryItem")
        return records
            .filter { ($0["kind"] as? String) == kind.rawValue }
            .map { r in
                GalleryItem(id: r.recordID.recordName,
                            caption: r["caption"] as? String ?? "",
                            photo: Self.assetData(r["photo"]),
                            createdAt: r.creationDate ?? Date())
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
        let saved = try await db.save(record)
        return GalleryItem(id: saved.recordID.recordName, caption: caption, photo: photo, createdAt: Date())
    }

    // MARK: - Familie-indhold

    func events(familyId: String) async throws -> [FamilyEvent] {
        let (db, zoneID) = try await locate(familyId)
        return try await all(db: db, zoneID: zoneID, type: "Event").map { r in
            FamilyEvent(id: r.recordID.recordName,
                        title: r["title"] as? String ?? "",
                        date: r["date"] as? Date,
                        details: r["details"] as? String ?? "",
                        photo: Self.assetData(r["photo"]),
                        place: Self.place(from: r))
        }.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    func addEvent(familyId: String, title: String, date: Date?, details: String,
                  photo: Data?, place: Place?) async throws -> FamilyEvent {
        let (db, zoneID) = try await locate(familyId)
        let record = CKRecord(recordType: "Event", recordID: CKRecord.ID(recordName: newId("ev"), zoneID: zoneID))
        record["familyRef"] = familyRef(zoneID)
        record["title"] = title.trimmingCharacters(in: .whitespaces) as CKRecordValue
        if let date { record["date"] = date as CKRecordValue }
        record["details"] = details.trimmingCharacters(in: .whitespaces) as CKRecordValue
        record["photo"] = photo.flatMap { Self.asset(from: $0) }
        Self.setPlace(place, on: record)
        let saved = try await db.save(record)
        return FamilyEvent(id: saved.recordID.recordName, title: title, date: date, details: details,
                           photo: photo, place: place)
    }

    func vacations(familyId: String) async throws -> [Vacation] {
        let (db, zoneID) = try await locate(familyId)
        return try await all(db: db, zoneID: zoneID, type: "Vacation").map { r in
            Vacation(id: r.recordID.recordName,
                     title: r["title"] as? String ?? "",
                     startDate: r["startDate"] as? Date,
                     endDate: r["endDate"] as? Date,
                     details: r["details"] as? String ?? "",
                     photo: Self.assetData(r["photo"]),
                     place: Self.place(from: r))
        }.sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
    }

    func addVacation(familyId: String, title: String, start: Date?, end: Date?,
                     details: String, photo: Data?, place: Place?) async throws -> Vacation {
        let (db, zoneID) = try await locate(familyId)
        let record = CKRecord(recordType: "Vacation", recordID: CKRecord.ID(recordName: newId("vac"), zoneID: zoneID))
        record["familyRef"] = familyRef(zoneID)
        record["title"] = title.trimmingCharacters(in: .whitespaces) as CKRecordValue
        if let start { record["startDate"] = start as CKRecordValue }
        if let end { record["endDate"] = end as CKRecordValue }
        record["details"] = details.trimmingCharacters(in: .whitespaces) as CKRecordValue
        record["photo"] = photo.flatMap { Self.asset(from: $0) }
        Self.setPlace(place, on: record)
        let saved = try await db.save(record)
        return Vacation(id: saved.recordID.recordName, title: title, startDate: start, endDate: end,
                        details: details, photo: photo, place: place)
    }

    // Sted: navn + adresse som tekst, koordinat som CloudKit LOCATION.
    private static func setPlace(_ place: Place?, on record: CKRecord) {
        guard let place else { return }
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
        let saved = try await db.save(record)
        return CustomBirthday(id: saved.recordID.recordName, name: name, date: date, emoji: trimmedEmoji.isEmpty ? "🎂" : trimmedEmoji)
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
        for (_, entry) in zoneCache {
            let id = CKRecord.ID(recordName: childId, zoneID: entry.zone)
            if (try? await entry.db.record(for: id)) != nil {
                rememberChild(childId, zoneName: entry.zone.zoneName)
                return (entry.db, entry.zone)
            }
        }
        throw StoreError.notFound
    }

    private func familyRecord(db: CKDatabase, zoneID: CKRecordZone.ID) async throws -> CKRecord {
        try await db.record(for: CKRecord.ID(recordName: "family", zoneID: zoneID))
    }

    private func fetchShare(db: CKDatabase, zoneID: CKRecordZone.ID) async throws -> CKShare {
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        guard let share = try await db.record(for: shareID) as? CKShare else { throw StoreError.notFound }
        return share
    }

    private func all(db: CKDatabase, zoneID: CKRecordZone.ID, type: String) async throws -> [CKRecord] {
        let query = CKQuery(recordType: type, predicate: NSPredicate(value: true))
        var results: [CKRecord] = []
        var (matches, cursor) = try await db.records(matching: query, inZoneWith: zoneID, resultsLimit: 200)
        results.append(contentsOf: matches.compactMap { try? $0.1.get() })
        while let c = cursor {
            (matches, cursor) = try await db.records(continuingMatchFrom: c, resultsLimit: 200)
            results.append(contentsOf: matches.compactMap { try? $0.1.get() })
        }
        return results
    }

    private func childRecords(_ childId: String, type: String) async throws -> [CKRecord] {
        let (db, zoneID) = try await locateChild(childId)
        let ref = childRef(childId, zoneID)
        let query = CKQuery(recordType: type, predicate: NSPredicate(format: "childRef == %@", ref))
        var results: [CKRecord] = []
        var (matches, cursor) = try await db.records(matching: query, inZoneWith: zoneID, resultsLimit: 200)
        results.append(contentsOf: matches.compactMap { try? $0.1.get() })
        while let c = cursor {
            (matches, cursor) = try await db.records(continuingMatchFrom: c, resultsLimit: 200)
            results.append(contentsOf: matches.compactMap { try? $0.1.get() })
        }
        return results
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
              gender: Gender(rawValue: record["gender"] as? String ?? "") ?? .unspecified)
    }

    // CKAsset <-> Data
    private static func asset(from data: Data) -> CKAsset? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        do {
            try data.write(to: url)
            return CKAsset(fileURL: url)
        } catch {
            return nil
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
