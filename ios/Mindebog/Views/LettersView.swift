import SwiftUI

// "Breve til dig": breve til barnet, forseglet indtil en dato (typisk 18-års fødselsdagen).
// Forseglede breve vises som en lukket kuvert; indholdet vises først, når datoen er nået.
struct LettersView: View {
    @EnvironmentObject var state: AppState
    let child: Child
    @State private var letters: [Letter] = []
    @State private var showAdd = false
    @State private var editing: Letter?
    @State private var reading: Letter?

    var body: some View {
        ScrollView {
            if letters.isEmpty {
                ContentUnavailableView {
                    Label("Ingen breve endnu", systemImage: "envelope")
                } description: {
                    Text(MeChild.id == child.id ? "Her kommer de breve, din familie har skrevet til dig, når de må åbnes."
                         : "Skriv et brev til \(child.name), der først kan åbnes på 18-års fødselsdagen — eller når I vælger.")
                }
                .padding(.top, 60)
            } else {
                VStack(spacing: 12) {
                    ForEach(letters) { letter in
                        card(letter).id(letter.id)
                    }
                }
                .padding(16)
            }
        }
        .jumpsToPendingRecord()
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Breve til dig")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if state.canEdit { Button { showAdd = true } label: { Image(systemName: "plus") } }
            }
        }
        .sheet(isPresented: $showAdd, onDismiss: { Task { await load() } }) {
            LetterEditView(child: child)
        }
        .sheet(item: $editing, onDismiss: { Task { await load() } }) { letter in
            LetterEditView(child: child, editing: letter)
        }
        .sheet(item: $reading) { letter in
            LetterReadView(child: child, letter: letter)
        }
        .refreshable { await load() }
        .task { await load() }
        .reloadOnStoreChange { await load() }
    }

    private func card(_ letter: Letter) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Circle()
                .fill((letter.isSealed ? Theme.neutral : Theme.rose).opacity(0.15))
                .frame(width: 44, height: 44)
                .overlay(Image(systemName: letter.isSealed ? "envelope" : "envelope.open")
                    .foregroundStyle(letter.isSealed ? Theme.neutralDark : Theme.rose))
            VStack(alignment: .leading, spacing: 4) {
                Text(letter.title.isEmpty ? "Brev til \(child.name)" : letter.title)
                    .font(.serifTitle(16))
                    .foregroundStyle(Theme.text)
                Text("Skrevet af \(letter.author.isEmpty ? "—" : letter.author) · \(Fmt.long(letter.writtenAt))")
                    .font(.caption).foregroundStyle(Theme.muted)
                if letter.isSealed, let open = letter.openDate {
                    Label("Forseglet · åbnes \(Fmt.long(open))", systemImage: "lock")
                        .font(.footnote).foregroundStyle(Theme.neutralDark)
                } else if !letter.text.isEmpty {
                    Text(letter.text).font(.footnote).foregroundStyle(Theme.muted).lineLimit(2)
                }
                if let d = letter.videoDuration {
                    Label("Videobrev · \(MediaFiles.format(d))", systemImage: "video")
                        .font(.caption).foregroundStyle(Theme.rose)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Theme.sep))
        .contentShape(RoundedRectangle(cornerRadius: Radius.card))
        .onTapGesture { if !letter.isSealed { read(letter) } }
        .contextMenu {
            if !letter.isSealed {
                Button { read(letter) } label: { Label("Læs", systemImage: "envelope.open") }
            }
            if state.canEdit {
                Button { edit(letter) } label: { Label("Redigér", systemImage: "pencil") }
            }
        }
    }

    /// Læs: åbnes med det samme (thumb), og billedet i fuld størrelse følger, når det er hentet (#62).
    private func read(_ letter: Letter) {
        reading = letter
        guard !letter.photoLoaded else { return }
        Task {
            await CloudKitStore.withOriginals { await load() }
            if reading?.id == letter.id, let fresh = letters.first(where: { $0.id == letter.id }) { reading = fresh }
        }
    }

    /// Redigering kræver originalen (ellers ville et gem ikke kunne ændre billedet).
    private func edit(_ letter: Letter) {
        if letter.photoLoaded { editing = letter; return }
        Task {
            await CloudKitStore.withOriginals { await load() }
            editing = letters.first { $0.id == letter.id } ?? letter
        }
    }

    private func load() async {
        let cacheKey = "letters_\(child.id)"
        if letters.isEmpty, let cached = ScreenCache.load([Letter].self, key: cacheKey) { letters = cached }
        if let fresh = try? await state.store.letters(childId: child.id) {
            letters = fresh
            ScreenCache.save(fresh, key: cacheKey)
        }
    }
}

