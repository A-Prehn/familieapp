import Foundation

// Datamodeller — spejler web-prototypens domæne. Generisk/multi-tenant.
// Fotos er Data (JPEG) i prototypen; i CloudKit bliver de til CKAsset.

enum Gender: String, Codable, CaseIterable, Identifiable {
    case girl, boy, unspecified
    var id: String { rawValue }
    var label: String {
        switch self {
        case .girl: return "Pige"
        case .boy: return "Dreng"
        case .unspecified: return "Ikke angivet"
        }
    }
}

struct AppUser: Identifiable, Hashable, Codable {
    let id: String
    var name: String
}

struct Family: Identifiable, Hashable, Codable {
    let id: String
    var name: String
    var ownerId: String
    var memberIds: [String]
}

struct Child: Identifiable, Hashable, Codable {
    let id: String
    var familyId: String
    var name: String
    var birthDate: Date?
    var dueDate: Date?
    var gender: Gender
    /// Profilbillede (valgfrit); ellers vises en emoji efter alder og køn.
    var photo: Data? = nil

    var onTheWay: Bool { birthDate == nil && dueDate != nil }
}

struct Highlight: Identifiable, Hashable, Codable {
    let id: String
    var date: Date?
    var text: String
    var photos: [Data]
    var createdAt: Date
    /// Varighed i sekunder, hvis der er en video/lydnote. Selve filen hentes først ved afspilning.
    var videoDuration: Double? = nil
    var audioDuration: Double? = nil
}

/// Flere billeder med ét valgt forsidebillede og evt. billedtekst pr. billede
/// (som på websitet: forsiden vises på kortet med "+N" for resten).
struct PhotoSet: Hashable, Codable {
    var photos: [Data] = []
    var captions: [String] = []     // samme rækkefølge som photos; "" = ingen tekst
    var cover: Int = 0

    init(photos: [Data] = [], captions: [String] = [], cover: Int = 0) {
        self.photos = photos
        self.captions = captions
        self.cover = cover
    }

    /// Bagudkompatibelt: ét enkelt billede (eller intet).
    init(single: Data?) { self.init(photos: single.map { [$0] } ?? []) }

    var isEmpty: Bool { photos.isEmpty }
    var count: Int { photos.count }
    private var safeCover: Int { photos.indices.contains(cover) ? cover : 0 }
    var coverPhoto: Data? { photos.isEmpty ? nil : photos[safeCover] }
    var coverCaption: String { caption(at: safeCover) }
    var coverIndex: Int { safeCover }

    func caption(at index: Int) -> String { captions.indices.contains(index) ? captions[index] : "" }

    mutating func append(_ data: Data) {
        photos.append(data)
        captions.append("")
    }

    mutating func remove(at index: Int) {
        guard photos.indices.contains(index) else { return }
        photos.remove(at: index)
        if captions.indices.contains(index) { captions.remove(at: index) }
        if cover == index { cover = 0 } else if cover > index { cover -= 1 }
    }

    mutating func setCaption(_ text: String, at index: Int) {
        while captions.count < photos.count { captions.append("") }
        if captions.indices.contains(index) { captions[index] = text }
    }
}

struct MilestoneEntry: Hashable, Codable {
    var value: String?
    var photos: PhotoSet = PhotoSet()
    /// Forsidebilledet (det der vises på flisen).
    var photo: Data? { photos.coverPhoto }
}

struct DiaryEntry: Identifiable, Hashable, Codable {
    let id: String
    var date: Date?
    var text: String
    var photo: Data?
    var createdAt: Date
}

enum GalleryKind: String, Codable, Hashable {
    case belly      // Maven måned for måned
    case monthly    // Måned for måned
    case drawings   // Tegninger (scannet med kameraet)
    case birthday   // Fødselsdage (billedteksten er alderen, fx "5")

    var title: String {
        switch self {
        case .belly: return "Maven måned for måned"
        case .monthly: return "Måned for måned"
        case .drawings: return "Tegninger"
        case .birthday: return "Fødselsdage"
        }
    }
    var captionLabel: String {
        switch self {
        case .belly: return "Uge/måned"
        case .monthly: return "Måned"
        case .drawings: return "Titel"
        case .birthday: return "Alder"
        }
    }
    var captionPlaceholder: String {
        switch self {
        case .belly: return "F.eks. Uge 24"
        case .monthly: return "F.eks. 3 måneder"
        case .drawings: return "F.eks. Vores hus"
        case .birthday: return "F.eks. 5"
        }
    }
}

struct GalleryItem: Identifiable, Hashable, Codable {
    let id: String
    var caption: String
    /// Lille beskrivelse (fx til tegninger) — vises kun i fuldskærmsvisningen.
    var note: String = ""
    /// Hvornår billedet er fra (kan rettes). nil = da det blev lagt op.
    var date: Date? = nil
    var photo: Data?
    var createdAt: Date
    /// Datoen, der vises og sorteres efter.
    var shownDate: Date { date ?? createdAt }
}

/// Et sted valgt i Apple Maps (fx kirken til brylluppet, sommerhuset).
struct Place: Hashable, Codable {
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
}

