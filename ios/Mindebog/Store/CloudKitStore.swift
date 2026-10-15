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
//   Highlight/Event/… -> CKRecord med reference til Child/Family.
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

    func signIn(name: String) async throws -> AppUser { throw StoreError.notImplemented }
    func user(id: String) async throws -> AppUser? { throw StoreError.notImplemented }

    func families(for userId: String) async throws -> [Family] { throw StoreError.notImplemented }
    func createFamily(userId: String, name: String) async throws -> Family { throw StoreError.notImplemented }
    func members(familyId: String) async throws -> [AppUser] { throw StoreError.notImplemented }
    func createInvite(userId: String, familyId: String) async throws -> String { throw StoreError.notImplemented }
    func acceptInvite(userId: String, code: String) async throws -> Family { throw StoreError.notImplemented }

    func children(familyId: String) async throws -> [Child] { throw StoreError.notImplemented }
    func createChild(familyId: String, name: String, gender: Gender,
                     birthDate: Date?, dueDate: Date?) async throws -> Child { throw StoreError.notImplemented }

    func highlights(childId: String) async throws -> [Highlight] { throw StoreError.notImplemented }
    func addHighlight(childId: String, date: Date?, text: String) async throws -> Highlight { throw StoreError.notImplemented }

    func events(familyId: String) async throws -> [FamilyEvent] { throw StoreError.notImplemented }
    func addEvent(familyId: String, title: String, date: Date?, details: String) async throws -> FamilyEvent { throw StoreError.notImplemented }
}
