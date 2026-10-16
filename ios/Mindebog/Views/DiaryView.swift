import SwiftUI

struct DiaryView: View {
    @EnvironmentObject var state: AppState
    let child: Child
    @State private var entries: [DiaryEntry] = []
    @State private var showAdd = false
    @State private var editing: DiaryEntry?
    @State private var lightbox: LightboxState?

    var body: some View {
        ScrollView {
            if entries.isEmpty {
                ContentUnavailableView("Ingen indlæg endnu", systemImage: "book")
                    .padding(.top, 60)
            } else {
                // Tidslinje som ferier og højdepunkter; uden dato bruges oprettelsesåret.
                TimelineView(items: entries,
                             year: { Calendar.current.component(.year, from: $0.date ?? $0.createdAt) }) { entry in
                    card(entry)
                }
                .padding(16)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(child.onTheWay ? "Svangerskabsdagbog" : "Dagbog")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if state.canEdit { Button { showAdd = true } label: { Image(systemName: "plus") } }
            }
        }
        .sheet(isPresented: $showAdd, onDismiss: { Task { await load() } }) {
            AddDiaryView(childId: child.id)
        }
        .sheet(item: $editing, onDismiss: { Task { await load() } }) { entry in
            AddDiaryView(childId: child.id, editing: entry)
        }
        .fullScreenCover(item: $lightbox) { LightboxView(state: $0) }
        .refreshable { await load() }
        .task { await load() }
        .reloadOnStoreChange { await load() }
    }

    // Tryk på opslaget = redigér; tryk på billedet = fuld skærm.
    // Samme kortstil som tidslinjen for ferier og højdepunkter.
    private func card(_ entry: DiaryEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let date = entry.date {
                Text(Fmt.long(date)).font(.caption).foregroundStyle(Theme.muted)
            }
            Text(entry.text).font(.body).foregroundStyle(Theme.text)
            if let photo = entry.photo {
                Color.clear
                    .aspectRatio(ImageTools.displayAspect(photo), contentMode: .fit)   // billedets egen form
                    .overlay { DataImage(data: photo) }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onTapGesture { lightbox = LightboxState(photos: [photo]) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.sep))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture { if state.canEdit { editing = entry } }
        .contextMenu {
            Button { if state.canEdit { editing = entry } } label: { Label("Redigér", systemImage: "pencil") }
        }
    }

    private func load() async {
        entries = (try? await state.store.diary(childId: child.id)) ?? []
    }
}

struct AddDiaryView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let childId: String
    /// Øvrige børn samme indlæg også gemmes for (hurtig-tilføj på Hjem med flere børn valgt).
    var alsoFor: [Child] = []
    /// Navne vist øverst i formularen, når der gemmes for flere børn.
    var forNames: [String] = []
    /// Sat ved redigering; nil ved oprettelse.
    var editing: DiaryEntry? = nil
    @State private var date = Date()
    @State private var text = ""
    @State private var photo: Data?
    @State private var saving = false
    @State private var saveError: String?
    @State private var savedFor: Set<String> = []   // ved fejl midt i flere børn: undgå dubletter ved nyt forsøg
    @State private var loaded = false
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                ForChildrenNote(names: forNames)
                DatePicker("Dato", selection: $date, displayedComponents: .date)
                Section("Tekst") {
                    TextField("Skriv dit indlæg…", text: $text, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section("Billede") {
                    PhotoField(data: $photo)
                }
                if editing != nil {
                    Section {
                        Button("Slet indlæg", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(editing == nil ? "Nyt indlæg" : "Redigér indlæg")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annullér") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gem") {
                        if var entry = editing {
                            entry.date = date; entry.text = text; entry.photo = photo
                            let updated = entry
                            Task {
                                await performSave(saving: $saving, errorMessage: $saveError, dismiss: dismiss) {
                                    try await state.store.updateDiary(childId: childId, updated)
                                }
                            }
                        } else {
                            // Nyt indlæg: luk med det samme, gem i baggrunden.
                            let (store, ids, date, text, photo) = (state.store, [childId] + alsoFor.map(\.id), date, text, photo)
                            performSaveInBackground(label: "dagbogsindlægget", dismiss: dismiss) {
                                for id in ids {
                                    _ = try await store.addDiary(childId: id, date: date, text: text, photo: photo)
                                }
                            }
                        }
                    }
                    .disabled(saving || (text.trimmingCharacters(in: .whitespaces).isEmpty && photo == nil))
                }
            }
            .saveErrorAlert($saveError)
            .confirmationDialog("Slet indlægget?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Slet", role: .destructive) {
                    Task {
                        await performSave(saving: $saving, errorMessage: $saveError, dismiss: dismiss) {
                            if let id = editing?.id { try await state.store.deleteDiary(childId: childId, id: id) }
                        }
                    }
                }
            } message: {
                Text("Indlægget og dets billede slettes for hele familien.")
            }
            .onAppear {
                guard !loaded, let e = editing else { return }
                loaded = true
                date = e.date ?? e.createdAt; text = e.text; photo = e.photo
            }
        }
    }
}
