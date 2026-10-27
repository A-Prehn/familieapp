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

    func testSurvivesRestart() async throws {
        let first = LocalRecords(directory: dir)
        first.apply(changed: [highlight("a", text: "gemt")], deleted: [], in: zone)
        // Skrivningen sker i baggrunden — giv den et øjeblik.
        for _ in 0..<50 where !LocalRecords(directory: dir).hasSnapshot(zone) {
            try await Task.sleep(for: .milliseconds(20))
        }
        let second = LocalRecords(directory: dir)
        XCTAssertTrue(second.hasSnapshot(zone))
        XCTAssertEqual(second.record(CKRecord.ID(recordName: "a", zoneID: zone))?["text"] as? String, "gemt")
        XCTAssertEqual(second.snapshotZones(), [zone])
    }

    func testPurgeRemovesZone() async throws {
        let local = LocalRecords(directory: dir)
        local.apply(changed: [highlight("a", text: "x")], deleted: [], in: zone)
        local.purge(named: "family_test")
        XCTAssertFalse(local.hasSnapshot(zone))
        XCTAssertTrue(local.snapshotZones().isEmpty)
    }
}
