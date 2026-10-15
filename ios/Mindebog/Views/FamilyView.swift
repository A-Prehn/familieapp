import SwiftUI

struct FamilyView: View {
    @EnvironmentObject var state: AppState
    @State private var events: [FamilyEvent] = []
    @State private var family: Family?
    @State private var showAdd = false

    var body: some View {
        ScrollView {
            if events.isEmpty {
                ContentUnavailableView("Ingen begivenheder endnu", systemImage: "calendar")
                    .padding(.top, 60)
            } else {
                VStack(spacing: 0) {
                    ForEach(events) { ev in
                        HStack(alignment: .top, spacing: 14) {
                            VStack(spacing: 0) {
                                Text(ev.date.map { $0.formatted(.dateTime.month(.abbreviated)) }?.uppercased() ?? "—")
                                    .font(.caption2).foregroundStyle(Theme.muted)
                                Text(ev.date.map { $0.formatted(.dateTime.day()) } ?? "·")
                                    .font(.serifTitle(20))
                            }
                            .frame(width: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ev.title).font(.system(size: 15, weight: .medium))
                                if !ev.details.isEmpty {
                                    Text(ev.details).font(.footnote).foregroundStyle(Theme.muted)
                                }
                            }
                            Spacer()
                        }
                        .padding(.vertical, 12)
                        Divider()
                    }
                }
                .padding(16)
                .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(16)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(family?.name ?? "Familie")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAdd, onDismiss: { Task { await load() } }) {
            AddEventView(familyId: state.familyId ?? "")
        }
        .task { await load() }
    }

    private func load() async {
        guard let familyId = state.familyId else { return }
        family = try? await state.store.families(for: state.user?.id ?? "").first { $0.id == familyId }
        events = (try? await state.store.events(familyId: familyId)) ?? []
    }
}

struct AddEventView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let familyId: String
    @State private var title = ""
    @State private var date = Date()
    @State private var details = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Titel", text: $title)
                DatePicker("Dato", selection: $date, displayedComponents: .date)
                Section("Beskrivelse") {
                    TextField("Beskrivelse", text: $details, axis: .vertical).lineLimit(2...5)
                }
            }
            .navigationTitle("Ny begivenhed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annullér") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gem") {
                        Task {
                            _ = try? await state.store.addEvent(familyId: familyId, title: title, date: date, details: details)
                            dismiss()
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
