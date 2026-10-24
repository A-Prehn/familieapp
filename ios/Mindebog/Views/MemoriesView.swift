import SwiftUI

/// "Minder" under Fælles: frie minder, der ikke er en begivenhed eller ferie — bare noget,
/// man vil gemme og dele med familien, fx bedsteforældre.
struct MemoriesView: View {
    @EnvironmentObject var state: AppState
    let memories: [FamilyMemory]
    let children: [Child]
    var members: [AppUser] = []
    var onEdit: (FamilyMemory) -> Void
    var onAdd: () -> Void
    var onLightbox: (LightboxState) -> Void

    var body: some View {
        if memories.isEmpty {
            VStack(spacing: 14) {
                Image(systemName: "heart.text.square")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Theme.neutralDark)
                Text("Jeres minder").font(.serifTitle(22))
                Text("Det, der ikke er en begivenhed eller rejse, men som I gerne vil huske: en sjov replik, en hyggelig søndag, mormors tale. Alle i familien kan se dem — også bedsteforældre.")
                    .font(.subheadline).foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                if state.canEdit {
                    Button { onAdd() } label: { Label("Tilføj det første minde", systemImage: "plus") }
                        .buttonStyle(.borderedProminent)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        } else {
            TimelineView(items: memories,
                         year: { $0.date.map { Calendar.current.component(.year, from: $0) } }) { memory in
                PhotoCard(photos: memory.photos, title: memory.title, subtitle: memory.dateText,
                          about: names(memory).isEmpty ? nil : names(memory),
                          onEdit: state.canEdit ? { onEdit(memory) } : nil, onOpen: onLightbox) {
                    VStack(alignment: .leading, spacing: 8) {
                        if !memory.text.isEmpty {
                            Text(memory.text).font(.footnote).foregroundStyle(Theme.text)
                        }
                        if let place = memory.place {
                            PlaceLabel(place: place)
                            PlaceMap(place: place)
                        }
                        CommentsBar(targetId: memory.id, title: memory.title)
                    }
                }
                .pressableCard { if state.canEdit { onEdit(memory) } }
            }
        }
    }

    private func names(_ memory: FamilyMemory) -> String {
        AboutPicker.names(childIds: memory.childIds, personIds: memory.personIds, children: children, members: members)
    }
}

/// Tilføj eller redigér et minde.
struct MemoryEditView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let familyId: String
    let children: [Child]
    var members: [AppUser] = []
    var editing: FamilyMemory? = nil

    @State private var draft = FamilyMemory(id: newId("mem"), title: "")
    @State private var hasDate = true
    @State private var date = Date()
    @State private var isPeriod = false     // flere dage, fx et spaophold med overnatning
    @State private var endDate = Date()
    @State private var saving = false
    @State private var saveError: String?
    @State private var confirmDelete = false
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Group {
                Section {
                    TextField("Titel (fx Første gang vi så havet)", text: $draft.title)
                    Toggle("Dato", isOn: $hasDate.animation())
                    if hasDate {
                        DatePicker(isPeriod ? "Fra" : "Hvornår", selection: $date, in: ...Date(), displayedComponents: .date)
                            .environment(\.locale, Locale(identifier: "da_DK"))
                        Toggle("Over flere dage", isOn: $isPeriod.animation())
                        if isPeriod {
                            DatePicker("Til", selection: $endDate, in: date..., displayedComponents: .date)
                                .environment(\.locale, Locale(identifier: "da_DK"))
                        }
                    }
                }
                Section("Fortæl om det") {
                    TextField("Hvad skete der, hvem var med, hvad blev der sagt …", text: $draft.text, axis: .vertical)
                        .lineLimit(3...12)
                }
                AboutPicker(children: children, members: members, childIds: $draft.childIds, personIds: $draft.personIds)
                Section("Billeder") {
                    PhotoSetEditor(set: $draft.photos)
                }
                Section("Sted (valgfrit)") {
                    PlaceField(place: $draft.place)
                }
                if editing != nil {
                    Section {
                        Button("Slet minde", role: .destructive) { confirmDelete = true }
                    }
                }
                }.listRowBackground(Theme.card)
            }
            .themedList()
            .navigationTitle(editing == nil ? "Nyt minde" : "Redigér minde")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annullér") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gem") { save() }
                        .disabled(saving || draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .saveErrorAlert($saveError)
            .confirmationDialog("Slet mindet?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Slet", role: .destructive) {
                    Task {
                        await performSave(saving: $saving, errorMessage: $saveError, dismiss: dismiss) {
                            if let id = editing?.id { try await state.store.deleteMemory(familyId: familyId, id: id) }
                        }
                    }
                }
            } message: {
                Text("Mindet og dets billeder slettes for hele familien.")
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let editing {
                    draft = editing
                    hasDate = editing.date != nil
                    date = editing.date ?? Date()
                    isPeriod = editing.endDate != nil
                    endDate = editing.endDate ?? date
                }
            }
        }
    }

    private func save() {
        draft.title = draft.title.trimmingCharacters(in: .whitespaces)
        draft.date = hasDate ? date : nil
        // Slutdato kun når den faktisk ligger efter startdagen.
        draft.endDate = hasDate && isPeriod && !Calendar.current.isDate(endDate, inSameDayAs: date) && endDate > date ? endDate : nil
        let (store, familyId, memory) = (state.store, familyId, draft)
        // Billeder kan tage tid at uploade: luk med det samme, gem i baggrunden.
        performSaveInBackground(label: "mindet", dismiss: dismiss) {
            try await store.saveMemory(familyId: familyId, memory)
        }
    }
}