struct FamilyEvent: Identifiable, Hashable, Codable {
    let id: String
    var title: String
    var date: Date?
    var details: String
    var photos: PhotoSet = PhotoSet()
    var place: Place? = nil
    /// Forsidebilledet.
    var photo: Data? { photos.coverPhoto }
}

struct Vacation: Identifiable, Hashable, Codable {
    let id: String
    var title: String
    var startDate: Date?
    var endDate: Date?
    var details: String
    var photos: PhotoSet = PhotoSet()
    var place: Place? = nil
    /// Forsidebilledet.
    var photo: Data? { photos.coverPhoto }
}

/// En måling til vækstkurven (vægt, højde, hovedomkreds — hver kan udelades).
struct Measurement: Identifiable, Hashable, Codable {
    let id: String
    var date: Date
    var weightGrams: Int?
    var heightCm: Double?
    var headCm: Double?
}

/// Brev til barnet — forseglet indtil `openDate` (fx 18-års fødselsdagen).
struct Letter: Identifiable, Hashable, Codable {
    let id: String
    var title: String
    var text: String
    var author: String          // hvem skrev det ("Mor", "Andreas")
    var writtenAt: Date
    var openDate: Date?         // nil = kan læses med det samme
    var photo: Data? = nil
    /// Videobrev: varighed i sekunder, hvis der er en video (filen hentes først ved afspilning).
    var videoDuration: Double? = nil

    var isSealed: Bool { openDate.map { $0 > Date() } ?? false }
}

/// Let oversigt over et minde (uden billeder) — til Hjem, så forsiden ikke skal
/// hente alle familiens billeder for at finde de få, der vises.
struct MemorySummary: Identifiable, Hashable, Codable {
    enum Kind: String, Codable { case highlight, diary, event, vacation, photo, interview, tradition, letter, memory }
    let id: String          // record-id
    let kind: Kind
    let childId: String?    // nil for fælles (begivenhed/ferie)
    let date: Date?
    let createdAt: Date
    let text: String        // tekst / titel
    /// Sidst ændret i iCloud — bruges som nøgle i billedcachen og til "Seneste i familien".
    var modifiedAt: Date = .distantPast
    /// Ekstra oplysning, fx billedseriens type ("belly", "monthly", "drawings").
    var detail: String = ""
}

struct CustomBirthday: Identifiable, Hashable, Codable {
    let id: String
    var name: String
    var date: Date
    var emoji: String
}

/// En person i familietræet. Relationer gemmes på personen selv:
/// `parentIds` (nul, én eller to forældre) og `partnerIds` (nuværende og tidligere partnere).
/// Det giver plads til sammenbragte familier: halvsøskende hænger under hvert sit par,
/// og et barn med kun én forælder i træet hænger under den forælder.
/// `childId` kobler personen til et af familiens børn, så navn og billede følger med.
struct Person: Identifiable, Hashable, Codable {
    let id: String
    var name: String
    var birthDate: Date? = nil
    var deathDate: Date? = nil
    /// Kort rolle/beskrivelse, fx "Mormor" eller "Farfar".
    var role: String = ""
    var photo: Data? = nil
    var parentIds: [String] = []
    var partnerIds: [String] = []
    var childId: String? = nil
}

/// Et svar i det årlige interview: samme spørgsmål hvert år, som tekst, lyd eller video.
struct InterviewAnswer: Identifiable, Hashable, Codable {
    let id: String
    var age: Int                 // alder i år ved interviewet
    var question: String         // nøgle fra Constants.interviewQuestions
    var text: String = ""
    var date: Date = Date()
    var audioDuration: Double? = nil
    var videoDuration: Double? = nil
    var hasAnswer: Bool { !text.isEmpty || audioDuration != nil || videoDuration != nil }
}

/// En familietradition: juleaften, fødselsdagssangen, mormors boller …
struct Tradition: Identifiable, Hashable, Codable {
    let id: String
    var title: String
    var when: String = ""        // fx "Juleaften", "Hver fødselsdag"
    var details: String = ""
    var photos: PhotoSet = PhotoSet()
    var audioDuration: Double? = nil
    var photo: Data? { photos.coverPhoto }
}


/// En person i den delte familie og deres adgang (til "Familie og adgang").
struct FamilyParticipant: Identifiable, Hashable {
    enum Access { case owner, editor, viewer
        var rank: Int { switch self { case .owner: 0; case .editor: 1; case .viewer: 2 } }
        var label: String { switch self { case .owner: "Ejer"; case .editor: "Kan redigere"; case .viewer: "Kun visning" } }
    }
    let id: String
    let name: String
    let contact: String     // mail/telefon, hvis det ikke allerede er navnet
    let access: Access
    let pending: Bool       // inviteret, men har ikke åbnet invitationen endnu
    let isMe: Bool
}

/// Et frit minde under Fælles: ikke en begivenhed eller ferie, bare noget, man vil gemme
/// og dele — fx "Mormors 80-års tale" eller "Første gang vi så havet".
struct FamilyMemory: Identifiable, Hashable, Codable {
    let id: String
    var title: String
    var date: Date? = nil
    var text: String = ""
    var photos: PhotoSet = PhotoSet()
    /// Hvilke børn mindet handler om (tomt = hele familien).
    var childIds: [String] = []
    var photo: Data? { photos.coverPhoto }
}
