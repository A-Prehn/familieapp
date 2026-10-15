import Foundation
import CloudKit

// CloudKit-implementering af Store — ÆGTE sync i hver brugers egen iCloud.
//
// STATUS: stub. Metoderne er endnu ikke implementeret, men typerne kompilerer,
// så CI kan bygge. Implementeres når iCloud-containeren (iCloud.net.prehn.mindebog)
// er oprettet via en Apple Developer-konto.
//
// Plan for mapping (fase 2b):
//   Family -> CKRecord("Family") i privat DB; deles med CKShare (begge forældre).
//   Child  -> CKRecord("Child"), reference til Family.
//   Highlight/Diary/Gallery/Milestone/Event/Vacation -> CKRecord med reference til Child/Family.
//   Fotos  -> CKAsset.
//   Realtids-sync -> CKDatabaseSubscription + push (aps-environment).
//
// Sign in with Apple + CKContainer giver automatisk en stabil bruger-identitet,
// så data isoleres pr. familie uden egen server (nul lageromkostning).
final class CloudKitStore: Store {
    private let container: CKContainer
    private var database: CKDatabase { container.privateCloudDatabase }

    init(containerIdentifier: String = "iCloud.net.prehn.mindebog") {
        self.container = CKContainer(identifier: containerIdentifier)
    }

    private func todo<T>() throws -> T { throw StoreError.notImplemented }

    func signIn(name: String) async throws -> AppUser { try todo() }
    func user(id: String) async throws -> AppUser? { try todo() }

    func families(for userId: String) async throws -> [Family] { try todo() }
    func createFamily(userId: String, name: String) async throws -> Family { try todo() }
    func members(familyId: String) async throws -> [AppUser] { try todo() }
    func createInvite(userId: String, familyId: String) async throws -> String { try todo() }
    func acceptInvite(userId: String, code: String) async throws -> Family { try todo() }

    func children(familyId: String) async throws -> [Child] { try todo() }
    func createChild(familyId: String, name: String, gender: Gender,
                     birthDate: Date?, dueDate: Date?) async throws -> Child { try todo() }

    func highlights(childId: String) async throws -> [Highlight] { try todo() }
    func addHighlight(childId: String, date: Date?, text: String, photos: [Data]) async throws -> Highlight { try todo() }

    func milestones(childId: String) async throws -> [String: MilestoneEntry] { try todo() }
    func setMilestone(childId: String, key: String, value: String?, photo: Data?) async throws {
        throw StoreError.notImplemented
    }

    func answers(childId: String) async throws -> [String: String] { try todo() }
    func setAnswer(childId: String, question: String, answer: String) async throws {
        throw StoreError.notImplemented
    }

    func diary(childId: String) async throws -> [DiaryEntry] { try todo() }
    func addDiary(childId: String, date: Date?, text: String, photo: Data?) async throws -> DiaryEntry { try todo() }

    func gallery(childId: String, kind: GalleryKind) async throws -> [GalleryItem] { try todo() }
    func addGalleryItem(childId: String, kind: GalleryKind, caption: String, photo: Data?) async throws -> GalleryItem { try todo() }

    func events(familyId: String) async throws -> [FamilyEvent] { try todo() }
    func addEvent(familyId: String, title: String, date: Date?, details: String) async throws -> FamilyEvent { try todo() }

    func vacations(familyId: String) async throws -> [Vacation] { try todo() }
    func addVacation(familyId: String, title: String, start: Date?, end: Date?,
                     details: String, photo: Data?) async throws -> Vacation { try todo() }

    func birthdays(familyId: String) async throws -> [CustomBirthday] { try todo() }
    func addBirthday(familyId: String, name: String, date: Date, emoji: String) async throws -> CustomBirthday { try todo() }
}
