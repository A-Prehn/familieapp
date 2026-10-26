import CloudKit
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
    /// Sletter familien og alt dens indhold for altid (kun ejeren). Også for dem, den er delt med.
    func deleteFamily(familyId: String) async throws
    func deleteChild(_ child: Child) async throws   // barnet og alt dets indhold
    func members(familyId: String) async throws -> [AppUser]
    /// false for medlemmer med "Kun visning" (fx bedsteforældre) — så skjules tilføj/redigér/slet.
    func canEdit(familyId: String) async -> Bool
    /// Gemmer brugerens visningsnavn i familien, så de andre medlemmer kan se det.
    func setMemberName(familyId: String, userId: String, name: String) async throws
    func createInvite(userId: String, familyId: String) async throws -> String
    func acceptInvite(userId: String, code: String) async throws -> Family

    // Børn
    func children(familyId: String) async throws -> [Child]
    func createChild(familyId: String, name: String, gender: Gender,
                     birthDate: Date?, dueDate: Date?) async throws -> Child
    func updateChild(_ child: Child) async throws -> Child
    /// Børn delt direkte med én (fx fra den anden forælders familie). Tom uden iCloud.
    func sharedChildren() async throws -> [Child]

    // Pr. barn
    func highlights(childId: String) async throws -> [Highlight]
    func addHighlight(childId: String, date: Date?, text: String, photos: [Data], cover: Int, place: Place?) async throws -> Highlight
    func updateHighlight(childId: String, _ highlight: Highlight) async throws
    func deleteHighlight(childId: String, id: String) async throws
    /// Video og lydnote på et højdepunkt (gemmes separat, så listen ikke henter store filer).
    func setHighlightMedia(childId: String, id: String, video: MediaChange, audio: MediaChange) async throws
    /// Henter video/lyd lokalt til afspilning.
    func highlightMedia(childId: String, id: String) async throws -> (video: URL?, audio: URL?)

    func milestones(childId: String) async throws -> [String: MilestoneEntry]
    func setMilestone(childId: String, key: String, value: String?, photos: PhotoSet) async throws

    func answers(childId: String) async throws -> [String: String]
    func setAnswer(childId: String, question: String, answer: String) async throws

    func diary(childId: String) async throws -> [DiaryEntry]
    func addDiary(childId: String, date: Date?, text: String, photo: Data?) async throws -> DiaryEntry
    func updateDiary(childId: String, _ entry: DiaryEntry) async throws
    func deleteDiary(childId: String, id: String) async throws

    func gallery(childId: String, kind: GalleryKind) async throws -> [GalleryItem]
    func addGalleryItem(childId: String, kind: GalleryKind, caption: String, photo: Data?) async throws -> GalleryItem
    func updateGalleryItem(childId: String, _ item: GalleryItem) async throws
    func deleteGalleryItem(childId: String, id: String) async throws

    // Vækst
    func measurements(childId: String) async throws -> [Measurement]
    func saveMeasurement(childId: String, _ measurement: Measurement) async throws   // opret eller opdatér
    func deleteMeasurement(childId: String, id: String) async throws

    // Breve til barnet
    func letters(childId: String) async throws -> [Letter]
    func addLetter(childId: String, _ letter: Letter) async throws
    func updateLetter(childId: String, _ letter: Letter) async throws
    func deleteLetter(childId: String, id: String) async throws

    // Videobrev
    func setLetterVideo(childId: String, id: String, video: MediaChange) async throws
    func letterVideo(childId: String, id: String) async throws -> URL?

    // Det årlige interview
    func interviews(childId: String) async throws -> [InterviewAnswer]
    func saveInterviewAnswer(childId: String, _ answer: InterviewAnswer, audio: MediaChange, video: MediaChange) async throws
    func deleteInterviewAnswer(childId: String, id: String) async throws
    func interviewMedia(childId: String, id: String) async throws -> (video: URL?, audio: URL?)

    // Traditioner (pr. familie)
    func traditions(familyId: String) async throws -> [Tradition]
    func saveTradition(familyId: String, _ tradition: Tradition, audio: MediaChange) async throws
    func deleteTradition(familyId: String, id: String) async throws
    func traditionAudio(familyId: String, id: String) async throws -> URL?

    // Opskrifter (pr. familie)
    func recipes(familyId: String) async throws -> [Recipe]
    func saveRecipe(familyId: String, _ recipe: Recipe) async throws   // opret eller opdatér
    func deleteRecipe(familyId: String, id: String) async throws

    // Reaktioner og kommentarer (pr. familie, på tværs af alt indhold)
    func comments(familyId: String) async throws -> [Comment]
    func addComment(familyId: String, _ comment: Comment) async throws
    func deleteComment(familyId: String, id: String) async throws

    // Minder (frie minder under Fælles)
    func memories(familyId: String) async throws -> [FamilyMemory]
    func saveMemory(familyId: String, _ memory: FamilyMemory) async throws   // opret eller opdatér
    func deleteMemory(familyId: String, id: String) async throws

    // Premium for hele familien (ejerens køb, så partner/bedsteforældre også får det)
    func familyPremium(familyId: String) async -> Date?
    func setFamilyPremium(familyId: String, until: Date?) async throws

    // Pr. familie
    func events(familyId: String) async throws -> [FamilyEvent]
    func addEvent(familyId: String, title: String, date: Date?, details: String,
                  photos: PhotoSet, place: Place?, childIds: [String], personIds: [String]) async throws -> FamilyEvent

    func updateEvent(familyId: String, _ event: FamilyEvent) async throws -> FamilyEvent
    func deleteEvent(familyId: String, id: String) async throws

    func vacations(familyId: String) async throws -> [Vacation]
    func updateVacation(familyId: String, _ vacation: Vacation) async throws -> Vacation
    func deleteVacation(familyId: String, id: String) async throws
    func addVacation(familyId: String, title: String, start: Date?, end: Date?,
                     details: String, photos: PhotoSet, place: Place?, childIds: [String], personIds: [String]) async throws -> Vacation

    // Hjem: lette oversigter uden billeder, og billede kun til de minder der vises.
    func memorySummaries(familyId: String) async throws -> [MemorySummary]
    func coverPhoto(familyId: String, memory: MemorySummary) async throws -> Data?

    func birthdays(familyId: String) async throws -> [CustomBirthday]
    func addBirthday(familyId: String, name: String, date: Date, emoji: String) async throws -> CustomBirthday
    func updateBirthday(familyId: String, _ birthday: CustomBirthday) async throws
    func deleteBirthday(familyId: String, id: String) async throws

    // Familietræ
    func persons(familyId: String) async throws -> [Person]
    func savePerson(familyId: String, _ person: Person) async throws   // opret eller opdatér
    func deletePerson(familyId: String, id: String) async throws
}

enum StoreError: LocalizedError {
    case notImplemented
    case invalidInvite
    case notFound
    case notOwner
    case moveIncomplete(String)

    var errorDescription: String? {
        switch self {
        case .notImplemented: return "Ikke implementeret endnu."
        case .invalidInvite: return "Ugyldig invitationskode."
        case .notFound: return "Findes ikke."
        case .notOwner: return "Kun den, der har oprettet familien, kan gøre det."
        case .moveIncomplete(let type): return "Flytningen blev ikke færdig (\(type)). Prøv igen — intet er slettet."
        }
    }
}

extension Error {
    /// Fejltekst til brugeren — med iClouds egen forklaring, når der er en (så vi kan se, hvad der gik galt).
    var userMessage: String {
        guard let ck = self as? CKError else { return localizedDescription }
        let server = ck.userInfo["ServerErrorDescription"] as? String
            ?? (ck.userInfo[NSUnderlyingErrorKey] as? Error)?.localizedDescription
        return server.map { "\(ck.localizedDescription) \($0)" } ?? ck.localizedDescription
    }
}

func newId(_ prefix: String) -> String {
    prefix + "_" + UUID().uuidString.prefix(8).lowercased()
}
