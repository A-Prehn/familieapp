import Foundation

// In-memory implementering til build, preview og simulator (uden CloudKit).
// Data nulstilles når appen lukkes — persistens kommer med CloudKitStore.
actor MemoryStore: Store {
    private var users: [String: AppUser] = [:]
    private var families: [String: Family] = [:]
    private var childrenById: [String: Child] = [:]
    private var invites: [String: String] = [:]   // kode -> familyId

    private var highlightsByChild: [String: [Highlight]] = [:]
    private var milestonesByChild: [String: [String: MilestoneEntry]] = [:]
    private var answersByChild: [String: [String: String]] = [:]
    private var diaryByChild: [String: [DiaryEntry]] = [:]
    private var galleryByChild: [String: [GalleryKind: [GalleryItem]]] = [:]

    private var eventsByFamily: [String: [FamilyEvent]] = [:]
    private var vacationsByFamily: [String: [Vacation]] = [:]
    private var birthdaysByFamily: [String: [CustomBirthday]] = [:]

    // MARK: Auth
    func signIn(name: String) async throws -> AppUser {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let user = AppUser(id: newId("user"), name: trimmed.isEmpty ? "Forælder" : trimmed)
        users[user.id] = user
        return user
    }

    func user(id: String) async throws -> AppUser? { users[id] }

    // MARK: Familie
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

    // MARK: Børn
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
        // Som på websitet: fødsels-/terminsdato ligger også i milepælene.
        if let birthDate {
            milestonesByChild[child.id, default: [:]]["birth_date"] = MilestoneEntry(value: Fmt.iso(birthDate), photo: nil)
        }
        if let dueDate {
            milestonesByChild[child.id, default: [:]]["due_date"] = MilestoneEntry(value: Fmt.iso(dueDate), photo: nil)
        }
        return child
    }

    func updateChild(_ child: Child) async throws -> Child {
        guard childrenById[child.id] != nil else { throw StoreError.notFound }
        var updated = child
        updated.name = child.name.trimmingCharacters(in: .whitespaces)
        childrenById[child.id] = updated
        // Bevar et evt. billede på milepælen.
        for (key, date) in [("birth_date", child.birthDate), ("due_date", child.dueDate)] {
            guard let date else { continue }
            let photo = milestonesByChild[child.id]?[key]?.photo
            milestonesByChild[child.id, default: [:]][key] = MilestoneEntry(value: Fmt.iso(date), photo: photo)
        }
        return updated
    }

    // MARK: Højdepunkter
    func highlights(childId: String) async throws -> [Highlight] {
        (highlightsByChild[childId] ?? []).sorted {
            ($0.date ?? $0.createdAt) > ($1.date ?? $1.createdAt)
        }
    }

    func addHighlight(childId: String, date: Date?, text: String, photos: [Data]) async throws -> Highlight {
        let highlight = Highlight(id: newId("hl"), date: date,
                                  text: text.trimmingCharacters(in: .whitespaces),
                                  photos: photos, createdAt: Date())
        highlightsByChild[childId, default: []].append(highlight)
        return highlight
    }

    // MARK: Milepæle
    func milestones(childId: String) async throws -> [String: MilestoneEntry] {
        milestonesByChild[childId] ?? [:]
    }

    func setMilestone(childId: String, key: String, value: String?, photo: Data?) async throws {
        let trimmed = value?.trimmingCharacters(in: .whitespaces)
        let cleanValue = (trimmed?.isEmpty ?? true) ? nil : trimmed
        if cleanValue == nil && photo == nil {
            milestonesByChild[childId]?[key] = nil
        } else {
            milestonesByChild[childId, default: [:]][key] = MilestoneEntry(value: cleanValue, photo: photo)
        }
    }

    // MARK: Om dig
    func answers(childId: String) async throws -> [String: String] {
        answersByChild[childId] ?? [:]
    }

    func setAnswer(childId: String, question: String, answer: String) async throws {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            answersByChild[childId]?[question] = nil
        } else {
            answersByChild[childId, default: [:]][question] = trimmed
        }
    }

    // MARK: Dagbog
    func diary(childId: String) async throws -> [DiaryEntry] {
        (diaryByChild[childId] ?? []).sorted {
            ($0.date ?? $0.createdAt) > ($1.date ?? $1.createdAt)
        }
    }

    func addDiary(childId: String, date: Date?, text: String, photo: Data?) async throws -> DiaryEntry {
        let entry = DiaryEntry(id: newId("diary"), date: date,
                               text: text.trimmingCharacters(in: .whitespaces),
                               photo: photo, createdAt: Date())
        diaryByChild[childId, default: []].append(entry)
        return entry
    }

    // MARK: Gallerier
    func gallery(childId: String, kind: GalleryKind) async throws -> [GalleryItem] {
        (galleryByChild[childId]?[kind] ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    func addGalleryItem(childId: String, kind: GalleryKind, caption: String, photo: Data?) async throws -> GalleryItem {
        let item = GalleryItem(id: newId("gal"),
                               caption: caption.trimmingCharacters(in: .whitespaces),
                               photo: photo, createdAt: Date())
        galleryByChild[childId, default: [:]][kind, default: []].append(item)
        return item
    }

    // MARK: Familie-indhold
    func events(familyId: String) async throws -> [FamilyEvent] {
        (eventsByFamily[familyId] ?? []).sorted {
            ($0.date ?? .distantPast) > ($1.date ?? .distantPast)
        }
    }

    func addEvent(familyId: String, title: String, date: Date?, details: String,
                  photo: Data?, place: Place?) async throws -> FamilyEvent {
        let event = FamilyEvent(id: newId("ev"),
                                title: title.trimmingCharacters(in: .whitespaces),
                                date: date, details: details.trimmingCharacters(in: .whitespaces),
                                photo: photo, place: place)
        eventsByFamily[familyId, default: []].append(event)
        return event
    }

    func updateEvent(familyId: String, _ event: FamilyEvent) async throws -> FamilyEvent {
        guard let index = eventsByFamily[familyId]?.firstIndex(where: { $0.id == event.id }) else { throw StoreError.notFound }
        eventsByFamily[familyId]?[index] = event
        return event
    }

    func deleteEvent(familyId: String, id: String) async throws {
        eventsByFamily[familyId]?.removeAll { $0.id == id }
    }

    func updateVacation(familyId: String, _ vacation: Vacation) async throws -> Vacation {
        guard let index = vacationsByFamily[familyId]?.firstIndex(where: { $0.id == vacation.id }) else { throw StoreError.notFound }
        vacationsByFamily[familyId]?[index] = vacation
        return vacation
    }

    func deleteVacation(familyId: String, id: String) async throws {
        vacationsByFamily[familyId]?.removeAll { $0.id == id }
    }

    func vacations(familyId: String) async throws -> [Vacation] {
        (vacationsByFamily[familyId] ?? []).sorted {
            ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast)
        }
    }

    func addVacation(familyId: String, title: String, start: Date?, end: Date?,
                     details: String, photo: Data?, place: Place?) async throws -> Vacation {
        let vacation = Vacation(id: newId("vac"),
                                title: title.trimmingCharacters(in: .whitespaces),
                                startDate: start, endDate: end,
                                details: details.trimmingCharacters(in: .whitespaces),
                                photo: photo, place: place)
        vacationsByFamily[familyId, default: []].append(vacation)
        return vacation
    }

    func birthdays(familyId: String) async throws -> [CustomBirthday] {
        birthdaysByFamily[familyId] ?? []
    }

    func addBirthday(familyId: String, name: String, date: Date, emoji: String) async throws -> CustomBirthday {
        let trimmedEmoji = emoji.trimmingCharacters(in: .whitespaces)
        let birthday = CustomBirthday(id: newId("bday"),
                                      name: name.trimmingCharacters(in: .whitespaces),
                                      date: date,
                                      emoji: trimmedEmoji.isEmpty ? "🎂" : trimmedEmoji)
        birthdaysByFamily[familyId, default: []].append(birthday)
        return birthday
    }
}
