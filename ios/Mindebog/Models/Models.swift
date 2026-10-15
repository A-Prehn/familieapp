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

    var title: String {
        switch self {
        case .belly: return "Maven måned for måned"
        case .monthly: return "Måned for måned"
        }
    }
    var captionLabel: String {
        switch self {
        case .belly: return "Uge/måned"
        case .monthly: return "Måned"
        }
    }
    var captionPlaceholder: String {
        switch self {
        case .belly: return "F.eks. Uge 24"
        case .monthly: return "F.eks. 3 måneder"
        }
    }
}

struct GalleryItem: Identifiable, Hashable, Codable {
    let id: String
    var caption: String
    var photo: Data?
    var createdAt: Date
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

/// Let oversigt over et minde (uden billeder) — til Hjem, så forsiden ikke skal
/// hente alle familiens billeder for at finde de få, der vises.
struct MemorySummary: Identifiable, Hashable, Codable {
    enum Kind: String, Codable { case highlight, diary, event, vacation }
    let id: String          // record-id
    let kind: Kind
    let childId: String?    // nil for fælles (begivenhed/ferie)
    let date: Date?
    let createdAt: Date
    let text: String        // tekst / titel
}

struct CustomBirthday: Identifiable, Hashable, Codable {
    let id: String
    var name: String
    var date: Date
    var emoji: String
}
