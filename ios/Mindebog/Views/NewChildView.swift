import SwiftUI

// Opret eller redigér et barn (navn, født/på vej, datoer, køn).
struct NewChildView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    /// Sat ved redigering; nil ved oprettelse.
    var editing: Child? = nil
    var onSaved: (Child) -> Void = { _ in }

    @State private var name = ""
    @State private var born = true
    @State private var birthDate = Date()
    @State private var dueDate = Date()
    @State private var gender: Gender = .unspecified
    @State private var saving = false
    @State private var errorMessage: String?
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
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
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(Theme.rose)
                }
            }
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
        }
    }

    private func fillFromEditing() {
        guard !loaded, let child = editing else { return }
        loaded = true
        name = child.name
        gender = child.gender
        born = child.birthDate != nil
        if let b = child.birthDate { birthDate = b }
        if let d = child.dueDate { dueDate = d }
    }

    private func save() async {
        guard let familyId = state.familyId else { return }
        saving = true
        errorMessage = nil
        do {
            if var child = editing {
                child.name = name
                child.gender = gender
                if born {
                    child.birthDate = birthDate   // terminsdatoen bevares som minde
                } else {
                    child.birthDate = nil
                    child.dueDate = dueDate
                }
                onSaved(try await state.store.updateChild(child))
            } else {
                let child = try await state.store.createChild(
                    familyId: familyId, name: name, gender: gender,
                    birthDate: born ? birthDate : nil,
                    dueDate: born ? nil : dueDate)
                onSaved(child)
            }
            dismiss()
        } catch {
            errorMessage = "Kunne ikke gemme: \(error.localizedDescription)"
            saving = false
        }
    }
}
