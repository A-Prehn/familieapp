import Foundation

// Datalag bag ét interface — præcis som i web-prototypen.
// MemoryStore bruges til build/preview/simulator. CloudKitStore (ægte sync)
// implementeres når Apple Developer-kontoen og iCloud-containeren er på plads.
protocol Store {
    func signIn(name: String) async throws -> AppUser
    func user(id: String) async throws -> AppUser?

    func families(for userId: String) async throws -> [Family]
    func createFamily(userId: String, name: String) async throws -> Family
    func members(familyId: String) async throws -> [AppUser]
    func createInvite(userId: String, familyId: String) async throws -> String
    func acceptInvite(userId: String, code: String) async throws -> Family

    func children(familyId: String) async throws -> [Child]
    func createChild(familyId: String, name: String, gender: Gender,
                     birthDate: Date?, dueDate: Date?) async throws -> Child

    func highlights(childId: String) async throws -> [Highlight]
    func addHighlight(childId: String, date: Date?, text: String) async throws -> Highlight

    func events(familyId: String) async throws -> [FamilyEvent]
    func addEvent(familyId: String, title: String, date: Date?, details: String) async throws -> FamilyEvent
}

enum StoreError: LocalizedError {
    case notImplemented
    case invalidInvite
    case notFound

    var errorDescription: String? {
        switch self {
        case .notImplemented: return "Ikke implementeret endnu."
        case .invalidInvite: return "Ugyldig invitationskode."
        case .notFound: return "Findes ikke."
        }
    }
}

func newId(_ prefix: String) -> String {
    prefix + "_" + UUID().uuidString.prefix(8).lowercased()
}
