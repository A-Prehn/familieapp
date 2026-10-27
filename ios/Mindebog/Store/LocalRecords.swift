import CloudKit
import Foundation

// Den lokale kopi af familien (#62): alle records pr. iCloud-zone, uden billeder/video/lyd
// (de ligger i AssetCache og hentes efter behov). Skærmene læser herfra og er øjeblikkelige;
// SyncEngine holder kopien opdateret med "hvad er ændret siden sidst" fra iCloud.
//
// Regler (se #62): kopien er kun en cache — iCloud er sandheden, og alt her kan smides væk og
// bygges igen. Kopien sletter aldrig noget i iCloud; den anvender kun sletninger, iCloud melder.
final class LocalRecords: @unchecked Sendable {
    /// Felter, der er filer (billeder, video, lyd). De gemmes ikke i kopien.
    static let assetKeys: Set<String> = ["photo", "photos", "video", "audio"]

    /// Alle øvrige felter i skemaet (CloudKit/schema.ckdb). Kun disse hentes ved sync.
    static let fieldKeys: [CKRecord.FieldKey] = [
        "age", "answer", "audioDuration", "author", "authorId", "authorName", "birthDate", "caption", "captions",
        "category", "childId", "childIds", "childRef", "coverIndex", "date", "deathDate", "details", "dueDate",
        "emoji", "endDate", "familyRef", "fromWhom", "gender", "headCm", "heightCm", "ingredients", "key", "kind",
        "linkedUserId", "location", "method", "name", "note", "openDate", "ownZone", "ownerId", "ownerName",
        "parentIds", "partnerIds", "personIds", "placeAddress", "placeName", "premiumUntil", "question", "role",
        "servings", "shareURL", "startDate", "story", "targetId", "text", "title", "userId", "value",
        "videoDuration", "weightGrams", "when", "writtenAt",
    ]