/// Et åbnet brev, læst i ro og mag.
struct LetterReadView: View {
    @EnvironmentObject var state: AppState
    let child: Child
    let letter: Letter
    @Environment(\.dismiss) private var dismiss
    @State private var loadingVideo = false
    @State private var player: VideoPlayerScreen?
    @State private var videoError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(letter.title)
                        .font(.serifTitle(24))
                    Text("Skrevet af \(letter.author) · \(Fmt.long(letter.writtenAt))")
                        .font(.footnote).foregroundStyle(Theme.muted)
                    if let d = letter.videoDuration {
                        Button {
                            Task { await playVideo() }
                        } label: {
                            HStack(spacing: 12) {
                                Circle().fill(Theme.rose.opacity(0.15)).frame(width: 44, height: 44)
                                    .overlay(Group {
                                        if loadingVideo { ProgressView() }
                                        else { Image(systemName: "play.fill").foregroundStyle(Theme.rose) }
                                    })
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Afspil videobrev").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                                    Text(MediaFiles.format(d)).font(.caption).foregroundStyle(Theme.muted)
                                }
                                Spacer()
                            }
                            .padding(12)
                            .background(Theme.card)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                            .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Theme.sep))
                        }
                        .buttonStyle(.plain)
                        .disabled(loadingVideo)
                        if let videoError {
                            Text(videoError).font(.footnote).foregroundStyle(Theme.rose)
                        }
                    }
                    if let photo = letter.listPhoto {
                        DataImage(data: photo, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.small))
                    }
                    Text(letter.text)
                        .font(.serif(17))
                        .lineSpacing(5)
                        .foregroundStyle(Theme.text)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Luk") { dismiss() } }
            }
            .fullScreenCover(item: $player) { $0 }
        }
    }

    private func playVideo() async {
        loadingVideo = true
        defer { loadingVideo = false }
        videoError = nil
        if let url = try? await state.store.letterVideo(childId: child.id, id: letter.id) {
            player = VideoPlayerScreen(url: url)
        } else {
            videoError = "Kunne ikke hente videoen. Tjek forbindelsen, og prøv igen."
        }
    }
}

