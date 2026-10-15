import Foundation

// Datamodeller — spejler web-prototypens domæne. Generisk/multi-tenant.

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
    var symbol: String {
        switch self {
        case .girl: return "figure.child"
        case .boy: return "figure.child"
        case .unspecified: return "figure.child"
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
    var createdAt: Date
}

struct FamilyEvent: Identifiable, Hashable, Codable {
    let id: String
    var title: String
    var date: Date?
    var details: String
}