    private let lock = NSLock()
    private var zones: [CKRecordZone.ID: [CKRecord.ID: CKRecord]] = [:]
    /// Zoner, der er hentet mindst én gang (også hvis de er tomme). Først da må skærmene stole på kopien.
    private var loaded: Set<CKRecordZone.ID> = []
    private var knownOnDisk: Set<CKRecordZone.ID>?
    private let directory: URL

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.directory = base.appendingPathComponent("LocalRecords", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        // Kopien er en cache: iOS må ikke lægge den i iCloud-backup.
        var url = self.directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    // MARK: Læs

    /// Findes der en kopi af zonen (hentet mindst én gang)?
    func hasSnapshot(_ zone: CKRecordZone.ID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if loaded.contains(zone) { return true }
        return fileExists(zone)
    }

    /// Alle zoner med en kopi på disken eller i hukommelsen.
    func snapshotZones() -> [CKRecordZone.ID] {
        lock.lock(); defer { lock.unlock() }
        var out = Set(loaded)
        for zone in zonesOnDisk() { out.insert(zone) }
        return Array(out)
    }

    func records(in zone: CKRecordZone.ID, type: String? = nil) -> [CKRecord] {
        lock.lock(); defer { lock.unlock() }
        let all = load(zone).values
        guard let type else { return Array(all) }
        return all.filter { $0.recordType == type }
    }

    func record(_ id: CKRecord.ID) -> CKRecord? {
        lock.lock(); defer { lock.unlock() }
        return load(id.zoneID)[id]
    }

    // MARK: Skriv (fra sync og fra egne gem)

    /// Anvender ændringer fra iCloud — eller et gem, vi selv lige har lavet. Filer fjernes fra kopien.
    /// `createIfMissing`: kun sync må oprette en zone-kopi; et enkelt gem i en zone uden kopi ignoreres
    /// (ellers ville kopien se "komplet" ud med én record i).
    func apply(changed: [CKRecord], deleted: [CKRecord.ID], in zone: CKRecordZone.ID, createIfMissing: Bool = true) {
        lock.lock(); defer { lock.unlock() }
        if !createIfMissing, !loaded.contains(zone), !fileExists(zone) { return }
        var map = load(zone)
        for id in deleted { map[id] = nil }
        for record in changed { map[record.recordID] = Self.stripped(record) }
        zones[zone] = map
        loaded.insert(zone)
        save(zone)
    }

    /// Markér zonen som hentet (fx en tom zone), så skærmene ikke venter på iCloud igen.
    func markLoaded(_ zone: CKRecordZone.ID) {
        lock.lock(); defer { lock.unlock() }
        if zones[zone] == nil { zones[zone] = [:] }
        loaded.insert(zone)
        save(zone)
    }

    /// Smid kopien af zonen væk (zonen er slettet i iCloud, delingen fjernet, eller tokenet er forældet).
    func purge(_ zone: CKRecordZone.ID) {
        lock.lock(); defer { lock.unlock() }
        zones[zone] = nil
        loaded.remove(zone)
        try? FileManager.default.removeItem(at: url(zone))
        knownOnDisk?.remove(zone)
    }

    /// Smid kopien af alle zoner med dette navn væk (ejer ukendt, fx efter sletning af en familie).
    func purge(named zoneName: String) {
        for zone in snapshotZones() where zone.zoneName == zoneName { purge(zone) }
    }

    /// Smid alt væk ("Hent alt igen").
    func purgeAll() {
        lock.lock(); defer { lock.unlock() }
        zones.removeAll()
        loaded.removeAll()
        knownOnDisk = nil
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// En kopi af recorden uden filfelter.
    static func stripped(_ record: CKRecord) -> CKRecord {
        guard record.allKeys().contains(where: { assetKeys.contains($0) }) else { return record }
        let copy = record.copy() as! CKRecord
        for key in copy.allKeys() where assetKeys.contains(key) { copy[key] = nil }
        return copy
    }

    // MARK: Disk — én fil pr. zone (NSKeyedArchiver af [CKRecord])

    private func url(_ zone: CKRecordZone.ID) -> URL {
        let safe = "\(zone.zoneName)__\(zone.ownerName)".replacingOccurrences(of: "/", with: "_")
        return directory.appendingPathComponent(safe + ".records")
    }

    private func fileExists(_ zone: CKRecordZone.ID) -> Bool {
        FileManager.default.fileExists(atPath: url(zone).path)
    }

    private func zonesOnDisk() -> Set<CKRecordZone.ID> {
        if let knownOnDisk { return knownOnDisk }
        var out: Set<CKRecordZone.ID> = []
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for f in files where f.pathExtension == "records" {
            let parts = f.deletingPathExtension().lastPathComponent.components(separatedBy: "__")
            guard parts.count == 2 else { continue }
            out.insert(CKRecordZone.ID(zoneName: parts[0], ownerName: parts[1]))
        }
        knownOnDisk = out
        return out
    }

    /// Indlæser zonen fra disk første gang, den bruges (lock holdes af kalderen).
    private func load(_ zone: CKRecordZone.ID) -> [CKRecord.ID: CKRecord] {
        if let map = zones[zone] { return map }
        var map: [CKRecord.ID: CKRecord] = [:]
        if let data = try? Data(contentsOf: url(zone)),
           let records = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSArray.self, CKRecord.self, CKShare.self], from: data) as? [CKRecord] {
            for r in records { map[r.recordID] = r }
            loaded.insert(zone)
        }
        zones[zone] = map
        return map
    }

    private func save(_ zone: CKRecordZone.ID) {
        let records = Array((zones[zone] ?? [:]).values)
        let target = url(zone)
        knownOnDisk?.insert(zone)
        // Skrives i baggrunden; NSKeyedArchiver arbejder på en kopi (CKRecord er NSCopying via arkivering).
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: records as NSArray, requiringSecureCoding: true) else { return }
        Task.detached(priority: .utility) {
            try? data.write(to: target, options: .atomic)
        }
    }
}
