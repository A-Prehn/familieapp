import SwiftUI

// Børnevaccinationsprogrammet som tjekliste. Forventet tidspunkt beregnes ud fra
// fødselsdatoen; givne vaccinationer gemmes som milepæle (nøgle "vac_…"), så der
// ikke kræves noget nyt i iCloud.
struct VaccineDef: Identifiable, Hashable {
    let key: String
    let name: String
    let detail: String
    let ageMonths: Int
    var id: String { key }
}

enum VaccineProgram {
    /// Sundhedsstyrelsens børnevaccinationsprogram (Danmark).
    static let all: [VaccineDef] = [
        VaccineDef(key: "vac_3m", name: "3 måneder", detail: "Di-Te-KiPol/Hib + pneumokok (1. dosis)", ageMonths: 3),
        VaccineDef(key: "vac_5m", name: "5 måneder", detail: "Di-Te-KiPol/Hib + pneumokok (2. dosis)", ageMonths: 5),
        VaccineDef(key: "vac_12m", name: "12 måneder", detail: "Di-Te-KiPol/Hib + pneumokok (3. dosis)", ageMonths: 12),
        VaccineDef(key: "vac_15m", name: "15 måneder", detail: "MFR – mæslinger, fåresyge, røde hunde (1. dosis)", ageMonths: 15),
        VaccineDef(key: "vac_4y", name: "4 år", detail: "MFR (2. dosis)", ageMonths: 48),
        VaccineDef(key: "vac_5y", name: "5 år", detail: "Di-Te-KiPol (revaccination)", ageMonths: 60),
        VaccineDef(key: "vac_12y", name: "12 år", detail: "HPV (2 doser)", ageMonths: 144),
    ]
}

struct VaccinesView: View {
    @EnvironmentObject var state: AppState
    let child: Child
    @State private var given: [String: Date] = [:]
    @State private var editing: VaccineDef?
    @State private var custom: [CustomVaccine] = []
    @State private var editingCustom: CustomVaccine?
    @State private var addingCustom = false

    var body: some View {
        List {
            Section {
                ForEach(VaccineProgram.all) { vaccine in
                    row(vaccine)
                }
            } header: {
                Text("Børnevaccinationsprogrammet")
            } footer: {
                Text("Efter Sundhedsstyrelsens børnevaccinationsprogram. Tidspunkterne er vejledende — aftal altid med jeres egen læge.")
            }

            Section {
                ForEach(custom) { v in
                    customRow(v)
                }
                if state.canEdit {
                    Button { addingCustom = true } label: {
                        Label("Tilføj vaccine", systemImage: "plus.circle")
                    }
                }
            } header: {
                Text("Andre vacciner")
            } footer: {
                if custom.isEmpty {
                    Text("Fx hepatitis A/B, rotavirus, influenza eller rejsevacciner.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Vaccinationer")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing, onDismiss: { Task { await load() } }) { vaccine in
            VaccineEditView(child: child, vaccine: vaccine, given: given[vaccine.key])
                .presentationDetents([.medium])
        }
        .sheet(item: $editingCustom, onDismiss: { Task { await load() } }) { v in
            CustomVaccineEditView(child: child, existing: v)
        }
        .sheet(isPresented: $addingCustom, onDismiss: { Task { await load() } }) {
            CustomVaccineEditView(child: child, existing: nil)
        }
        .refreshable { await load() }
        .task { await load() }
        .reloadOnStoreChange { await load() }
    }

    private func row(_ v: VaccineDef) -> some View {
        let done = given[v.key]
        let due = child.birthDate.flatMap { Calendar.current.date(byAdding: .month, value: v.ageMonths, to: $0) }
        let soon = due.map { $0.timeIntervalSinceNow < 30 * 86_400 } ?? false
        return HStack(spacing: 14) {
            Image(systemName: done != nil ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(done != nil ? Theme.green : (soon ? Theme.rose : Theme.muted))
            VStack(alignment: .leading, spacing: 2) {
                Text(v.name).font(.subheadline.weight(.semibold))
                Text(v.detail).font(.footnote).foregroundStyle(Theme.muted)
                if let done {
                    Text("Givet \(Fmt.long(done))").font(.caption).foregroundStyle(Theme.green)
                } else if let due {
                    Text((due < Date() ? "Forventet " : "Omkring ") + Fmt.long(due))
                        .font(.caption).foregroundStyle(soon ? Theme.rose : Theme.muted)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { if state.canEdit { editing = v } }
    }

    private func customRow(_ v: CustomVaccine) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(Theme.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(v.name).font(.subheadline.weight(.semibold))
                if !v.note.isEmpty {
                    Text(v.note).font(.footnote).foregroundStyle(Theme.muted)
                }
                Text("Givet \(Fmt.long(v.date))").font(.caption).foregroundStyle(Theme.green)
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { if state.canEdit { editingCustom = v } }
    }

    private func load() async {
        let cacheKey = "milestones_\(child.id)"
        if given.isEmpty && custom.isEmpty, let cached = ScreenCache.load([String: MilestoneEntry].self, key: cacheKey) { apply(cached) }
        guard let ms = try? await state.store.milestones(childId: child.id) else { return }
        apply(ms)
        ScreenCache.save(ms, key: cacheKey)
    }

    private func apply(_ ms: [String: MilestoneEntry]) {
        var out: [String: Date] = [:]
        for v in VaccineProgram.all {
            if let value = ms[v.key]?.value, let date = Fmt.parseIso(value) { out[v.key] = date }
        }
        given = out
        custom = ms.compactMap { key, entry in
            guard key.hasPrefix(CustomVaccine.prefix), let value = entry.value else { return nil }
            return CustomVaccine.decode(value)
        }
        .sorted { $0.date > $1.date }
    }
}

/// Markér en vaccination som givet (med dato) — eller fjern markeringen.
struct VaccineEditView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let child: Child
    let vaccine: VaccineDef
    let given: Date?

    @State private var date = Date()
    @State private var saving = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(vaccine.detail).font(.footnote).foregroundStyle(Theme.muted)
                    DatePicker("Givet den", selection: $date, in: ...Date(), displayedComponents: .date)
                }
                if given != nil {
                    Section {
                        Button("Fjern markering", role: .destructive) { Task { await save(nil) } }
                    }
                }
            }
            .navigationTitle(vaccine.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annullér") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gem") { Task { await save(date) } }.disabled(saving)
                }
            }
            .saveErrorAlert($saveError)
            .onAppear { if let given { date = given } }
        }
    }

    private func save(_ value: Date?) async {
        await performSave(saving: $saving, errorMessage: $saveError, dismiss: dismiss) {
            try await state.store.setMilestone(childId: child.id, key: vaccine.key,
                                               value: value.map(Fmt.iso), photos: PhotoSet())
        }
    }
}