/// Skriv eller redigér et brev.
struct LetterEditView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let child: Child
    var editing: Letter? = nil

    enum Opening: String, CaseIterable, Identifiable {
        case eighteen = "På 18-års dagen"
        case date = "Vælg dato"
        case now = "Med det samme"
        var id: String { rawValue }
    }

    @State private var title = ""
    @State private var text = ""
    @State private var author = ""
    @State private var opening: Opening = .eighteen
    @State private var openDate = Date()
    @State private var photo: Data?
    @State private var video: MediaChange = .keep
    @State private var saving = false
    @State private var saveError: String?
    @State private var loaded = false
    @State private var confirmDelete = false

    /// Er der tekst eller video? Et videobrev må godt stå uden tekst.
    private var hasContent: Bool {
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        switch video {
        case .keep: return editing?.videoDuration != nil
        case .remove: return false
        case .set: return true
        }
    }

    /// 18-års dagen ud fra fødselsdato — eller termin, hvis barnet er på vej.
    private var eighteenth: Date? {
        guard let base = child.birthDate ?? child.dueDate else { return nil }
        return Calendar.current.date(byAdding: .year, value: 18, to: base)
    }

    var body: some View {
        NavigationStack {
            Form {
                Group {
                Section {
                    TextField("Overskrift (fx Til dig på din 18-års dag)", text: $title)
                    TextField("Skrevet af", text: $author)
                }
                Section("Brevet") {
                    TextField("Kære \(child.name) …", text: $text, axis: .vertical)
                        .lineLimit(8...30)
                }
                Section {
                    MediaField(video: $video, audio: .constant(.keep), existingVideo: editing?.videoDuration,
                               showAudio: false, videoLabel: "Vælg videobrev",
                               loadExisting: editing.map { l in
                                   { (video: try? await state.store.letterVideo(childId: child.id, id: l.id), audio: nil) }
                               })
                } header: {
                    Text("Videobrev (valgfrit)")
                } footer: {
                    Text("Optag en hilsen i Fotos-appen og vælg den her. Maks 3 min. Videoen forsegles sammen med brevet.")
                }
                Section {
                    Picker("Åbnes", selection: $opening) {
                        ForEach(Opening.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if opening == .eighteen {
                        if let date = eighteenth {
                            LabeledContent("Dato", value: Fmt.long(date))
                        } else {
                            Text("Sæt fødsels- eller terminsdato på barnet for at bruge 18-års dagen.")
                                .font(.footnote).foregroundStyle(Theme.muted)
                        }
                    } else if opening == .date {
                        DatePicker("Dato", selection: $openDate, in: Date()..., displayedComponents: .date)
                    }
                } header: {
                    Text("Hvornår må det læses?")
                } footer: {
                    Text("Indtil datoen vises brevet som en lukket kuvert i appen.")
                }
                Section("Billede (valgfrit)") {
                    PhotoField(data: $photo)
                }
                if editing != nil {
                    Section {
                        Button("Slet brev", role: .destructive) { confirmDelete = true }
                    }
                }
                }.listRowBackground(Theme.card)
            }
            .themedList()
            .navigationTitle(editing == nil ? "Nyt brev" : "Redigér brev")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annullér") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gem") { Task { await save() } }
                        .disabled(saving || !hasContent)
                }
            }
            .saveErrorAlert($saveError)
            .confirmationDialog("Slet brevet?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Slet", role: .destructive) {
                    Task {
                        await performSave(saving: $saving, errorMessage: $saveError, dismiss: dismiss) {
                            if let id = editing?.id { try await state.store.deleteLetter(childId: child.id, id: id) }
                        }
                    }
                }
            } message: {
                Text("Brevet slettes for hele familien og kan ikke gendannes.")
            }
            .onAppear(perform: prefill)
        }
    }

    private func prefill() {
        guard !loaded else { return }
        loaded = true
        guard let l = editing else {
            let me = state.user?.name ?? ""
            author = me == "Forælder" ? "" : me
            return
        }
        title = l.title; text = l.text; author = l.author; photo = l.photo
        if let open = l.openDate {
            if let e = eighteenth, Calendar.current.isDate(open, inSameDayAs: e) { opening = .eighteen }
            else { opening = .date; openDate = open }
        } else {
            opening = .now
        }
    }

    private func save() async {
        let open: Date?
        switch opening {
        case .eighteen: open = eighteenth
        case .date: open = openDate
        case .now: open = nil
        }
        var letter = editing ?? Letter(id: newId("letter"), title: "", text: "", author: "",
                                       writtenAt: Date(), openDate: nil)
        letter.title = title; letter.text = text; letter.author = author
        letter.openDate = open; letter.photo = photo
        let (store, childId, final, video, isNew) = (state.store, child.id, letter, video, editing == nil)
        let work: () async throws -> Void = {
            if isNew {
                try await store.addLetter(childId: childId, final)
            } else {
                try await store.updateLetter(childId: childId, final)
            }
            try await store.setLetterVideo(childId: childId, id: final.id, video: video)
        }
        // Et videobrev kan tage tid at uploade: luk med det samme og gem i baggrunden.
        if case .set = video {
            performSaveInBackground(label: "brevet", dismiss: dismiss, work)
        } else {
            await performSave(saving: $saving, errorMessage: $saveError, dismiss: dismiss, work)
        }
    }
}
