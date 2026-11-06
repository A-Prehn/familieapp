import XCTest
import CloudKit
@testable import Mindebog

// Den lokale kopi (#62): ændringer anvendes rigtigt, filer holdes ude, og kopien overlever en genstart.
final class LocalRecordsTests: XCTestCase {
    private var dir: URL!
    private let zone = CKRecordZone.ID(zoneName: "family_test", ownerName: CKCurrentUserDefaultName)

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("LocalRecordsTests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    private func highlight(_ name: String, text: String) -> CKRecord {
        let r = CKRecord(recordType: "Highlight", recordID: CKRecord.ID(recordName: name, zoneID: zone))
        r["text"] = text as CKRecordValue
        return r
    }

    func testApplyAddsUpdatesAndDeletes() {
        let local = LocalRecords(directory: dir)
        XCTAssertFalse(local.hasSnapshot(zone))
        local.apply(changed: [highlight("a", text: "Første skridt"), highlight("b", text: "Første ord")], deleted: [], in: zone)
        XCTAssertTrue(local.hasSnapshot(zone))
        XCTAssertEqual(local.records(in: zone, type: "Highlight").count, 2)

        local.apply(changed: [highlight("a", text: "Første skridt (rettet)")],
                    deleted: [CKRecord.ID(recordName: "b", zoneID: zone)], in: zone)
        let left = local.records(in: zone, type: "Highlight")
        XCTAssertEqual(left.map(\.recordID.recordName), ["a"])
        XCTAssertEqual(left.first?["text"] as? String, "Første skridt (rettet)")
    }

    func testOwnSaveDoesNotCreateHalfSnapshot() {
        // Et gem i en zone, der ikke er hentet endnu, må ikke få kopien til at se komplet ud med én record.
        let local = LocalRecords(directory: dir)
        local.apply(changed: [highlight("a", text: "x")], deleted: [], in: zone, createIfMissing: false)
        XCTAssertFalse(local.hasSnapshot(zone))
        XCTAssertTrue(local.records(in: zone).isEmpty)
    }

    func testAssetsAreStripped() throws {
        let local = LocalRecords(directory: dir)
        let file = dir.appendingPathComponent("p.jpg")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: file)
        let r = highlight("a", text: "med billede")
        r["photos"] = [CKAsset(fileURL: file)] as CKRecordValue
        local.apply(changed: [r], deleted: [], in: zone)
        let stored = try XCTUnwrap(local.record(r.recordID))
        XCTAssertNil(stored["photos"], "Filer hører ikke hjemme i kopien")
        XCTAssertEqual(stored["text"] as? String, "med billede")
        XCTAssertNotNil(r["photos"], "Originalen må ikke ændres")
    }

    func testSurvivesRestart() throws {
        let first = LocalRecords(directory: dir)
        first.apply(changed: [highlight("a", text: "gemt")], deleted: [], in: zone)
        let second = LocalRecords(directory: dir)
        XCTAssertTrue(second.hasSnapshot(zone))
        XCTAssertEqual(second.record(CKRecord.ID(recordName: "a", zoneID: zone))?["text"] as? String, "gemt")
        XCTAssertEqual(second.snapshotZones(), [zone])
    }

    func testPurgeRemovesZone() throws {
        let local = LocalRecords(directory: dir)
        local.apply(changed: [highlight("a", text: "x")], deleted: [], in: zone)
        local.purge(named: "family_test")
        XCTAssertFalse(local.hasSnapshot(zone))
        XCTAssertTrue(local.snapshotZones().isEmpty)
    }
}

// MARK: - Udbakke (#63)

/// Et gem uden net skal kunne ligge på disken og læses igen efter en "genstart" — med billedet.
final class OutboxTests: XCTestCase {
    func testOutboxKeepsRecordAndPhotoAcrossRestart() throws {
        let zone = CKRecordZone.ID(zoneName: "family_test_outbox", ownerName: CKCurrentUserDefaultName)
        let id = CKRecord.ID(recordName: "hl_outbox_\(UUID().uuidString)", zoneID: zone)
        let record = CKRecord(recordType: "Highlight", recordID: id)
        record["text"] = "Første skridt" as CKRecordValue
        let photo = Data([0xFF, 0xD8, 0xFF, 0x01, 0x02, 0x03])
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        try photo.write(to: file)
        record["photos"] = [CKAsset(fileURL: file)] as CKRecordValue
        defer { CloudKitStore.Outbox.remove(id) }

        CloudKitStore.Outbox.write(record, shared: false)
        try? FileManager.default.removeItem(at: file)   // upload-filen ryddes op, som efter et gem

        XCTAssertTrue(CloudKitStore.Outbox.contains(id))
        let entry = try XCTUnwrap(CloudKitStore.Outbox.all().first { $0.record.recordID == id })
        XCTAssertEqual(entry.record["text"] as? String, "Første skridt")
        XCTAssertEqual(Set(entry.keys), ["text", "photos"])
        XCTAssertFalse(entry.shared)
        let assets = try XCTUnwrap(entry.record["photos"] as? [CKAsset])
        XCTAssertEqual(assets.count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(assets[0].fileURL)), photo, "Billedet overlever i udbakken")

        CloudKitStore.Outbox.remove(id)
        XCTAssertFalse(CloudKitStore.Outbox.contains(id))
    }
}
