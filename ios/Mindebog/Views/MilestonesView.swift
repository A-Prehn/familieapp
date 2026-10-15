import SwiftUI

struct MilestonesView: View {
    @EnvironmentObject var state: AppState
    let child: Child
    @State private var entries: [String: MilestoneEntry] = [:]
    @State private var editing: MilestoneDef?
    @State private var lightbox: LightboxState?

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Constants.milestones) { def in
                    tile(def)
                }
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Milepæle")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing, onDismiss: { Task { await load() } }) { def in
            MilestoneEditView(child: child, def: def, entry: entries[def.key])
        }
        .fullScreenCover(item: $lightbox) { LightboxView(state: $0) }
        .refreshable { await load() }
        .task { await load() }
    }

    private func tile(_ def: MilestoneDef) -> some View {
        let entry = entries[def.key]
        let filled = entry?.value != nil || entry?.photo != nil
        return VStack(spacing: 0) {
            Color.clear
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
                .overlay {
                    ZStack {
                        Theme.bgDark
                        if let photo = entry?.photo {
                            DataImage(data: photo)
                        } else {
                            Text(def.icon)
                                .font(.system(size: 28))
                                .opacity(filled ? 0.85 : 0.4)
                        }
                    }
                }
                .clipped()
                .contentShape(Rectangle())
                .onTapGesture {
                    if let photo = entry?.photo {
                        lightbox = LightboxState(photos: [photo])
                    } else {
                        editing = def
                    }
                }

            VStack(spacing: 2) {
                Text(def.label)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                Text(displayValue(def, entry))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(filled ? Theme.text : Theme.muted.opacity(0.6))
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .onTapGesture { editing = def }
        }
        .background(filled ? Theme.card : Theme.bg)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(filled ? Theme.green.opacity(0.35) : Theme.sep)
        )
    }

    private func displayValue(_ def: MilestoneDef, _ entry: MilestoneEntry?) -> String {
        guard let value = entry?.value else { return "—" }
        if def.isDate, let date = Fmt.parseIso(value) { return Fmt.long(date) }
        return value
    }

    private func load() async {
        entries = (try? await state.store.milestones(childId: child.id)) ?? [:]
    }
}

struct MilestoneEditView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let child: Child
    let def: MilestoneDef
    let entry: MilestoneEntry?

    @State private var hasDate = false
    @State private var date = Date()
    @State private var text = ""
    @State private var photo: Data?

    var body: some View {
        NavigationStack {
            Form {
                if def.isDate {
                    Section("Dato") {
                        Toggle("Sæt dato", isOn: $hasDate)
                        if hasDate {
                            DatePicker("Dato", selection: $date, displayedComponents: .date)
                        }
                    }
                } else {
                    Section("Værdi") {
                        TextField("Skriv her…", text: $text)
                    }
                }
                Section("Billede") {
                    PhotoField(data: $photo)
                }
            }
            .navigationTitle(def.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annullér") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gem") { Task { await save() } }
                }
            }
            .onAppear(perform: prefill)
        }
    }

    private func prefill() {
        photo = entry?.photo
        if def.isDate {
            if let value = entry?.value, let parsed = Fmt.parseIso(value) {
                date = parsed
                hasDate = true
            }
        } else {
            text = entry?.value ?? ""
        }
    }

    private func save() async {
        let value: String?
        if def.isDate {
            value = hasDate ? Fmt.iso(date) : nil
        } else {
            value = text
        }
        try? await state.store.setMilestone(childId: child.id, key: def.key, value: value, photo: photo)
        dismiss()
    }
}
