import SwiftUI
import AVFoundation

// Det årlige interview: de samme 10 spørgsmål hver fødselsdag, besvaret som tekst, lyd eller video.
// Fanen "I år" udfylder ét års svar; "Gennem årene" afspiller alle svar på ét spørgsmål i rækkefølge.
struct InterviewView: View {
    @EnvironmentObject var state: AppState
    let child: Child
    /// Alderen, der skal være valgt (fx fra fødselsdagspåmindelsen); ellers barnets alder nu.
    var initialAge: Int? = nil

    enum Mode: String, CaseIterable, Identifiable {
        case year = "Pr. år"
        case question = "Gennem årene"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .year
    @State private var answers: [InterviewAnswer] = []
    @State private var age: Int = 0
    @State private var editing: EditTarget?
    @State private var selectedQuestion = Constants.interviewQuestions[0].key
    @State private var loaded = false
    @State private var playing: InterviewPlaybackView?

    struct EditTarget: Identifiable {
        let question: String
        let age: Int
        let existing: InterviewAnswer?
        var id: String { "\(question)_\(age)" }
    }

    /// Barnets alder i hele år lige nu.
    private var currentAge: Int {
        guard let birth = child.birthDate else { return 0 }
        return max(0, Calendar.current.dateComponents([.year], from: birth, to: Date()).year ?? 0)
    }
    private var ages: [Int] { Array(0...max(currentAge, answers.map(\.age).max() ?? 0)) }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(16)

