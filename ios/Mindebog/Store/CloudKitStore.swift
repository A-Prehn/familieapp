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
// actor (ikke class): flere skærme indlæser samtidig, og zoneCache må ikke
// skrives fra to tråde på én gang.
actor CloudKitStore: Store {
    private let container: CKContainer
    private var privateDB: CKDatabase { container.privateCloudDatabase }
    private var sharedDB: CKDatabase { container.sharedCloudDatabase }

    // familyId == zoneName. Husker hvilken database zonen ligger i.
    private var zoneCache: [String: (db: CKDatabase, zone: CKRecordZone.ID)] = [:]
    private let nameKey = "mindebog.displayName"

    init(containerIdentifier: String = "iCloud.net.prehn.mindebog") {
        self.container = CKContainer(identifier: containerIdentifier)
        Self.clearUploadDir()   // ingen uploads kører endnu ved oprettelse
        Task.detached(priority: .background) { AssetCache.prune() }
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
        let saved = try await persist(record, in: privateDB)
        return Self.family(from: saved, zoneName: zoneName)
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

                var tags: [String] = []
                if p.role == .owner { tags.append("ejer") }
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
        let records = try await all(db: db, zoneID: zoneID, type: "Child",
                                    keys: ["familyRef", "name", "gender", "birthDate", "dueDate"], assetKeys: ["photo"])
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
        record["photo"] = child.photo.flatMap { Self.asset(from: $0) }
        let saved = try await persist(record, in: db)
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
        _ = try await persist(record, in: db)
    }

    // MARK: - Højdepunkter

    func highlights(childId: String) async throws -> [Highlight] {
        // Bevidst uden "video"/"audio" — de hentes først ved afspilning (highlightMedia).
        let records = try await childRecords(childId, type: "Highlight",
                                              keys: ["childRef", "date", "text", "videoDuration", "audioDuration"],
                                              assetKeys: ["photos"])
        return records.map { r in
            Highlight(id: r.recordID.recordName,
                      date: r["date"] as? Date,
                      text: r["text"] as? String ?? "",
                      photos: Self.assetsData(r["photos"]),
                      createdAt: r.creationDate ?? Date(),
                      videoDuration: r["videoDuration"] as? Double,
                      audioDuration: r["audioDuration"] as? Double)
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

    func addHighlight(childId: String, date: Date?, text: String, photos: [Data]) async throws -> Highlight {
        let (db, zoneID) = try await locateChild(childId)
        let record = CKRecord(recordType: "Highlight", recordID: CKRecord.ID(recordName: newId("hl"), zoneID: zoneID))
        record["childRef"] = childRef(childId, zoneID)
        if let date { record["date"] = date as CKRecordValue }
        record["text"] = text.trimmingCharacters(in: .whitespaces) as CKRecordValue
        let assets = photos.compactMap { Self.asset(from: $0) }
        if !assets.isEmpty { record["photos"] = assets as CKRecordValue }
        let saved = try await persist(record, in: db)
        return Highlight(id: saved.recordID.recordName, date: date, text: text, photos: photos, createdAt: Date())
    }

    func updateHighlight(childId: String, _ highlight: Highlight) async throws {
        let (db, zoneID) = try await locateChild(childId)
        let record = try await db.record(for: CKRecord.ID(recordName: highlight.id, zoneID: zoneID))
        record["date"] = highlight.date as CKRecordValue?
        record["text"] = highlight.text.trimmingCharacters(in: .whitespaces) as CKRecordValue
        let assets = highlight.photos.compactMap { Self.asset(from: $0) }
        record["photos"] = assets.isEmpty ? nil : assets as CKRecordValue
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
        let list = assetsData(record["photos"])
        if list.isEmpty { return PhotoSet(single: assetData(record["photo"])) }
        let captions = record["captions"] as? [String] ?? []
        let cover = (record["coverIndex"] as? Int64).map(Int.init) ?? 0
        return PhotoSet(photos: list, captions: captions, cover: cover)
    }

    private static func setPhotos(_ set: PhotoSet, on record: CKRecord) {
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
            try? await remove(recordID, in: db)
            return
        }
        let record = (try? await db.record(for: recordID)) ?? CKRecord(recordType: "Answer", recordID: recordID)
        record["childRef"] = childRef(childId, zoneID)
        record["question"] = question as CKRecordValue
        record["answer"] = trimmed as CKRecordValue
        _ = try await persist(record, in: db)
    }

    // MARK: - Dagbog

    func diary(childId: String) async throws -> [DiaryEntry] {
        let records = try await childRecords(childId, type: "Diary", keys: ["childRef", "date", "text"], assetKeys: ["photo"])
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
        let saved = try await persist(record, in: db)
        return DiaryEntry(id: saved.recordID.recordName, date: date, text: text, photo: photo, createdAt: Date())
    }

    func updateDiary(childId: String, _ entry: DiaryEntry) async throws {
        let (db, zoneID) = try await locateChild(childId)
        let record = try await db.record(for: CKRecord.ID(recordName: entry.id, zoneID: zoneID))
        record["date"] = entry.date as CKRecordValue?
        record["text"] = entry.text.trimmingCharacters(in: .whitespaces) as CKRecordValue
        record["photo"] = entry.photo.flatMap { Self.asset(from: $0) }
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
                                              keys: ["childRef", "kind", "caption", "note"], assetKeys: ["photo"],
                                              extraPredicate: NSPredicate(format: "kind == %@", kind.rawValue),
                                              extraMatch: { ($0["kind"] as? String) == kind.rawValue })
        return records
            .map { r in
                GalleryItem(id: r.recordID.recordName,
                            caption: r["caption"] as? String ?? "",
                            note: r["note"] as? String ?? "",
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
        let saved = try await persist(record, in: db)
        return GalleryItem(id: saved.recordID.recordName, caption: caption, photo: photo, createdAt: Date())
    }

    func updateGalleryItem(childId: String, _ item: GalleryItem) async throws {
        let (db, zoneID) = try await locateChild(childId)
        let record = try await db.record(for: CKRecord.ID(recordName: item.id, zoneID: zoneID))
        record["caption"] = item.caption.trimmingCharacters(in: .whitespaces) as CKRecordValue
        record["note"] = item.note.trimmingCharacters(in: .whitespacesAndNewlines) as CKRecordValue
        record["photo"] = item.photo.flatMap { Self.asset(from: $0) }
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

    func letters(childId: String) async throws -> [Letter] {
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
        record["photo"] = letter.photo.flatMap { asset(from: $0) }
    }

    // MARK: - Familie-indhold

    func events(familyId: String) async throws -> [FamilyEvent] {
        let (db, zoneID) = try await locate(familyId)
        return try await all(db: db, zoneID: zoneID, type: "Event",
                             keys: ["familyRef", "title", "date", "details", "placeName", "placeAddress", "location", "captions", "coverIndex"],
                             assetKeys: ["photo", "photos"]).map { r in
            FamilyEvent(id: r.recordID.recordName,
                        title: r["title"] as? String ?? "",
                        date: r["date"] as? Date,
                        details: r["details"] as? String ?? "",
                        photos: Self.photoSet(from: r),
                        place: Self.place(from: r))
        }.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    func addEvent(familyId: String, title: String, date: Date?, details: String,
                  photos: PhotoSet, place: Place?) async throws -> FamilyEvent {
        let (db, zoneID) = try await locate(familyId)
        let record = CKRecord(recordType: "Event", recordID: CKRecord.ID(recordName: newId("ev"), zoneID: zoneID))
        record["familyRef"] = familyRef(zoneID)
        record["title"] = title.trimmingCharacters(in: .whitespaces) as CKRecordValue
        if let date { record["date"] = date as CKRecordValue }
        record["details"] = details.trimmingCharacters(in: .whitespaces) as CKRecordValue
        Self.setPhotos(photos, on: record)
        Self.setPlace(place, on: record)
        let saved = try await persist(record, in: db)
        return FamilyEvent(id: saved.recordID.recordName, title: title, date: date, details: details,
                           photos: photos, place: place)
    }

    func vacations(familyId: String) async throws -> [Vacation] {
        let (db, zoneID) = try await locate(familyId)
        return try await all(db: db, zoneID: zoneID, type: "Vacation",
                             keys: ["familyRef", "title", "startDate", "endDate", "details", "placeName", "placeAddress", "location", "captions", "coverIndex"],
                             assetKeys: ["photo", "photos"]).map { r in
            Vacation(id: r.recordID.recordName,
                     title: r["title"] as? String ?? "",
                     startDate: r["startDate"] as? Date,
                     endDate: r["endDate"] as? Date,
                     details: r["details"] as? String ?? "",
                     photos: Self.photoSet(from: r),
                     place: Self.place(from: r))
        }.sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
    }

    func addVacation(familyId: String, title: String, start: Date?, end: Date?,
                     details: String, photos: PhotoSet, place: Place?) async throws -> Vacation {
        let (db, zoneID) = try await locate(familyId)
        let record = CKRecord(recordType: "Vacation", recordID: CKRecord.ID(recordName: newId("vac"), zoneID: zoneID))
        record["familyRef"] = familyRef(zoneID)
        record["title"] = title.trimmingCharacters(in: .whitespaces) as CKRecordValue
        if let start { record["startDate"] = start as CKRecordValue }
        if let end { record["endDate"] = end as CKRecordValue }
        record["details"] = details.trimmingCharacters(in: .whitespaces) as CKRecordValue
        Self.setPhotos(photos, on: record)
        Self.setPlace(place, on: record)
        let saved = try await persist(record, in: db)
        return Vacation(id: saved.recordID.recordName, title: title, startDate: start, endDate: end,
                        details: details, photos: photos, place: place)
    }

    func updateEvent(familyId: String, _ event: FamilyEvent) async throws -> FamilyEvent {
        let (db, zoneID) = try await locate(familyId)
        let record = try await db.record(for: CKRecord.ID(recordName: event.id, zoneID: zoneID))
        record["title"] = event.title.trimmingCharacters(in: .whitespaces) as CKRecordValue
        record["date"] = event.date as CKRecordValue?
        record["details"] = event.details.trimmingCharacters(in: .whitespaces) as CKRecordValue
        Self.setPhotos(event.photos, on: record)
        Self.setPlace(event.place, on: record)
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

        // De fire opslag kører samtidig.
        async let highlights = all(db: db, zoneID: zoneID, type: "Highlight", keys: ["childRef", "date", "text"])
        async let diary = all(db: db, zoneID: zoneID, type: "Diary", keys: ["childRef", "date", "text"])
        async let events = all(db: db, zoneID: zoneID, type: "Event", keys: ["title", "date"])
        async let vacations = all(db: db, zoneID: zoneID, type: "Vacation", keys: ["title", "startDate"])
        async let photos = all(db: db, zoneID: zoneID, type: "GalleryItem", keys: ["childRef", "kind", "caption", "note"])
        async let interviews = all(db: db, zoneID: zoneID, type: "Interview", keys: ["childRef", "question", "age", "date"])
        async let traditions = all(db: db, zoneID: zoneID, type: "Tradition", keys: ["title", "when"])
        async let letters = all(db: db, zoneID: zoneID, type: "Letter", keys: ["childRef", "title", "writtenAt", "openDate"])

        for r in try await highlights {
            out.append(MemorySummary(id: r.recordID.recordName, kind: .highlight, childId: childId(r),
                                     date: r["date"] as? Date, createdAt: r.creationDate ?? Date(),
                                     text: r["text"] as? String ?? "", modifiedAt: r.modificationDate ?? .distantPast))
        }
        for r in try await diary {
            out.append(MemorySummary(id: r.recordID.recordName, kind: .diary, childId: childId(r),
                                     date: r["date"] as? Date, createdAt: r.creationDate ?? Date(),
                                     text: r["text"] as? String ?? "", modifiedAt: r.modificationDate ?? .distantPast))
        }
        for r in try await events {
            out.append(MemorySummary(id: r.recordID.recordName, kind: .event, childId: nil,
                                     date: r["date"] as? Date, createdAt: r.creationDate ?? Date(),
                                     text: r["title"] as? String ?? "", modifiedAt: r.modificationDate ?? .distantPast))
        }
        for r in try await vacations {
            out.append(MemorySummary(id: r.recordID.recordName, kind: .vacation, childId: nil,
                                     date: r["startDate"] as? Date, createdAt: r.creationDate ?? Date(),
                                     text: r["title"] as? String ?? "", modifiedAt: r.modificationDate ?? .distantPast))
        }
        // De nyere typer: kun til "Seneste i familien" — en fejl her må ikke tømme forsiden.
        for r in (try? await photos) ?? [] {
            let caption = r["caption"] as? String ?? ""
            let note = r["note"] as? String ?? ""
            out.append(MemorySummary(id: r.recordID.recordName, kind: .photo, childId: childId(r),
                                     date: r.creationDate, createdAt: r.creationDate ?? Date(),
                                     text: [caption, note].filter { !$0.isEmpty }.joined(separator: " · "),
                                     modifiedAt: r.modificationDate ?? .distantPast,
                                     detail: r["kind"] as? String ?? ""))
        }
        for r in (try? await interviews) ?? [] {
            let age = Int(r["age"] as? Int64 ?? 0)
            out.append(MemorySummary(id: r.recordID.recordName, kind: .interview, childId: childId(r),
                                     date: r["date"] as? Date, createdAt: r.creationDate ?? Date(),
                                     text: "\(age == 1 ? "1 år" : "\(age) år"): \(Constants.interviewQuestion(r["question"] as? String ?? ""))",
                                     modifiedAt: r.modificationDate ?? .distantPast))
        }
        for r in (try? await traditions) ?? [] {
            out.append(MemorySummary(id: r.recordID.recordName, kind: .tradition, childId: nil,
                                     date: nil, createdAt: r.creationDate ?? Date(),
                                     text: r["title"] as? String ?? "", modifiedAt: r.modificationDate ?? .distantPast))
        }
        for r in (try? await letters) ?? [] {
            let title = r["title"] as? String ?? ""
            let sealed = (r["openDate"] as? Date).map { $0 > Date() } ?? false
            out.append(MemorySummary(id: r.recordID.recordName, kind: .letter, childId: childId(r),
                                     date: r["writtenAt"] as? Date, createdAt: r.creationDate ?? Date(),
                                     text: (title.isEmpty ? "Et brev" : title) + (sealed ? " (forseglet)" : ""),
                                     modifiedAt: r.modificationDate ?? .distantPast))
        }
        return out
    }

    /// Henter kun billedfelterne for ét minde og returnerer forsidebilledet.
    func coverPhoto(familyId: String, memory: MemorySummary) async throws -> Data? {
        let (db, zoneID) = try await locate(familyId)
        let id = CKRecord.ID(recordName: memory.id, zoneID: zoneID)
        let keys: [CKRecord.FieldKey]
        switch memory.kind {
        case .highlight: keys = ["photos"]
        case .diary, .photo: keys = ["photo"]
        case .event, .vacation, .tradition: keys = ["photos", "photo", "coverIndex"]
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
            case .event, .vacation, .tradition: return Self.photoSet(from: record).coverPhoto
            case .interview: return nil
            }
        }
        // Fra billedcachen, hvis mindet ikke er ændret, siden forsiden sidst blev hentet.
        if memory.modifiedAt > .distantPast {
            let cached = CKRecord(recordType: "cover", recordID: id)
            var complete = true
            for k in keys {
                if let v = AssetCache.read(id: id, modified: memory.modifiedAt, key: k) { cached[k] = v } else { complete = false; break }
            }
            if complete { return cover(cached) }
        }
        let results = try await db.records(for: [id], desiredKeys: keys)
        guard let record = try results[id]?.get() else { return nil }
        for k in keys { record[k] = AssetCache.store(record, key: k) }
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
        record["photo"] = person.photo.flatMap { Self.asset(from: $0) }
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

    /// Udfylder asset-felterne på records hentet uden assets: fra cachen, ellers fra iCloud i bundter.
    private func fillAssets(_ records: [CKRecord], keys: [String], db: CKDatabase) async -> [CKRecord] {
        guard !keys.isEmpty, !records.isEmpty else { return records }
        var missing: [CKRecord] = []
        for r in records {
            var complete = true
            for k in keys {
                if let cached = AssetCache.read(r, key: k) { r[k] = cached } else { complete = false }
            }
            if !complete { missing.append(r) }
        }
        var i = 0
        while i < missing.count {
            let chunk = Array(missing[i..<min(i + 20, missing.count)])
            i += 20
            guard let fetched = try? await db.records(for: chunk.map(\.recordID), desiredKeys: keys) else { continue }
            for r in chunk {
                guard let full = try? fetched[r.recordID]?.get() else { continue }
                for k in keys { r[k] = AssetCache.store(full, key: k) }
            }
        }
        return records
    }
    // MARK: - Nyligt gemt/slettet
    // iCloud finder først nye poster i søgninger nogle sekunder efter, de er gemt (og viser
    // slettede lidt endnu). Derfor husker appen selv det, den lige har gemt eller slettet,
    // i to minutter og lægger det oven i søgeresultaterne — så lister er rigtige med det samme.
    private let recentLock = NSLock()
    private var recentSaves: [CKRecord.ID: (record: CKRecord, at: Date)] = [:]
    private var recentDeletes: [CKRecord.ID: Date] = [:]
    private static let recentWindow: TimeInterval = 120

    private func noteSaved(_ record: CKRecord) {
        recentLock.lock(); defer { recentLock.unlock() }
        recentSaves[record.recordID] = (record, Date())
        recentDeletes[record.recordID] = nil
    }

    private func noteDeleted(_ id: CKRecord.ID) {
        recentLock.lock(); defer { recentLock.unlock() }
        recentDeletes[id] = Date()
        recentSaves[id] = nil
    }

    /// Gemmer én record. Store filer (video) kan tage minutter at uploade, så ventetiden er
    /// sat op (iCloud giver ellers op efter ca. et minut og melder "netværksfejl"), og
    /// midlertidige fejl prøves igen op til tre gange — med den ventetid, iCloud selv beder om.
    private func saveWithRetry(_ record: CKRecord, in db: CKDatabase) async throws -> CKRecord {
        var attempt = 0
        while true {
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
            op.perRecordSaveBlock = { _, result in
                if case .success(let r) = result { saved = r }
            }
            op.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    if let saved { continuation.resume(returning: saved) }
                    else { continuation.resume(throwing: CKError(.internalError)) }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            db.add(op)
        }
    }

    /// Sletter en record og husker det, så den ikke dukker op igen i næste søgning.
    private func remove(_ id: CKRecord.ID, in db: CKDatabase) async throws {
        _ = try await db.deleteRecord(withID: id)
        noteDeleted(id)
    }

    /// Lægger nyligt gemte records oven i et søgeresultat og fjerner nyligt slettede.
    private func merged(_ results: [CKRecord], type: String, zoneID: CKRecordZone.ID,
                        matching: (CKRecord) -> Bool = { _ in true }) -> [CKRecord] {
        recentLock.lock(); defer { recentLock.unlock() }
        let cutoff = Date().addingTimeInterval(-Self.recentWindow)
        recentSaves = recentSaves.filter { $0.value.at > cutoff }
        recentDeletes = recentDeletes.filter { $0.value > cutoff }
        guard !recentSaves.isEmpty || !recentDeletes.isEmpty else { return results }
        var out = results.filter { recentDeletes[$0.recordID] == nil }
        var seen = Set(out.map(\.recordID))
        for (id, entry) in recentSaves
        where entry.record.recordType == type && id.zoneID == zoneID && matching(entry.record) {
            if let i = out.firstIndex(where: { $0.recordID == id }) {
                // Søgningen kan give en ældre version end den, vi lige gemte.
                if (out[i].modificationDate ?? .distantPast) < (entry.record.modificationDate ?? .distantFuture) {
                    out[i] = entry.record
                }
            } else if !seen.contains(id) {
                out.append(entry.record)
                seen.insert(id)
            }
        }
        return out
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

    private func shareTitle(_ familyName: String?) -> String {
        let name = (familyName ?? "").trimmingCharacters(in: .whitespaces)
        return name.isEmpty || name == "Vores familie" ? "Vores familie" : "Vores familie · \(name)"
    }

    // MARK: - Adgang (deltagere i delingen)

    /// Alle i den delte familie med deres adgang — til "Familie og adgang".
    func participants(familyId: String) async throws -> [FamilyParticipant] {
        let (db, zoneID) = try await locate(familyId)
        guard let share = try? await fetchShare(db: db, zoneID: zoneID) else { return [] }
        let me = share.currentUserParticipant
        let myId = UserDefaults.standard.string(forKey: "mindebog.userId")
        let myName = UserDefaults.standard.string(forKey: nameKey)
        var savedNames: [String: String] = [:]
        for r in (try? await all(db: db, zoneID: zoneID, type: "Member")) ?? [] {
            if let uid = r["userId"] as? String, let n = r["name"] as? String, !n.isEmpty { savedNames[uid] = n }
        }
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
            return FamilyParticipant(id: Self.participantKey(p), name: name, contact: contact == name ? "" : contact,
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
            guard let p = share.participants.first(where: { Self.participantKey($0) == id }), p.role != .owner else { return }
            p.permission = readOnly ? .readOnly : .readWrite
        }
    }

    func removeParticipant(familyId: String, id: String) async throws {
        try await changeShare(familyId: familyId) { share in
            guard let p = share.participants.first(where: { Self.participantKey($0) == id }), p.role != .owner else { return }
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

    private static func participantKey(_ p: CKShare.Participant) -> String {
        let identity = p.userIdentity
        return identity.userRecordID?.recordName
            ?? identity.lookupInfo?.emailAddress
            ?? identity.lookupInfo?.phoneNumber
            ?? "\(p.hashValue)"
    }

    private func fetchShare(db: CKDatabase, zoneID: CKRecordZone.ID) async throws -> CKShare {
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        guard let share = try await db.record(for: shareID) as? CKShare else { throw StoreError.notFound }
        return share
    }

    /// Alle records af en type i zonen. `keys` begrænser felterne (fx uden billeder), nil = alle.
    /// `assetKeys`: billedfelter, der tages fra cachen (så `keys` skal være felterne UDEN billeder).
    private func all(db: CKDatabase, zoneID: CKRecordZone.ID, type: String,
                     keys: [CKRecord.FieldKey]? = nil, assetKeys: [String] = [],
                     predicate: NSPredicate = NSPredicate(value: true)) async throws -> [CKRecord] {
        let query = CKQuery(recordType: type, predicate: predicate)
        var results: [CKRecord] = []
        var (matches, cursor) = try await db.records(matching: query, inZoneWith: zoneID,
                                                     desiredKeys: keys, resultsLimit: 200)
        results.append(contentsOf: matches.compactMap { try? $0.1.get() })
        while let c = cursor {
            (matches, cursor) = try await db.records(continuingMatchFrom: c, desiredKeys: keys, resultsLimit: 200)
            results.append(contentsOf: matches.compactMap { try? $0.1.get() })
        }
        return await fillAssets(merged(results, type: type, zoneID: zoneID), keys: assetKeys, db: db)
    }

    /// Et barns records af en type. `keys` begrænser felterne (fx uden video), nil = alle.
    private func childRecords(_ childId: String, type: String,
                              keys: [CKRecord.FieldKey]? = nil, assetKeys: [String] = [],
                              extraPredicate: NSPredicate? = nil,
                              extraMatch: ((CKRecord) -> Bool)? = nil) async throws -> [CKRecord] {
        let (db, zoneID) = try await locateChild(childId)
        let ref = childRef(childId, zoneID)
        var predicate = NSPredicate(format: "childRef == %@", ref)
        if let extra = extraPredicate { predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [predicate, extra]) }
        let query = CKQuery(recordType: type, predicate: predicate)
        var results: [CKRecord] = []
        var (matches, cursor) = try await db.records(matching: query, inZoneWith: zoneID,
                                                     desiredKeys: keys, resultsLimit: 200)
        results.append(contentsOf: matches.compactMap { try? $0.1.get() })
        while let c = cursor {
            (matches, cursor) = try await db.records(continuingMatchFrom: c, desiredKeys: keys, resultsLimit: 200)
            results.append(contentsOf: matches.compactMap { try? $0.1.get() })
        }
        let matched = merged(results, type: type, zoneID: zoneID) { r in
            (r["childRef"] as? CKRecord.Reference)?.recordID == ref.recordID && (extraMatch?(r) ?? true)
        }
        return await fillAssets(matched, keys: assetKeys, db: db)
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
              photo: assetData(record["photo"]))
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
        let saved = try await saveWithRetry(record, in: db)
        // Billeder lægges i cachen med det samme (upload-filerne slettes lige om lidt).
        for key in saved.allKeys() where saved[key] is CKAsset || saved[key] is [CKAsset] {
            saved[key] = AssetCache.store(saved, key: key)
        }
        noteSaved(saved)
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
