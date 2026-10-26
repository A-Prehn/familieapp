import SwiftUI

// Opret eller redigér et barn (navn, født/på vej, datoer, køn).
struct NewChildView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    /// Sat ved redigering; nil ved oprettelse.
    var editing: Child? = nil
    var onSaved: (Child) -> Void = { _ in }
    /// Kaldes, når barnet er slettet (kun ved redigering).
    var onDeleted: () -> Void = {}

    @State private var name = ""
    @State private var born = true
    @State private var birthDate = Date()
    @State private var dueDate = Date()
    @State private var gender: Gender = .unspecified
    @State private var photo: Data?
    /// Barnet er oprettet, men billedet fejlede: "Gem" igen opdaterer i stedet for at oprette et barn mere.
    @State private var created: Child?
    @State private var saving = false
    @State private var errorMessage: String?
    @State private var loaded = false
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Group {
                Section {
                    TextField("Barnets navn", text: $name)
                }
                Section("Status") {
                    Picker("Status", selection: $born) {
                        Text("Født").tag(true)
                        Text("På vej").tag(false)
                    }
                    .pickerStyle(.segmented)
                    if born {
                        DatePicker("Fødselsdato", selection: $birthDate, displayedComponents: .date)
                    } else {
                        DatePicker("Terminsdato", selection: $dueDate, displayedComponents: .date)
                    }
                }
                Section("Køn") {
                    Picker("Køn", selection: $gender) {
                        ForEach(Gender.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    PhotoField(data: $photo)
                } header: {
                    Text("Billede")
                } footer: {
                    Text("Vises i cirklen i stedet for initialerne. Kan udelades.")
                }
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(Theme.rose)
                }
                if editing != nil {
                    Section {
                        Button("Slet barn", role: .destructive) { confirmDelete = true }
                            .disabled(saving)
                    } footer: {
                        Text("Sletter barnet og alt i barnets bog for alle i familien.")
                    }
                }
                }.listRowBackground(Theme.card)
            }
            .themedList()
            .navigationTitle(editing == nil ? "Nyt barn" : "Redigér \(editing?.name ?? "")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annullér") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? "Opret" : "Gem") { Task { await save() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
            .onAppear(perform: fillFromEditing)
            .confirmationDialog("Slet \(editing?.name ?? "barnet") og alt indhold?",
                                isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Slet \(editing?.name ?? "barnet")", role: .destructive) { Task { await delete() } }
                Button("Annullér", role: .cancel) {}
            } message: {
                Text("Højdepunkter, milepæle, dagbog, breve og billeder slettes. Det kan ikke fortrydes.")
            }
        }
    }

    private func fillFromEditing() {
        guard !loaded, let child = editing else { return }
        loaded = true
        name = child.name
        gender = child.gender
        photo = child.photo
        born = child.birthDate != nil
        if let b = child.birthDate { birthDate = b }
        if let d = child.dueDate { dueDate = d }
    }

    private func delete() async {
        guard let child = editing else { return }
        saving = true
        errorMessage = nil
        do {
            try await state.store.deleteChild(child)
            dismiss()
            onDeleted()
        } catch StoreError.notOwner {
            errorMessage = "Kun den, der har oprettet familien, kan slette et barn."
            saving = false
        } catch {
            errorMessage = "Kunne ikke slette: \(error.userMessage)"
            saving = false
        }
    }

    private func save() async {
        guard let familyId = state.familyId else { return }
        saving = true
        errorMessage = nil
        do {
            if var child = editing ?? created {
                child.name = name
                child.gender = gender
                child.photo = photo
                if born {
                    child.birthDate = birthDate   // terminsdatoen bevares som minde
                } else {
                    child.birthDate = nil
                    child.dueDate = dueDate
                }
                onSaved(try await state.store.updateChild(child))
            } else {
                var child = try await state.store.createChild(
                    familyId: familyId, name: name, gender: gender,
                    birthDate: born ? birthDate : nil,
                    dueDate: born ? nil : dueDate)
                created = child
                if let photo {
                    child.photo = photo
                    do {
                        child = try await state.store.updateChild(child)
                    } catch {
                        errorMessage = "\(name) er oprettet, men billedet kunne ikke gemmes. Tryk Gem for at prøve igen."
                        saving = false
                        return
                    }
                }
                onSaved(child)
            }
            dismiss()
        } catch {
            errorMessage = "Kunne ikke gemme: \(error.userMessage)"
            saving = false
        }
    }
}
