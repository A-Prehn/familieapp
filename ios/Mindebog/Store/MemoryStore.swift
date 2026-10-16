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
    private var personsByFamily: [String: [Person]] = [:]

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

    func canEdit(familyId: String) async -> Bool { true }

    func setMemberName(familyId: String, userId: String, name: String) async throws {
        users[userId]?.name = name.trimmingCharacters(in: .whitespaces)
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
            milestonesByChild[child.id, default: [:]]["birth_date"] = MilestoneEntry(value: Fmt.iso(birthDate))
        }
        if let dueDate {
            milestonesByChild[child.id, default: [:]]["due_date"] = MilestoneEntry(value: Fmt.iso(dueDate))
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
            let photos = milestonesByChild[child.id]?[key]?.photos ?? PhotoSet()
            milestonesByChild[child.id, default: [:]][key] = MilestoneEntry(value: Fmt.iso(date), photos: photos)
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

    func setMilestone(childId: String, key: String, value: String?, photos: PhotoSet) async throws {
        let trimmed = value?.trimmingCharacters(in: .whitespaces)
        let cleanValue = (trimmed?.isEmpty ?? true) ? nil : trimmed
        if cleanValue == nil && photos.isEmpty {
            milestonesByChild[childId]?[key] = nil
        } else {
            milestonesByChild[childId, default: [:]][key] = MilestoneEntry(value: cleanValue, photos: photos)
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
                  photos: PhotoSet, place: Place?) async throws -> FamilyEvent {
        let event = FamilyEvent(id: newId("ev"),
                                title: title.trimmingCharacters(in: .whitespaces),
                                date: date, details: details.trimmingCharacters(in: .whitespaces),
                                photos: photos, place: place)
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
                     details: String, photos: PhotoSet, place: Place?) async throws -> Vacation {
        let vacation = Vacation(id: newId("vac"),
                                title: title.trimmingCharacters(in: .whitespaces),
                                startDate: start, endDate: end,
                                details: details.trimmingCharacters(in: .whitespaces),
                                photos: photos, place: place)
        vacationsByFamily[familyId, default: []].append(vacation)
        return vacation
    }

    func memorySummaries(familyId: String) async throws -> [MemorySummary] {
        var out: [MemorySummary] = []
        for child in childrenById.values where child.familyId == familyId {
            for h in highlightsByChild[child.id] ?? [] {
                out.append(MemorySummary(id: h.id, kind: .highlight, childId: child.id,
                                         date: h.date, createdAt: h.createdAt, text: h.text))
            }
            for d in diaryByChild[child.id] ?? [] {
                out.append(MemorySummary(id: d.id, kind: .diary, childId: child.id,
                                         date: d.date, createdAt: d.createdAt, text: d.text))
            }
        }
        for e in eventsByFamily[familyId] ?? [] {
            out.append(MemorySummary(id: e.id, kind: .event, childId: nil,
                                     date: e.date, createdAt: e.date ?? .distantPast, text: e.title))
        }
        for v in vacationsByFamily[familyId] ?? [] {
            out.append(MemorySummary(id: v.id, kind: .vacation, childId: nil,
                                     date: v.startDate, createdAt: v.startDate ?? .distantPast, text: v.title))
        }
        return out
    }

    func coverPhoto(familyId: String, memory: MemorySummary) async throws -> Data? {
        switch memory.kind {
        case .highlight:
            return highlightsByChild.values.joined().first { $0.id == memory.id }?.photos.first
        case .diary:
            return diaryByChild.values.joined().first { $0.id == memory.id }?.photo
        case .event:
            return eventsByFamily[familyId]?.first { $0.id == memory.id }?.photo
        case .vacation:
            return vacationsByFamily[familyId]?.first { $0.id == memory.id }?.photo
        }
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

    // MARK: Video/lyd på højdepunkter
    private var mediaByHighlight: [String: (video: URL?, audio: URL?)] = [:]

    func setHighlightMedia(childId: String, id: String, video: MediaChange, audio: MediaChange) async throws {
        guard let i = highlightsByChild[childId]?.firstIndex(where: { $0.id == id }) else { throw StoreError.notFound }
        var media = mediaByHighlight[id] ?? (nil, nil)
        switch video {
        case .keep: break
        case .remove: media.video = nil; highlightsByChild[childId]?[i].videoDuration = nil
        case .set(let url, let d): media.video = url; highlightsByChild[childId]?[i].videoDuration = d
        }
        switch audio {
        case .keep: break
        case .remove: media.audio = nil; highlightsByChild[childId]?[i].audioDuration = nil
        case .set(let url, let d): media.audio = url; highlightsByChild[childId]?[i].audioDuration = d
        }
        mediaByHighlight[id] = media
    }

    func highlightMedia(childId: String, id: String) async throws -> (video: URL?, audio: URL?) {
        mediaByHighlight[id] ?? (nil, nil)
    }

    // MARK: Vækst
    private var measurementsByChild: [String: [Measurement]] = [:]

    func measurements(childId: String) async throws -> [Measurement] {
        (measurementsByChild[childId] ?? []).sorted { $0.date < $1.date }
    }

    func saveMeasurement(childId: String, _ measurement: Measurement) async throws {
        var list = measurementsByChild[childId] ?? []
        if let i = list.firstIndex(where: { $0.id == measurement.id }) { list[i] = measurement } else { list.append(measurement) }
        measurementsByChild[childId] = list
    }

    func deleteMeasurement(childId: String, id: String) async throws {
        measurementsByChild[childId]?.removeAll { $0.id == id }
    }

    // MARK: Breve
    private var lettersByChild: [String: [Letter]] = [:]

    func letters(childId: String) async throws -> [Letter] {
        (lettersByChild[childId] ?? []).sorted { $0.writtenAt > $1.writtenAt }
    }

    func addLetter(childId: String, _ letter: Letter) async throws {
        lettersByChild[childId, default: []].append(letter)
    }

    func updateLetter(childId: String, _ letter: Letter) async throws {
        guard let i = lettersByChild[childId]?.firstIndex(where: { $0.id == letter.id }) else { throw StoreError.notFound }
        lettersByChild[childId]?[i] = letter
    }

    func deleteLetter(childId: String, id: String) async throws {
        lettersByChild[childId]?.removeAll { $0.id == id }
    }

    // MARK: Redigér / slet
    func updateHighlight(childId: String, _ highlight: Highlight) async throws {
        guard let i = highlightsByChild[childId]?.firstIndex(where: { $0.id == highlight.id }) else { throw StoreError.notFound }
        highlightsByChild[childId]?[i] = highlight
    }

    func deleteHighlight(childId: String, id: String) async throws {
        highlightsByChild[childId]?.removeAll { $0.id == id }
    }

    func updateDiary(childId: String, _ entry: DiaryEntry) async throws {
        guard let i = diaryByChild[childId]?.firstIndex(where: { $0.id == entry.id }) else { throw StoreError.notFound }
        diaryByChild[childId]?[i] = entry
    }

    func deleteDiary(childId: String, id: String) async throws {
        diaryByChild[childId]?.removeAll { $0.id == id }
    }

    func updateGalleryItem(childId: String, _ item: GalleryItem) async throws {
        for kind in [GalleryKind.belly, .monthly, .drawings] {
            if let i = galleryByChild[childId]?[kind]?.firstIndex(where: { $0.id == item.id }) {
                galleryByChild[childId]?[kind]?[i] = item
                return
            }
        }
        throw StoreError.notFound
    }

    func deleteGalleryItem(childId: String, id: String) async throws {
        for kind in [GalleryKind.belly, .monthly, .drawings] {
            galleryByChild[childId]?[kind]?.removeAll { $0.id == id }
        }
    }

    func updateBirthday(familyId: String, _ birthday: CustomBirthday) async throws {
        guard let i = birthdaysByFamily[familyId]?.firstIndex(where: { $0.id == birthday.id }) else { throw StoreError.notFound }
        birthdaysByFamily[familyId]?[i] = birthday
    }

    func deleteBirthday(familyId: String, id: String) async throws {
        birthdaysByFamily[familyId]?.removeAll { $0.id == id }
    }


    // MARK: Videobrev, interview, traditioner (kun i hukommelsen)
    private var letterVideos: [String: URL] = [:]
    private var interviewsByChild: [String: [InterviewAnswer]] = [:]
    private var mediaByRecord: [String: (video: URL?, audio: URL?)] = [:]
    private var traditionsByFamily: [String: [Tradition]] = [:]

    func setLetterVideo(childId: String, id: String, video: MediaChange) async throws {
        if case .set(let url, let d) = video {
            letterVideos[id] = url
            if let i = lettersByChild[childId]?.firstIndex(where: { $0.id == id }) { lettersByChild[childId]?[i].videoDuration = d }
        } else if case .remove = video {
            letterVideos[id] = nil
            if let i = lettersByChild[childId]?.firstIndex(where: { $0.id == id }) { lettersByChild[childId]?[i].videoDuration = nil }
        }
    }
    func letterVideo(childId: String, id: String) async throws -> URL? { letterVideos[id] }

    func interviews(childId: String) async throws -> [InterviewAnswer] { interviewsByChild[childId] ?? [] }
    func saveInterviewAnswer(childId: String, _ answer: InterviewAnswer, audio: MediaChange, video: MediaChange) async throws {
        var a = answer
        var m = mediaByRecord[answer.id] ?? (nil, nil)
        if case .set(let url, let d) = audio { m.audio = url; a.audioDuration = d } else if case .remove = audio { m.audio = nil; a.audioDuration = nil }
        if case .set(let url, let d) = video { m.video = url; a.videoDuration = d } else if case .remove = video { m.video = nil; a.videoDuration = nil }
        mediaByRecord[answer.id] = m
        var list = interviewsByChild[childId] ?? []
        if let i = list.firstIndex(where: { $0.id == a.id }) { list[i] = a } else { list.append(a) }
        interviewsByChild[childId] = list
    }
    func deleteInterviewAnswer(childId: String, id: String) async throws { interviewsByChild[childId]?.removeAll { $0.id == id } }
    func interviewMedia(childId: String, id: String) async throws -> (video: URL?, audio: URL?) { mediaByRecord[id] ?? (nil, nil) }

    func traditions(familyId: String) async throws -> [Tradition] { traditionsByFamily[familyId] ?? [] }
    func saveTradition(familyId: String, _ tradition: Tradition, audio: MediaChange) async throws {
        var t = tradition
        var m = mediaByRecord[t.id] ?? (nil, nil)
        if case .set(let url, let d) = audio { m.audio = url; t.audioDuration = d } else if case .remove = audio { m.audio = nil; t.audioDuration = nil }
        mediaByRecord[t.id] = m
        var list = traditionsByFamily[familyId] ?? []
        if let i = list.firstIndex(where: { $0.id == t.id }) { list[i] = t } else { list.append(t) }
        traditionsByFamily[familyId] = list
    }
    func deleteTradition(familyId: String, id: String) async throws { traditionsByFamily[familyId]?.removeAll { $0.id == id } }
    func traditionAudio(familyId: String, id: String) async throws -> URL? { mediaByRecord[id]?.audio }
    // MARK: Familietræ
    func persons(familyId: String) async throws -> [Person] {
        personsByFamily[familyId] ?? []
    }

    func savePerson(familyId: String, _ person: Person) async throws {
        var list = personsByFamily[familyId] ?? []
        if let i = list.firstIndex(where: { $0.id == person.id }) { list[i] = person } else { list.append(person) }
        personsByFamily[familyId] = list
    }

    func deletePerson(familyId: String, id: String) async throws {
        personsByFamily[familyId]?.removeAll { $0.id == id }
    }
}
