import SwiftUI

struct HighlightsView: View {
    @EnvironmentObject var state: AppState
    @Namespace private var zoomNS   // zoom-overgang til fuld skærm (iOS 18)
    let child: Child
    @State private var items: [Highlight] = []
    @State private var showAdd = false
    @State private var editing: Highlight?
    @State private var lightbox: LightboxState?
    @State private var loading = true
    @State private var playingVideo: VideoPlayerScreen?
    @State private var loadingMedia: String?          // highlight-id der henter medie
    @StateObject private var audioPlayback = AudioPlayback()
    @State private var playingAudioId: String?

    var body: some View {
        ScrollView {
            if items.isEmpty && loading {
                ShimmerList()
            } else if items.isEmpty {
                ContentUnavailableView("Ingen højdepunkter endnu", systemImage: "star")
                    .padding(.top, 60)
            } else {
                // Tidslinje som på websitet; uden dato bruges oprettelsesåret.
                TimelineView(items: items,
                             year: { Calendar.current.component(.year, from: $0.date ?? $0.createdAt) }) { highlight in
                    card(highlight)
                }
                .padding(16)
            }
        }
        .jumpsToPendingRecord()
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Højdepunkter")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if state.canEdit { Button { showAdd = true } label: { Image(systemName: "plus") } }
            }
        }
        .sheet(isPresented: $showAdd, onDismiss: { Task { await load() } }) {
            AddHighlightView(childId: child.id)
        }
        .sheet(item: $editing, onDismiss: { Task { await load() } }) { highlight in
            AddHighlightView(childId: child.id, editing: highlight)
        }
        .fullScreenCover(item: $lightbox) { LightboxView(state: $0).zoomTarget(id: $0.sourceId, in: zoomNS) }
        .fullScreenCover(item: $playingVideo) { $0 }
        .refreshable { await load() }
        .task { await load() }
        .reloadOnStoreChange { await load() }
    }

    // Video/lyd hentes først, når man trykker afspil.
    @ViewBuilder
    private func mediaButtons(_ h: Highlight) -> some View {
        if h.videoDuration != nil || h.audioDuration != nil {
            HStack(spacing: 10) {
                if let d = h.videoDuration {
                    Button { Task { await playVideo(h) } } label: {
                        Label(loadingMedia == h.id + "v" ? "Henter…" : "Video \(MediaFiles.format(d))",
                              systemImage: "play.rectangle.fill")
                    }
                }
                if let d = h.audioDuration {
                    Button { Task { await toggleAudio(h) } } label: {
                        Label(loadingMedia == h.id + "a" ? "Henter…"
                              : (playingAudioId == h.id && audioPlayback.isPlaying ? "Stop" : "Lydnote \(MediaFiles.format(d))"),
                              systemImage: playingAudioId == h.id && audioPlayback.isPlaying ? "stop.fill" : "waveform")
                    }
                }
            }
            .font(.footnote.weight(.medium))
            .buttonStyle(.bordered)
            .tint(Theme.tint)
        }
    }

    private func playVideo(_ h: Highlight) async {
        loadingMedia = h.id + "v"
        defer { loadingMedia = nil }
        if let url = try? await state.store.highlightMedia(childId: child.id, id: h.id).video {
            playingVideo = VideoPlayerScreen(url: url)
        }
    }

    private func toggleAudio(_ h: Highlight) async {
        if playingAudioId == h.id && audioPlayback.isPlaying {
            audioPlayback.stop()
            return
        }
        audioPlayback.stop()   // stop en anden lydnote, der evt. spiller
        loadingMedia = h.id + "a"
        defer { loadingMedia = nil }
        if let url = try? await state.store.highlightMedia(childId: child.id, id: h.id).audio {
            playingAudioId = h.id
            audioPlayback.toggle(url: url)
        }
    }

    // Tryk på kortet = redigér; tryk på et billede = fuld skærm.
    private func card(_ highlight: Highlight) -> some View {
        // Forsidebilledet bærer titel og dato; resten ses i fuld skærm med forsiden først.
        PhotoCard(photos: PhotoSet(photos: highlight.photos, cover: highlight.coverIndex,
                                   thumb: highlight.thumb, loaded: highlight.photosLoaded),
                  title: highlight.text,
                  subtitle: highlight.date.map(Fmt.long),
                  zoomId: "\(highlight.id)_cover", zoomNamespace: zoomNS,
                  onEdit: state.canEdit ? { edit(highlight) } : nil,
                  onOpen: { openLightbox($0, for: highlight) }) {
            VStack(alignment: .leading, spacing: 8) {
                if let place = highlight.place {
                    PlaceLabel(place: place)
                    PlaceMap(place: place)
                }
                mediaButtons(highlight)
                CommentsBar(targetId: highlight.id, title: highlight.text)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
        .pressableCard { if state.canEdit { edit(highlight) } }
    }

    /// Fuld skærm: thumb med det samme, og originalerne så snart de er hentet (#62).
    private func openLightbox(_ shown: LightboxState, for highlight: Highlight) {
        lightbox = shown
        guard shown.needsOriginals else { return }
        Task {
            await CloudKitStore.withOriginals { await load() }
            guard let fresh = items.first(where: { $0.id == highlight.id }), !fresh.photos.isEmpty else { return }
            lightbox = LightboxState.coverFirst(photos: fresh.photos, cover: fresh.coverIndex, sourceId: shown.sourceId)
        }
    }

    /// Redigering kræver originalerne (ellers ville et gem ikke kunne ændre billederne).
    private func edit(_ highlight: Highlight) {
        if highlight.photosLoaded { editing = highlight; return }
        Task {
            await CloudKitStore.withOriginals { await load() }
            editing = items.first { $0.id == highlight.id } ?? highlight
        }
    }

    private func load() async {
        defer { loading = false }
        let cacheKey = "highlights_\(child.id)"
        if items.isEmpty, let cached = ScreenCache.load([Highlight].self, key: cacheKey) { items = cached; loading = false }
        if let fresh = try? await state.store.highlights(childId: child.id) {
            items = fresh
            ScreenCache.save(fresh, key: cacheKey)
        }
    }
}

struct AddHighlightView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let childId: String
    /// Øvrige børn samme indlæg også gemmes for (hurtig-tilføj på Hjem med flere børn valgt).
    var alsoFor: [Child] = []
    /// Navne vist øverst i formularen, når der gemmes for flere børn.
    var forNames: [String] = []
    /// Sat ved redigering; nil ved oprettelse.
    var editing: Highlight? = nil
    @State private var date = Date()
    @State private var text = ""
    @State private var photos: [Data] = []
    @State private var cover = 0        // det billede, der vises på oversigten
    @State private var place: Place?
    @State private var saving = false
    @State private var saveError: String?
    @State private var savedFor: Set<String> = []   // ved fejl midt i flere børn: undgå dubletter ved nyt forsøg
    @State private var loaded = false
    @State private var confirmDelete = false
    @State private var video: MediaChange = .keep
    @State private var audio: MediaChange = .keep

    /// Er der (eller kommer der) en video eller lydnote?
    private var hasMedia: Bool {
        func has(_ change: MediaChange, existing: Double?) -> Bool {
            switch change {
            case .keep: return existing != nil
            case .remove: return false
            case .set: return true
            }
        }
        return has(video, existing: editing?.videoDuration) || has(audio, existing: editing?.audioDuration)
    }

    var body: some View {
        NavigationStack {
            Form {
                Group {
                ForChildrenNote(names: forNames)
                DatePicker("Dato", selection: $date, displayedComponents: .date)
                Section("Tekst") {
                    TextField("Hvad skete der?", text: $text, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section("Billeder") {
                    MultiPhotoField(photos: $photos, cover: $cover, suggestRange: .around(date, days: 3))
                }
                Section("Sted (valgfrit)") {
                    PlaceField(place: $place)
                }
                Section {
                    MediaField(video: $video, audio: $audio,
                               existingVideo: editing?.videoDuration, existingAudio: editing?.audioDuration,
                               loadExisting: editing.map { h in
                                   { (try? await state.store.highlightMedia(childId: childId, id: h.id)) ?? (nil, nil) }
                               })
                } header: {
                    Text("Video og lyd")
                } footer: {
                    Text("Fx det første grin eller de første ord. Video maks 3 min, lydnote maks 5 min.")
                }
                if editing != nil {
                    Section {
                        Button("Slet højdepunkt", role: .destructive) { confirmDelete = true }
                    }
                }
                }.listRowBackground(Theme.card)
            }
            .themedList()
            .navigationTitle(editing == nil ? "Nyt højdepunkt" : "Redigér højdepunkt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annullér") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gem") {
                        if var highlight = editing {
                            highlight.date = date; highlight.text = text; highlight.photos = photos; highlight.cover = cover; highlight.place = place
                            let (updated, video, audio) = (highlight, video, audio)
                            Task {
                                await performSave(saving: $saving, errorMessage: $saveError, dismiss: dismiss) {
                                    try await state.store.updateHighlight(childId: childId, updated)
                                    try await state.store.setHighlightMedia(childId: childId, id: updated.id,
                                                                            video: video, audio: audio)
                                }
                            }
                        } else {
                            // Nyt højdepunkt: luk med det samme, upload billeder/video i baggrunden.
                            let (store, ids, date, text, photos, cover, place, video, audio) =
                                (state.store, [childId] + alsoFor.map(\.id), date, text, photos, cover, place, video, audio)
                            performSaveInBackground(label: "højdepunktet", dismiss: dismiss) {
                                for id in ids {
                                    let created = try await store.addHighlight(childId: id, date: date, text: text, photos: photos, cover: cover, place: place)
                                    try await store.setHighlightMedia(childId: id, id: created.id, video: video, audio: audio)
                                }
                            }
                        }
                    }
                    .disabled(saving || (text.trimmingCharacters(in: .whitespaces).isEmpty && photos.isEmpty && !hasMedia))
                }
            }
            .saveErrorAlert($saveError)
            .confirmationDialog("Slet højdepunktet?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Slet", role: .destructive) {
                    Task {
                        await performSave(saving: $saving, errorMessage: $saveError, dismiss: dismiss) {
                            if let id = editing?.id { try await state.store.deleteHighlight(childId: childId, id: id) }
                        }
                    }
                }
            } message: {
                Text("Højdepunktet og dets billeder slettes for hele familien.")
            }
            .onAppear {
                guard !loaded, let h = editing else { return }
                loaded = true
                date = h.date ?? h.createdAt; text = h.text; photos = h.photos; cover = h.coverIndex; place = h.place
            }
        }
    }
}
