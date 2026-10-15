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

    var body: some View {
        List {
            Section {
                ForEach(VaccineProgram.all) { vaccine in
                    row(vaccine)
                }
            } footer: {
                Text("Efter Sundhedsstyrelsens børnevaccinationsprogram. Tidspunkterne er vejledende — aftal altid med jeres egen læge.")
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
        .refreshable { await load() }
        .task { await load() }
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

    private func load() async {
        let ms = (try? await state.store.milestones(childId: child.id)) ?? [:]
        var out: [String: Date] = [:]
        for v in VaccineProgram.all {
            if let value = ms[v.key]?.value, let date = Fmt.parseIso(value) { out[v.key] = date }
        }
        given = out
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
