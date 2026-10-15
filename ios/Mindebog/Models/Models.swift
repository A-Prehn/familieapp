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

    var onTheWay: Bool { birthDate == nil && dueDate != nil }
}

struct Highlight: Identifiable, Hashable, Codable {
    let id: String
    var date: Date?
    var text: String
    var photos: [Data]
    var createdAt: Date
}

struct MilestoneEntry: Hashable, Codable {
    var value: String?
    var photo: Data?
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

struct FamilyEvent: Identifiable, Hashable, Codable {
    let id: String
    var title: String
    var date: Date?
    var details: String
}

struct Vacation: Identifiable, Hashable, Codable {
    let id: String
    var title: String
    var startDate: Date?
    var endDate: Date?
    var details: String
    var photo: Data?
}

struct CustomBirthday: Identifiable, Hashable, Codable {
    let id: String
    var name: String
    var date: Date
    var emoji: String
}