            List {
                if mode == .year { yearSection } else { questionSection }
            }
            .scrollContentBackground(.hidden)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Det årlige interview")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing, onDismiss: { Task { await load() } }) { target in
            InterviewAnswerEditView(child: child, question: target.question, age: target.age, existing: target.existing)
        }
        .fullScreenCover(item: $playing) { $0 }
        .refreshable { await load() }
        .reloadOnStoreChange { await load() }
        .task {
            if !loaded { loaded = true; age = initialAge ?? currentAge }
            await load()
        }
    }

    // MARK: Pr. år

    @ViewBuilder
    private var yearSection: some View {
        Section {
            Picker("Alder", selection: $age) {
                ForEach(ages, id: \.self) { Text($0 == 1 ? "1 år" : "\($0) år").tag($0) }
            }
            // Alle svar for den valgte alder, i spørgsmålenes rækkefølge.
            let forAge = Constants.interviewQuestions.compactMap { q in
                best(q.key, age).flatMap { $0.hasAnswer ? $0 : nil }
            }
            if !forAge.isEmpty {
                Button {
                    playing = InterviewPlaybackView(child: child, title: "\(child.name), \(age == 1 ? "1 år" : "\(age) år")",
                                                    answers: forAge, headline: .question)
                } label: {
                    Label("Afspil alle svar (\(forAge.count))", systemImage: "play.circle.fill")
                        .font(.subheadline.weight(.semibold))
                }
            }
        } footer: {
            Text("Stil de samme spørgsmål hvert år omkring fødselsdagen. Svar med tekst, en lydoptagelse eller en lille video — så kan I senere høre \(child.name) vokse.")
        }
        Section {
            ForEach(Constants.interviewQuestions) { q in
                let a = best(q.key, age)
                Button {
                    if state.canEdit || a != nil { editing = EditTarget(question: q.key, age: age, existing: a) }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: a?.hasAnswer == true ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(a?.hasAnswer == true ? Theme.green : Theme.muted)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(q.text).font(.subheadline.weight(.medium)).foregroundStyle(Theme.text)
                            if let a, a.hasAnswer {
                                HStack(spacing: 8) {
                                    if !a.text.isEmpty { Text(a.text).lineLimit(1) }
                                    if let d = a.audioDuration { Label(MediaFiles.format(d), systemImage: "waveform") }
                                    if let d = a.videoDuration { Label(MediaFiles.format(d), systemImage: "video") }
                                }
                                .font(.caption).foregroundStyle(Theme.muted)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
            }
        } header: {
            Text(age == 1 ? "1 år" : "\(age) år")
        }
    }

    // MARK: Gennem årene

    @ViewBuilder
    private var questionSection: some View {
        Section {
            Picker("Spørgsmål", selection: $selectedQuestion) {
                ForEach(Constants.interviewQuestions) { Text($0.text).tag($0.key) }
            }
            .pickerStyle(.menu)
        }
        // Ét svar pr. alder (det bedste), i rækkefølge efter alder.
        let list = Set(answers.filter { $0.question == selectedQuestion }.map(\.age)).sorted()
            .compactMap { best(selectedQuestion, $0) }.filter(\.hasAnswer)
        if list.isEmpty {
            Section {
                Text("Ingen svar på det spørgsmål endnu.").font(.footnote).foregroundStyle(Theme.muted)
            }
        } else {
            Section {
                ForEach(list) { a in
                    AnswerRow(child: child, answer: a) {
                        editing = EditTarget(question: a.question, age: a.age, existing: a)
                    }
                }
            } header: {
                HStack {
                    Text(Constants.interviewQuestion(selectedQuestion))
                    Spacer()
                    Button {
                        playing = InterviewPlaybackView(child: child, title: Constants.interviewQuestion(selectedQuestion),
                                                        answers: list, headline: .age)
                    } label: {
                        Label("Afspil alle", systemImage: "play.circle")
                    }
                    .font(.caption.weight(.semibold))
                    .textCase(nil)
                }
            } footer: {
                Text("Svarene står i rækkefølge efter alder. \"Afspil alle\" viser dem efter hinanden — video, lyd og tekst.")
            }
        }
    }

    /// Det bedste svar for et spørgsmål og en alder: med video/lyd frem for kun tekst, ellers det nyeste.
    /// (Der kan være flere, hvis et gem fejlede halvvejs i en tidligere version.)
    private func best(_ question: String, _ age: Int) -> InterviewAnswer? {
        answers.filter { $0.question == question && $0.age == age }.max { score($0) < score($1) }
    }

    private func score(_ a: InterviewAnswer) -> (Int, Date) {
        ((a.videoDuration != nil ? 4 : 0) + (a.audioDuration != nil ? 2 : 0) + (a.text.isEmpty ? 0 : 1), a.date)
    }

    private func load() async {
        let cacheKey = "interviews_\(child.id)"
        if answers.isEmpty, let cached = ScreenCache.load([InterviewAnswer].self, key: cacheKey) { answers = cached }
        guard let fresh = try? await state.store.interviews(childId: child.id) else { return }
        answers = fresh
        ScreenCache.save(fresh, key: cacheKey)
        await removeEmptyDuplicates()
        // Er interviewet for en alder påbegyndt, skal opfølgningspåmindelsen ikke komme.
        for age in Set(answers.filter(\.hasAnswer).map(\.age)) {
            Reminders.markInterviewStarted(childId: child.id, age: age)
        }
    }

    /// Rydder op efter et halvt gemt svar: tomme dubletter slettes, når der findes et svar med indhold.
    /// Svar med indhold slettes aldrig — de vises bare ikke, hvis der er et bedre.
    private func removeEmptyDuplicates() async {
        guard state.canEdit else { return }
        let groups = Dictionary(grouping: answers) { "\($0.question)_\($0.age)" }
        var removed: Set<String> = []
        for (_, group) in groups where group.count > 1 && group.contains(where: \.hasAnswer) {
            for empty in group where !empty.hasAnswer {
                if (try? await state.store.deleteInterviewAnswer(childId: child.id, id: empty.id)) != nil {
                    removed.insert(empty.id)
                }
            }
        }
        if !removed.isEmpty { answers.removeAll { removed.contains($0.id) } }
    }
}

/// Ét svar i "Gennem årene": alder, tekst og afspil-knapper.
private struct AnswerRow: View {
    @EnvironmentObject var state: AppState
    let child: Child
    let answer: InterviewAnswer
    var onEdit: () -> Void
    @StateObject private var playback = AudioPlayback()
    @State private var loading = false
    @State private var player: VideoPlayerScreen?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(answer.age == 1 ? "1 år" : "\(answer.age) år")
                .font(.serifTitle(15)).foregroundStyle(Theme.neutralDark)
                .frame(width: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                if !answer.text.isEmpty {
                    Text(answer.text).font(.subheadline).foregroundStyle(Theme.text)
                }
                HStack(spacing: 14) {
                    if let d = answer.audioDuration {
                        Button { Task { await playAudio() } } label: {
                            Label(playback.isPlaying ? "Stop" : "Lyd \(MediaFiles.format(d))",
                                  systemImage: playback.isPlaying ? "stop.fill" : "play.fill")
                        }
                    }
                    if let d = answer.videoDuration {
                        Button { Task { await playVideo() } } label: {
                            Label("Video \(MediaFiles.format(d))", systemImage: "video")
                        }
                    }
                    if loading { ProgressView().controlSize(.small) }
                }
                .font(.caption.weight(.medium))
                .buttonStyle(.borderless)
                Text(Fmt.long(answer.date)).font(.caption2).foregroundStyle(Theme.muted)
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture { if state.canEdit { onEdit() } }
        .fullScreenCover(item: $player) { $0 }
    }

    private func playAudio() async {
        if playback.isPlaying { playback.stop(); return }
        loading = true
        defer { loading = false }
        if let url = (try? await state.store.interviewMedia(childId: child.id, id: answer.id))?.audio {
            playback.toggle(url: url)
        }
    }

    private func playVideo() async {
        loading = true
        defer { loading = false }
        if let url = (try? await state.store.interviewMedia(childId: child.id, id: answer.id))?.video {
            player = VideoPlayerScreen(url: url)
        }
    }
}

/// Besvar ét spørgsmål for ét år: tekst, lydoptagelse og/eller video.
struct InterviewAnswerEditView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let child: Child
    let question: String
    let age: Int
    let existing: InterviewAnswer?

    @State private var text = ""
    @State private var audio: MediaChange = .keep
    @State private var video: MediaChange = .keep
    @State private var saving = false
    @State private var saveError: String?
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Group {
                Section {
                    Text(Constants.interviewQuestion(question))
                        .font(.serifTitle(18)).foregroundStyle(Theme.text)
                    Text(age == 1 ? "\(child.name), 1 år" : "\(child.name), \(age) år")
                        .font(.footnote).foregroundStyle(Theme.muted)
                }
                Section("Svar") {
                    TextField("Skriv svaret, hvis I vil", text: $text, axis: .vertical)
                        .lineLimit(2...6)
                }
                Section {
                    MediaField(video: $video, audio: $audio,
                               existingVideo: existing?.videoDuration, existingAudio: existing?.audioDuration,
                               videoLabel: "Vælg video", audioLabel: "Optag svaret",
                               loadExisting: existing.map { a in
                                   { (try? await state.store.interviewMedia(childId: child.id, id: a.id)) ?? (nil, nil) }
                               })
                } header: {
                    Text("Lyd og video")
                } footer: {
                    Text("Det sjoveste er at høre stemmen. Optag lyd eller video direkte her, eller vælg en video fra Fotos. Tryk på en gemt video for at se den.")
                }
                if existing != nil && state.canEdit {
                    Section {
                        Button("Slet svaret", role: .destructive) { confirmDelete = true }
                    }
                }
                }.listRowBackground(Theme.card)
            }
            .themedList()
            .navigationTitle("Svar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annullér") { dismiss() } }
                if state.canEdit {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Gem") { Task { await save() } }.disabled(saving)
                    }
                }
            }
            .saveErrorAlert($saveError)
            .confirmationDialog("Slet svaret?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Slet", role: .destructive) {
                    Task {
                        await performSave(saving: $saving, errorMessage: $saveError, dismiss: dismiss) {
                            if let id = existing?.id { try await state.store.deleteInterviewAnswer(childId: child.id, id: id) }
                        }
                    }
                }
            }
            .onAppear { text = existing?.text ?? "" }
        }
    }

    private func save() async {
        // Fast id pr. spørgsmål og alder: gemmer man igen efter en fejl, opdateres det samme svar
        // i stedet for at der opstår et nyt ved siden af.
        var answer = existing ?? InterviewAnswer(id: "iv_\(question)_\(age)", age: age, question: question)
        answer.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if existing == nil { answer.date = Date() }
        let (store, childId, final, audio, video) = (state.store, child.id, answer, audio, video)
        // Ny video/lyd kan tage tid at uploade: luk med det samme og gem i baggrunden.
        if hasNewMedia {
            performSaveInBackground(label: "svaret", dismiss: dismiss) {
                try await store.saveInterviewAnswer(childId: childId, final, audio: audio, video: video)
            }
        } else {
            await performSave(saving: $saving, errorMessage: $saveError, dismiss: dismiss) {
                try await store.saveInterviewAnswer(childId: childId, final, audio: audio, video: video)
            }
        }
    }

    private var hasNewMedia: Bool {
        if case .set = video { return true }
        if case .set = audio { return true }
        return false
    }
}
