import SwiftUI

// Stemmearkivet: alle lydoptagelser af barnet samlet i én tidslinje —
// lydnoter på højdepunkter og lydsvar fra det årlige interview. Plus "Optag stemme",
// der gemmer en ny optagelse som et højdepunkt med lydnote.
struct VoiceArchiveView: View {
    @EnvironmentObject var state: AppState
    let child: Child

    struct Clip: Identifiable {
        enum Source { case highlight(String), interview(String) }
        let id: String
        let title: String
        let subtitle: String
        let date: Date
        let duration: Double
        let source: Source
    }

    @State private var clips: [Clip] = []
    @State private var showRecord = false

    var body: some View {
        ScrollView {
            if clips.isEmpty {
                ContentUnavailableView {
                    Label("Ingen optagelser endnu", systemImage: "waveform")
                } description: {
                    Text("Optag \(child.name)s stemme: de første lyde, de første ord, en sang. Lydnoter på højdepunkter og svar fra det årlige interview samles også her.")
                }
                .padding(.top, 60)
            } else {
                TimelineView(items: clips, year: { Calendar.current.component(.year, from: $0.date) }) { clip in
                    ClipCard(child: child, clip: clip)
                }
                .padding(16)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Stemmearkiv")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if state.canEdit {
                    Button { showRecord = true } label: { Image(systemName: "mic.badge.plus") }
                }
            }
        }
        .sheet(isPresented: $showRecord, onDismiss: { Task { await load() } }) {
            RecordVoiceView(child: child)
        }
        .refreshable { await load() }
        .task { await load() }
        .reloadOnStoreChange { await load() }
    }

    private func load() async {
        let hKey = "highlights_\(child.id)", iKey = "interviews_\(child.id)"
        if clips.isEmpty {
            build(highlights: ScreenCache.load([Highlight].self, key: hKey) ?? [],
                  answers: ScreenCache.load([InterviewAnswer].self, key: iKey) ?? [])
        }
        guard let highlights = try? await state.store.highlights(childId: child.id),
              let answers = try? await state.store.interviews(childId: child.id) else { return }
        ScreenCache.save(highlights, key: hKey)
        ScreenCache.save(answers, key: iKey)
        build(highlights: highlights, answers: answers)
    }

    private func build(highlights: [Highlight], answers: [InterviewAnswer]) {
        var out: [Clip] = []
        for h in highlights {
            guard let d = h.audioDuration else { continue }
            out.append(Clip(id: h.id, title: h.text.isEmpty ? "Lydnote" : h.text, subtitle: "Højdepunkt",
                            date: h.date ?? h.createdAt, duration: d, source: .highlight(h.id)))
        }
        for a in answers {
            guard let d = a.audioDuration else { continue }
            out.append(Clip(id: a.id, title: Constants.interviewQuestion(a.question),
                            subtitle: "Interview · \(a.age == 1 ? "1 år" : "\(a.age) år")",
                            date: a.date, duration: d, source: .interview(a.id)))
        }
        clips = out.sorted { $0.date > $1.date }
    }
}

private struct ClipCard: View {
    @EnvironmentObject var state: AppState
    let child: Child
    let clip: VoiceArchiveView.Clip
    @StateObject private var playback = AudioPlayback()
    @State private var loading = false

    var body: some View {
        HStack(spacing: 14) {
            Button { Task { await toggle() } } label: {
                Circle().fill(Theme.rose.opacity(0.15)).frame(width: 46, height: 46)
                    .overlay(Group {
                        if loading { ProgressView() }
                        else { Image(systemName: playback.isPlaying ? "stop.fill" : "play.fill").foregroundStyle(Theme.rose) }
                    })
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 3) {
                Text(clip.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(2)
                Text("\(clip.subtitle) · \(MediaFiles.format(clip.duration))").font(.caption).foregroundStyle(Theme.muted)
                Text(ageText).font(.caption2).foregroundStyle(Theme.neutralDark)
            }
            Spacer()
        }
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.sep))
    }

    private var ageText: String {
        guard let birth = child.birthDate else { return Fmt.long(clip.date) }
        let c = Calendar.current.dateComponents([.year, .month], from: birth, to: clip.date)
        let y = c.year ?? 0, m = c.month ?? 0
        let age = y == 0 ? "\(m) mdr." : (m == 0 ? "\(y) år" : "\(y) år og \(m) mdr.")
        return "\(Fmt.long(clip.date)) · \(age)"
    }

    private func toggle() async {
        if playback.isPlaying { playback.stop(); return }
        loading = true
        defer { loading = false }
        let url: URL?
        switch clip.source {
        case .highlight(let id): url = (try? await state.store.highlightMedia(childId: child.id, id: id))?.audio
        case .interview(let id): url = (try? await state.store.interviewMedia(childId: child.id, id: id))?.audio
        }
        if let url { playback.toggle(url: url) }
    }
}

/// Hurtig optagelse: gemmes som et højdepunkt med lydnote, så den også står i tidslinjen.
struct RecordVoiceView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let child: Child
    @State private var title = ""
    @State private var date = Date()
    @State private var audio: MediaChange = .keep
    @State private var saving = false
    @State private var saveError: String?

    private static let ideas = ["Første lyde", "Første ord", "Pludren", "Latter", "En sang", "Sig dit navn", "Godnat-hilsen"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Hvad er det?") {
                    TextField("Fx Første ord: \"mor\"", text: $title)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Self.ideas, id: \.self) { s in
                                Button(s) { title = s }
                                    .font(.footnote)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(Capsule().fill(Theme.bgDark))
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                    DatePicker("Dato", selection: $date, in: ...Date(), displayedComponents: .date)
                }
                Section("Optagelse") {
                    MediaField(video: .constant(.keep), audio: $audio, showVideo: false, audioLabel: "Optag")
                }
            }
            .navigationTitle("Optag stemme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annullér") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gem") { Task { await save() } }
                        .disabled(saving || !hasAudio)
                }
            }
            .saveErrorAlert($saveError)
        }
    }

    private var hasAudio: Bool { if case .set = audio { return true } else { return false } }

    private func save() async {
        await performSave(saving: $saving, errorMessage: $saveError, dismiss: dismiss) {
            let created = try await state.store.addHighlight(childId: child.id, date: date,
                                                             text: title.trimmingCharacters(in: .whitespaces), photos: [], cover: 0, place: nil)
            try await state.store.setHighlightMedia(childId: child.id, id: created.id, video: .keep, audio: audio)
        }
    }
}