// MARK: - Egne vacciner

/// En vaccine uden for standardprogrammet (fx hepatitis A/B før en rejse).
/// Gemmes som milepæl med nøglen "vacx_<id>" og JSON som værdi, så der ikke kræves
/// noget nyt i iCloud. Andre visninger ignorerer ukendte milepælsnøgler.
struct CustomVaccine: Identifiable, Hashable, Codable {
    static let prefix = "vacx_"
    var key: String
    var name: String
    var note: String
    var date: Date
    var id: String { key }

    static func new() -> CustomVaccine {
        CustomVaccine(key: prefix + UUID().uuidString.prefix(8).lowercased(), name: "", note: "", date: Date())
    }

    var encoded: String? {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        return (try? enc.encode(self)).flatMap { String(data: $0, encoding: .utf8) }
    }

    static func decode(_ value: String) -> CustomVaccine? {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return value.data(using: .utf8).flatMap { try? dec.decode(CustomVaccine.self, from: $0) }
    }
}

/// Tilføj, redigér eller slet en egen vaccine.
struct CustomVaccineEditView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let child: Child
    let existing: CustomVaccine?

    @State private var draft = CustomVaccine.new()
    @State private var saving = false
    @State private var saveError: String?
    @State private var confirmDelete = false

    private static let suggestions = ["Hepatitis A", "Hepatitis B", "Hepatitis A+B", "Rotavirus",
                                      "Influenza", "Skoldkopper", "TBE (skovflåt)", "Tyfus", "Gul feber", "BCG (tuberkulose)"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Vaccine (fx Hepatitis A)", text: $draft.name)
                    DatePicker("Givet den", selection: $draft.date, in: ...Date(), displayedComponents: .date)
                    TextField("Note (valgfri, fx dosis eller rejse)", text: $draft.note, axis: .vertical)
                        .lineLimit(1...3)
                }
                if existing == nil && draft.name.isEmpty {
                    Section("Forslag") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Self.suggestions, id: \.self) { s in
                                    Button(s) { draft.name = s }
                                        .font(.footnote)
                                        .padding(.horizontal, 10).padding(.vertical, 6)
                                        .background(Capsule().fill(Theme.bgDark))
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                if existing != nil {
                    Section {
                        Button("Slet vaccine", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(existing == nil ? "Ny vaccine" : "Redigér vaccine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annullér") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gem") { Task { await save(delete: false) } }
                        .disabled(saving || draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Slet vaccinen?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Slet", role: .destructive) { Task { await save(delete: true) } }
            }
            .saveErrorAlert($saveError)
            .onAppear { if let existing { draft = existing } }
        }
    }

    private func save(delete: Bool) async {
        draft.name = draft.name.trimmingCharacters(in: .whitespaces)
        draft.note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = delete ? nil : draft.encoded
        await performSave(saving: $saving, errorMessage: $saveError, dismiss: dismiss) {
            try await state.store.setMilestone(childId: child.id, key: draft.key, value: value, photos: PhotoSet())
        }
    }
}
