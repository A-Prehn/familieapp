import XCTest
import UIKit
import ImageIO
@testable import Mindebog

// Automatiske tests, der kører før hvert TestFlight-build (#54). Fejler én, stopper buildet.
// Datalaget testes mod MemoryStore (CloudKit kræver en rigtig Apple-konto og testes i TestFlight).

// MARK: - Gem og slet

final class StoreTests: XCTestCase {
    private func familyWithChild() async throws -> (MemoryStore, Family, Child) {
        let store = MemoryStore()
        let user = try await store.signIn(name: "Test")
        let family = try await store.createFamily(userId: user.id, name: "Testfamilien")
        let child = try await store.createChild(familyId: family.id, name: "Nohr", gender: .boy,
                                                birthDate: Date(timeIntervalSinceNow: -4 * 365 * 86_400), dueDate: nil)
        return (store, family, child)
    }

    func testDeleteHighlightOnlyRemovesThatOne() async throws {
        let (store, _, child) = try await familyWithChild()
        let a = try await store.addHighlight(childId: child.id, date: nil, text: "Første skridt", photos: [], cover: 0, place: nil)
        let b = try await store.addHighlight(childId: child.id, date: nil, text: "Første ord", photos: [], cover: 0, place: nil)
        try await store.deleteHighlight(childId: child.id, id: a.id)
        let left = try await store.highlights(childId: child.id)
        XCTAssertEqual(left.map(\.id), [b.id], "Kun det slettede højdepunkt må forsvinde")
    }

    func testDeleteGalleryItemOnlyRemovesThatOne() async throws {
        let (store, _, child) = try await familyWithChild()
        let a = try await store.addGalleryItem(childId: child.id, kind: .belly, caption: "Uge 20+0", photo: nil)
        let b = try await store.addGalleryItem(childId: child.id, kind: .belly, caption: "Uge 24+0", photo: nil)
        try await store.deleteGalleryItem(childId: child.id, id: a.id)
        let left = try await store.gallery(childId: child.id, kind: .belly)
        XCTAssertEqual(left.map(\.id), [b.id])
    }

    func testDeleteVacationOnlyRemovesThatOne() async throws {
        let (store, family, _) = try await familyWithChild()
        let a = try await store.addVacation(familyId: family.id, title: "Skagen", start: nil, end: nil, details: "",
                                            photos: PhotoSet(), place: nil, childIds: [], personIds: [])
        let b = try await store.addVacation(familyId: family.id, title: "Egypten", start: nil, end: nil, details: "",
                                            photos: PhotoSet(), place: nil, childIds: [], personIds: [])
        try await store.deleteVacation(familyId: family.id, id: a.id)
        let left = try await store.vacations(familyId: family.id)
        XCTAssertEqual(left.map(\.id), [b.id])
    }

    func testLettersAreSavedAndDeletedPerChild() async throws {
        let (store, family, nohr) = try await familyWithChild()
        let william = try await store.createChild(familyId: family.id, name: "William", gender: .boy, birthDate: nil, dueDate: nil)
        let letter = Letter(id: "l1", title: "Til dig", text: "Hej", author: "Mor", writtenAt: Date(), openDate: nil)
        try await store.addLetter(childId: nohr.id, letter)
        let otherLetters = try await store.letters(childId: william.id)
        XCTAssertTrue(otherLetters.isEmpty, "Et brev til ét barn må ikke dukke op hos et andet")
        try await store.deleteLetter(childId: nohr.id, id: letter.id)
        let nohrLetters = try await store.letters(childId: nohr.id)
        XCTAssertTrue(nohrLetters.isEmpty)
    }

    func testDeleteChildOnlyRemovesThatChild() async throws {
        let (store, family, nohr) = try await familyWithChild()
        let william = try await store.createChild(familyId: family.id, name: "William", gender: .boy, birthDate: nil, dueDate: nil)
        _ = try await store.addHighlight(childId: nohr.id, date: nil, text: "Første skridt", photos: [], cover: 0, place: nil)
        try await store.deleteChild(nohr)
        let kids = try await store.children(familyId: family.id)
        XCTAssertEqual(kids.map(\.id), [william.id], "Kun det slettede barn må forsvinde")
        let left = try await store.highlights(childId: nohr.id)
        XCTAssertTrue(left.isEmpty, "Barnets indhold skal slettes med")
    }

    func testChildOwnAccountSeesOnlyOpenedLetters() async throws {
        let (store, _, nohr) = try await familyWithChild()
        let sealed = Letter(id: "s", title: "Til dig som 18-årig", text: "", author: "Mor", writtenAt: Date(),
                            openDate: Date(timeIntervalSinceNow: 86_400))
        let open = Letter(id: "o", title: "Hej", text: "", author: "Far", writtenAt: Date(), openDate: nil)
        try await store.addLetter(childId: nohr.id, sealed)
        try await store.addLetter(childId: nohr.id, open)
        defer { MeChild.set(nil) }
        MeChild.set(nil)
        let asParent = try await store.letters(childId: nohr.id)
        XCTAssertEqual(asParent.count, 2, "Forældre ser alle breve")
        MeChild.set(nohr.id)
        let asChild = try await store.letters(childId: nohr.id)
        XCTAssertEqual(asChild.map(\.id), ["o"], "Barnet ser kun åbnede breve")
        XCTAssertEqual(nohr.displayName, "Nohr (dig)")
        var linked = nohr
        linked.linkedUserId = "user_abc"
        let saved = try await store.updateChild(linked)
        XCTAssertEqual(saved.linkedUserId, "user_abc", "Koblingen til barnets konto gemmes")
    }

