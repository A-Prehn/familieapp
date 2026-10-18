import SwiftUI

// Traditioner: familiens juleaften, fødselsdagssangen, mormors boller — tekst, billeder og lyd.
struct TraditionsView: View {
    @EnvironmentObject var state: AppState
    let traditions: [Tradition]
    var onEdit: (Tradition) -> Void
    var onAdd: () -> Void
    var onLightbox: (LightboxState) -> Void

    var body: some View {
        if traditions.isEmpty {
            VStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Theme.neutralDark)
                Text("Jeres traditioner").font(.serifTitle(22))
                Text("Det, I gør igen og igen: juleaften, fødselsdagssangen, sommerhuset, mormors boller. Skriv det ned, læg billeder på, og optag fx sangen — så arver børnene det.")
                    .font(.subheadline).foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                if state.canEdit {
                    Button { onAdd() } label: { Label("Tilføj den første tradition", systemImage: "plus") }
                        .buttonStyle(.borderedProminent)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        } else {
            VStack(spacing: 12) {
                ForEach(traditions) { t in
                    TraditionCard(tradition: t, onLightbox: onLightbox)
                        .onTapGesture { if state.canEdit { onEdit(t) } }
                }
            }
        }
    }
}

private struct TraditionCard: View {
    @EnvironmentObject var state: AppState
    let tradition: Tradition
    var onLightbox: (LightboxState) -> Void
    @StateObject private var playback = AudioPlayback()
    @State private var loading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tradition.title).font(.serifTitle(17)).foregroundStyle(Theme.text)
                    if !tradition.when.isEmpty {
                        Label(tradition.when, systemImage: "calendar").font(.caption).foregroundStyle(Theme.neutralDark)
                    }
                }
                Spacer()
                if let d = tradition.audioDuration {
                    Button { Task { await toggle() } } label: {
                        HStack(spacing: 6) {
                            if loading { ProgressView().controlSize(.small) }
                            else { Image(systemName: playback.isPlaying ? "stop.fill" : "play.fill") }
                            Text(MediaFiles.format(d))
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().fill(Theme.rose.opacity(0.15)))
                        .foregroundStyle(Theme.rose)
                    }
                    .buttonStyle(.plain)
                }
            }
            if !tradition.details.isEmpty {
                Text(tradition.details).font(.subheadline).foregroundStyle(Theme.muted).lineLimit(4)
            }
            if !tradition.photos.isEmpty {
                CoverPhotoView(set: tradition.photos) { onLightbox($0) }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.sep))
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }

    private func toggle() async {
        if playback.isPlaying { playback.stop(); return }
        guard let familyId = state.familyId else { return }
        loading = true
        defer { loading = false }
        if let url = try? await state.store.traditionAudio(familyId: familyId, id: tradition.id) {
            playback.toggle(url: url)
        }
    }
}

/// Tilføj eller redigér en tradition.
struct TraditionEditView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let familyId: String
    var editing: Tradition? = nil

    @State private var draft = Tradition(id: newId("trad"), title: "")
    @State private var audio: MediaChange = .keep
    @State private var saving = false
    @State private var saveError: String?
    @State private var confirmDelete = false

    private static let ideas = ["Juleaften", "Nytårsaften", "Fødselsdagsmorgen", "Fastelavn", "Påske",
                                "Sankthans", "Sommerhuset", "Søndagsmorgen", "Godnatritual"]

    var body: some View {
        NavigationStack {
            Form {
                Group {
                Section {
                    TextField("Tradition (fx Juleaften hos mormor)", text: $draft.title)
                    TextField("Hvornår (fx 24. december, hver fødselsdag)", text: $draft.when)
                    if editing == nil && draft.title.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Self.ideas, id: \.self) { s in
                                    Button(s) { draft.title = s }
                                        .font(.footnote)
                                        .padding(.horizontal, 10).padding(.vertical, 6)
                                        .background(Capsule().fill(Theme.bgDark))
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                Section("Sådan gør vi") {
                    TextField("Hvad sker der, hvem er med, hvad spiser I, hvad synger I …", text: $draft.details, axis: .vertical)
                        .lineLimit(4...12)
                }
                Section("Billeder") {
                    PhotoSetEditor(set: $draft.photos)
                }
                Section {
                    MediaField(video: .constant(.keep), audio: $audio, existingAudio: editing?.audioDuration,
                               showVideo: false, audioLabel: "Optag (fx sangen)",
                               loadExisting: editing.map { t in
                                   { (video: nil, audio: try? await state.store.traditionAudio(familyId: familyId, id: t.id)) }
                               })
                } header: {
                    Text("Lyd")
                } footer: {
                    Text("Fødselsdagssangen, bordbønnen eller bare stemningen rundt om bordet.")
                }
                if editing != nil {
                    Section {
                        Button("Slet tradition", role: .destructive) { confirmDelete = true }
                    }
                }
                }.listRowBackground(Theme.card)
            }
            .themedList()
            .navigationTitle(editing == nil ? "Ny tradition" : "Redigér tradition")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annullér") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gem") { Task { await save() } }
                        .disabled(saving || draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .saveErrorAlert($saveError)
            .confirmationDialog("Slet traditionen?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Slet", role: .destructive) {
                    Task {
                        await performSave(saving: $saving, errorMessage: $saveError, dismiss: dismiss) {
                            if let id = editing?.id { try await state.store.deleteTradition(familyId: familyId, id: id) }
                        }
                    }
                }
            }
            .onAppear { if let editing { draft = editing } }
        }
    }

    private func save() async {
        draft.title = draft.title.trimmingCharacters(in: .whitespaces)
        let (store, familyId, t, audio) = (state.store, familyId, draft, audio)
        performSaveInBackground(label: "traditionen", dismiss: dismiss) {
            try await store.saveTradition(familyId: familyId, t, audio: audio)
        }
    }
}
