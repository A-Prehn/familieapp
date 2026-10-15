import Foundation

// Datalag bag ét interface — præcis som i web-prototypen.
// MemoryStore bruges til build/preview/simulator. CloudKitStore (ægte sync)
// implementeres når Apple Developer-kontoen og iCloud-containeren er på plads.
protocol Store {
    func signIn(name: String) async throws -> AppUser
    func user(id: String) async throws -> AppUser?

    // Familie + deling
    func families(for userId: String) async throws -> [Family]
    func createFamily(userId: String, name: String) async throws -> Family
    func members(familyId: String) async throws -> [AppUser]
    func createInvite(userId: String, familyId: String) async throws -> String
    func acceptInvite(userId: String, code: String) async throws -> Family

    // Børn
    func children(familyId: String) async throws -> [Child]
    func createChild(familyId: String, name: String, gender: Gender,
                     birthDate: Date?, dueDate: Date?) async throws -> Child

    // Pr. barn
    func highlights(childId: String) async throws -> [Highlight]
    func addHighlight(childId: String, date: Date?, text: String, photos: [Data]) async throws -> Highlight

    func milestones(childId: String) async throws -> [String: MilestoneEntry]
    func setMilestone(childId: String, key: String, value: String?, photo: Data?) async throws

    func answers(childId: String) async throws -> [String: String]
    func setAnswer(childId: String, question: String, answer: String) async throws

    func diary(childId: String) async throws -> [DiaryEntry]
    func addDiary(childId: String, date: Date?, text: String, photo: Data?) async throws -> DiaryEntry

    func gallery(childId: String, kind: GalleryKind) async throws -> [GalleryItem]
    func addGalleryItem(childId: String, kind: GalleryKind, caption: String, photo: Data?) async throws -> GalleryItem

    // Pr. familie
    func events(familyId: String) async throws -> [FamilyEvent]
    func addEvent(familyId: String, title: String, date: Date?, details: String, photo: Data?) async throws -> FamilyEvent

    func vacations(familyId: String) async throws -> [Vacation]
    func addVacation(familyId: String, title: String, start: Date?, end: Date?,
                     details: String, photo: Data?) async throws -> Vacation

    func birthdays(familyId: String) async throws -> [CustomBirthday]
    func addBirthday(familyId: String, name: String, date: Date, emoji: String) async throws -> CustomBirthday
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
