import Foundation

// In-memory implementering til build, preview og simulator (uden CloudKit).
// Data gemmes i UserDefaults så det overlever genstart under test.
actor MemoryStore: Store {
    private var users: [String: AppUser] = [:]
    private var families: [String: Family] = [:]
    private var childrenById: [String: Child] = [:]
    private var highlightsByChild: [String: [Highlight]] = [:]
    private var eventsByFamily: [String: [FamilyEvent]] = [:]
    private var invites: [String: String] = [:]   // kode -> familyId

    func signIn(name: String) async throws -> AppUser {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let user = AppUser(id: newId("user"), name: trimmed.isEmpty ? "Forælder" : trimmed)
        users[user.id] = user
        return user
    }

    func user(id: String) async throws -> AppUser? { users[id] }

    func families(for userId: String) async throws -> [Family] {
        families.values.filter { $0.memberIds.contains(userId) }
    }

    func createFamily(userId: String, name: String) async throws -> Family {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let family = Family(id: newId("family"),
                            name: trimmed.isEmpty ? "Vores familie" : trimmed,
                            ownerId: userId, memberIds: [userId])
        families[family.id] = family
        return family
    }

    func members(familyId: String) async throws -> [AppUser] {
        guard let family = families[familyId] else { return [] }
        return family.memberIds.compactMap { users[$0] }
    }

    func createInvite(userId: String, familyId: String) async throws -> String {
        let code = String(UUID().uuidString.prefix(6)).uppercased()
        invites[code] = familyId
        return code
    }

    func acceptInvite(userId: String, code: String) async throws -> Family {
        let key = code.trimmingCharacters(in: .whitespaces).uppercased()
        guard let familyId = invites[key], var family = families[familyId] else {
            throw StoreError.invalidInvite
        }
        if !family.memberIds.contains(userId) { family.memberIds.append(userId) }
        families[familyId] = family
        return family
    }

    func children(familyId: String) async throws -> [Child] {
        childrenById.values
            .filter { $0.familyId == familyId }
            .sorted { $0.name < $1.name }
    }

    func createChild(familyId: String, name: String, gender: Gender,
                     birthDate: Date?, dueDate: Date?) async throws -> Child {
        let child = Child(id: newId("child"), familyId: familyId,
                          name: name.trimmingCharacters(in: .whitespaces),
                          birthDate: birthDate, dueDate: dueDate, gender: gender)
        childrenById[child.id] = child
        return child
    }

    func highlights(childId: String) async throws -> [Highlight] {
        (highlightsByChild[childId] ?? []).sorted {
            ($0.date ?? $0.createdAt) > ($1.date ?? $1.createdAt)
        }
    }

    func addHighlight(childId: String, date: Date?, text: String) async throws -> Highlight {
        let h = Highlight(id: newId("hl"), date: date,
                          text: text.trimmingCharacters(in: .whitespaces), createdAt: Date())
        highlightsByChild[childId, default: []].append(h)
        return h
    }

    func events(familyId: String) async throws -> [FamilyEvent] {
        (eventsByFamily[familyId] ?? []).sorted {
            ($0.date ?? .distantPast) > ($1.date ?? .distantPast)
        }
    }

    func addEvent(familyId: String, title: String, date: Date?, details: String) async throws -> FamilyEvent {
        let e = FamilyEvent(id: newId("ev"),
                            title: title.trimmingCharacters(in: .whitespaces),
                            date: date, details: details.trimmingCharacters(in: .whitespaces))
        eventsByFamily[familyId, default: []].append(e)
        return e
    }
}
