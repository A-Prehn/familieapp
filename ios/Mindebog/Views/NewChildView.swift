import SwiftUI

struct NewChildView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var born = true
    @State private var birthDate = Date()
    @State private var dueDate = Date()
    @State private var gender: Gender = .unspecified
    @State private var saving = false

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
            }
            .navigationTitle("Nyt barn")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annullér") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Opret") { Task { await create() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
        }
    }

    private func create() async {
        guard let familyId = state.familyId else { return }
        saving = true
        _ = try? await state.store.createChild(
            familyId: familyId, name: name, gender: gender,
            birthDate: born ? birthDate : nil,
            dueDate: born ? nil : dueDate)
        dismiss()
    }
}