    func testDeleteFamilyRemovesItsChildren() async throws {
        let (store, family, _) = try await familyWithChild()
        try await store.deleteFamily(familyId: family.id)
        let kids = try await store.children(familyId: family.id)
        XCTAssertTrue(kids.isEmpty)
    }
}

// MARK: - Invitationer

@MainActor
final class InviteTests: XCTestCase {
    func testAppStoreLinkIsRejected() {
        XCTAssertNotNil(AppState.inviteProblem("https://apps.apple.com/dk/app/vores-familie/id6823090981"))
    }

    func testRandomTextIsRejected() {
        XCTAssertNotNil(AppState.inviteProblem("hej"))
    }

    func testICloudShareLinkIsAccepted() {
        XCTAssertNil(AppState.inviteProblem("  https://www.icloud.com/share/0abcDEF123#Vores_familie \n"))
    }
}

// MARK: - Logik

final class LogicTests: XCTestCase {
    private let cal = Calendar.current

    func testGestationCaptionFromDueDate() {
        let due = cal.date(from: DateComponents(year: 2027, month: 1, day: 1))!
        let day = cal.date(byAdding: .day, value: -(280 - (28 * 7 + 2)), to: due)!   // uge 28+2
        XCTAssertEqual(AddGalleryItemView.gestationCaption(on: day, due: due), "Uge 28+2")
    }

    func testGestationCaptionIsNilFarOutsidePregnancy() {
        let due = cal.date(from: DateComponents(year: 2027, month: 1, day: 1))!
        let long = cal.date(byAdding: .day, value: -400, to: due)!
        XCTAssertNil(AddGalleryItemView.gestationCaption(on: long, due: due))
    }

    func testHandwrittenWeekGetsPrefix() {
        XCTAssertEqual(Fmt.gestation("28+2"), "Uge 28+2")
        XCTAssertEqual(Fmt.gestation("28"), "Uge 28")
        XCTAssertEqual(Fmt.gestation("Uge 28+2"), "Uge 28+2", "Står der allerede Uge, røres teksten ikke")
        XCTAssertEqual(Fmt.gestation("Første spark"), "Første spark")
    }

    func testNoHolidaysForUnbornOrBabies() {
        let unborn = Child(id: "u", familyId: "f", name: "Baby Blob", birthDate: nil,
                           dueDate: Date(timeIntervalSinceNow: 60 * 86_400), gender: .unspecified)
        let baby = Child(id: "b", familyId: "f", name: "Liv", birthDate: Date(timeIntervalSinceNow: -150 * 86_400),
                         dueDate: nil, gender: .girl)
        let kid = Child(id: "k", familyId: "f", name: "Nohr", birthDate: Date(timeIntervalSinceNow: -4 * 365 * 86_400),
                        dueDate: nil, gender: .boy)
        XCTAssertFalse(WeeklyQuestion.hasHolidays(unborn))
        XCTAssertFalse(WeeklyQuestion.hasHolidays(baby))
        XCTAssertTrue(WeeklyQuestion.hasHolidays(kid))
    }

    func testSealedLetter() {
        let sealed = Letter(id: "1", title: "", text: "", author: "", writtenAt: Date(),
                            openDate: Date(timeIntervalSinceNow: 86_400))
        let open = Letter(id: "2", title: "", text: "", author: "", writtenAt: Date(), openDate: nil)
        XCTAssertTrue(sealed.isSealed)
        XCTAssertFalse(open.isSealed)
    }

    @MainActor
    func testTwoFreeChildren() {
        XCTAssertEqual(AppState.freeChildLimit, 2)
    }

    func testResizeKeepsCaptureDate() throws {
        // Lav et JPEG med optagelsesdato i EXIF, skalér ned, og tjek at datoen er bevaret.
        let size = CGSize(width: 2400, height: 1600)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.systemPink.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
        }
        let out = NSMutableData()
        let dest = try XCTUnwrap(CGImageDestinationCreateWithData(out, "public.jpeg" as CFString, 1, nil))
        let meta: [CFString: Any] = [kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2025:12:20 14:30:00"]]
        CGImageDestinationAddImage(dest, try XCTUnwrap(image.cgImage), meta as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))

        let resized = try XCTUnwrap(ImageTools.resized(out as Data))
        let taken = try XCTUnwrap(ImageTools.captureDate(resized), "Optagelsesdatoen forsvandt ved nedskalering")
        let parts = cal.dateComponents([.year, .month, .day], from: taken)
        XCTAssertEqual(parts.year, 2025); XCTAssertEqual(parts.month, 12); XCTAssertEqual(parts.day, 20)
    }
}
