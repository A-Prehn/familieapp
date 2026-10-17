import SwiftUI

/// "Minder" under Fælles: frie minder, der ikke er en begivenhed eller ferie — bare noget,
/// man vil gemme og dele med familien, fx bedsteforældre.
struct MemoriesView: View {
    @EnvironmentObject var state: AppState
    let memories: [FamilyMemory]
    let children: [Child]
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
                Text("Det, der ikke er en begivenhed eller ferie, men som I gerne vil huske: en sjov replik, en hyggelig søndag, mormors tale. Alle i familien kan se dem — også bedsteforældre.")
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
                VStack(alignment: .leading, spacing: 8) {
                    Text(memory.title).font(.serifTitle(16)).foregroundStyle(Theme.text)
                    HStack(spacing: 6) {
                        if let date = memory.date { Text(Fmt.long(date)) }
                        if !names(memory).isEmpty {
                            if memory.date != nil { Text("·") }
                            Label(names(memory), systemImage: "person")
                        }
                    }
                    .font(.caption).foregroundStyle(Theme.muted)
                    if !memory.text.isEmpty {
                        Text(memory.text).font(.footnote).foregroundStyle(Theme.text)
                    }
                    CoverPhotoView(set: memory.photos) { onLightbox($0) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .contentShape(Rectangle())
                .onTapGesture { if state.canEdit { onEdit(memory) } }
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.sep.opacity(0.7)))
        .warmShadow()
            }
        }
    }

    private func names(_ memory: FamilyMemory) -> String {
        memory.childIds.compactMap { id in children.first { $0.id == id }?.name }.joined(separator: ", ")
    }
}

/// Tilføj eller redigér et minde.
struct MemoryEditView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let familyId: String
    let children: [Child]
    var editing: FamilyMemory? = nil

    @State private var draft = FamilyMemory(id: newId("mem"), title: "")
    @State private var hasDate = true
    @State private var date = Date()
    @State private var saving = false
    @State private var saveError: String?
    @State private var confirmDelete = false
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Titel (fx Første gang vi så havet)", text: $draft.title)
                    Toggle("Dato", isOn: $hasDate.animation())
                    if hasDate {
                        DatePicker("Hvornår", selection: $date, in: ...Date(), displayedComponents: .date)
                    }
                }
                Section("Fortæl om det") {
                    TextField("Hvad skete der, hvem var med, hvad blev der sagt …", text: $draft.text, axis: .vertical)
                        .lineLimit(3...12)
                }
                if !children.isEmpty {
                    Section {
                        ForEach(children) { child in
                            Button { toggle(child.id) } label: {
                                HStack {
                                    ChildAvatar(child: child, size: 28)
                                    Text(child.name).foregroundStyle(Theme.text)
                                    Spacer()
                                    if draft.childIds.contains(child.id) {
                                        Image(systemName: "checkmark").foregroundStyle(Theme.tint)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("Handler om (valgfrit)")
                    } footer: {
                        Text("Vælg ingen, hvis mindet gælder hele familien.")
                    }
                }
                Section("Billeder") {
                    PhotoSetEditor(set: $draft.photos)
                }
                if editing != nil {
                    Section {
                        Button("Slet minde", role: .destructive) { confirmDelete = true }
                    }
                }
            }
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
                }
            }
        }
    }

    private func toggle(_ id: String) {
        if let i = draft.childIds.firstIndex(of: id) { draft.childIds.remove(at: i) } else { draft.childIds.append(id) }
    }

    private func save() {
        draft.title = draft.title.trimmingCharacters(in: .whitespaces)
        draft.date = hasDate ? date : nil
        let (store, familyId, memory) = (state.store, familyId, draft)
        // Billeder kan tage tid at uploade: luk med det samme, gem i baggrunden.
        performSaveInBackground(label: "mindet", dismiss: dismiss) {
            try await store.saveMemory(familyId: familyId, memory)
        }
    }
}
