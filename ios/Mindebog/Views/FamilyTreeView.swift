import SwiftUI

// Familietræet under Fælles: tegnes ud fra personerne og deres relationer.
// Kan panoreres og zoomes; tryk på en person for at redigere.
struct FamilyTreeView: View {
    @EnvironmentObject var state: AppState
    let persons: [Person]
    let children: [Child]
    var onEdit: (Person) -> Void
    var onAdd: () -> Void

    @State private var zoom: CGFloat = 1
    @State private var lastZoom: CGFloat = 1

    var body: some View {
        if persons.isEmpty {
            VStack(spacing: 14) {
                Image(systemName: "tree")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Theme.neutralDark)
                Text("Jeres familietræ").font(.serifTitle(22))
                Text("Tilføj en person ad gangen og vælg, hvem der er forældre og partnere. Så vokser træet frem af sig selv — også med halvsøskende og sammenbragte familier.")
                    .font(.subheadline).foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                if state.canEdit {
                    Button { onAdd() } label: {
                        Label("Tilføj den første person", systemImage: "person.badge.plus")
                    }
                    .buttonStyle(.primaryPill)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        } else {
            let layout = FamilyTreeLayout(persons: persons)
            VStack(spacing: 10) {
                ScrollView([.horizontal, .vertical], showsIndicators: false) {
                    ZStack(alignment: .topLeading) {
                        Canvas { ctx, _ in
                            for line in layout.lines {
                                var path = Path()
                                path.addLines(line.points)
                                let style = StrokeStyle(lineWidth: 1.5, lineCap: .round,
                                                        dash: line.dashed ? [4, 5] : [])
                                ctx.stroke(path, with: .color(Theme.neutral.opacity(line.dashed ? 0.8 : 0.9)), style: style)
                            }
                        }
                        .frame(width: layout.size.width, height: layout.size.height)
                        ForEach(layout.nodes) { node in
                            PersonCard(person: node.person, child: linkedChild(node.person))
                                .frame(width: node.frame.width, height: node.frame.height)
                                .position(x: node.frame.midX, y: node.frame.midY)
                                .onTapGesture { if state.canEdit { onEdit(node.person) } }
                        }
                    }
                    .frame(width: layout.size.width, height: layout.size.height)
                    .padding(24)
                    .scaleEffect(zoom, anchor: .topLeading)
                    .frame(width: (layout.size.width + 48) * zoom, height: (layout.size.height + 48) * zoom)
                }
                .frame(minHeight: 360)
                .noTabSwipe()   // panorering i træet må ikke skifte hovedfane
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Theme.sep))
                .gesture(MagnificationGesture()
                    .onChanged { zoom = min(2, max(0.5, lastZoom * $0)) }
                    .onEnded { _ in lastZoom = zoom })

                HStack {
                    Text("Stiplet linje: barn af kun den ene i parret.")
                        .font(.caption).foregroundStyle(Theme.muted)
                    Spacer()
                    Button { withAnimation { zoom = 1; lastZoom = 1 } } label: {
                        Image(systemName: "arrow.counterclockwise").font(.caption)
                    }
                    .opacity(zoom == 1 ? 0 : 1)
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private func linkedChild(_ p: Person) -> Child? {
        p.childId.flatMap { id in children.first { $0.id == id } }
    }
}

/// Én person i træet: rundt billede eller initialer, navn, rolle og årstal.
struct PersonCard: View {
    let person: Person
    var child: Child? = nil

    private var name: String { child?.name ?? person.name }
    private var photo: Data? { child?.photo ?? person.photo }
    private var birth: Date? { child?.birthDate ?? person.birthDate }

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                if let photo {
                    DataImage(data: photo)
                        .frame(width: 56, height: 56)
                        .clipShape(Circle())
                } else {
                    Circle().fill(Theme.bgDark)
                    Text(initials)
                        .font(.serifTitle(19))
                        .foregroundStyle(Theme.neutralDark)
                }
                Circle().strokeBorder(Theme.neutral.opacity(0.35), lineWidth: 1)
            }
            .frame(width: 56, height: 56)
            Text(name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
            if !person.role.isEmpty {
                Text(person.role).font(.system(size: 10)).foregroundStyle(Theme.muted).lineLimit(1)
            }
            if let years {
                Text(years).font(.system(size: 10)).foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
    }

    private var initials: String {
        // Spring "(dig)" o.l. over, så initialerne ikke bliver "A(".
        let letters = name.split(separator: " ").compactMap(\.first).filter(\.isLetter).prefix(2).map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    private var years: String? {
        let cal = Calendar.current
        guard let birth else { return nil }
        let b = cal.component(.year, from: birth)
        if let death = person.deathDate { return "\(b)–\(cal.component(.year, from: death))" }
        if child?.onTheWay == true { return "på vej" }
        return "\(b)"
    }
}

/// Tilføj eller redigér en person og dennes relationer.
struct PersonEditView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let familyId: String
    let persons: [Person]
    let children: [Child]
    var members: [AppUser] = []
    var birthdays: [CustomBirthday] = []
    var editing: Person? = nil

    @State private var draft = Person(id: newId("person"), name: "")
    /// Medlemmer (forældrene i appen), som ikke allerede står i træet.
    private var unlinkedMembers: [AppUser] {
        members.filter { m in
            m.name != "Forælder" && !m.name.isEmpty
                && !persons.contains { $0.name.caseInsensitiveCompare(m.name) == .orderedSame && $0.id != draft.id }
        }
    }
    @State private var hasBirth = false
    @State private var birth = Date()
    @State private var hasDeath = false
    @State private var death = Date()
    @State private var saving = false
    @State private var saveError: String?
    @State private var confirmDelete = false

    private var others: [Person] { persons.filter { $0.id != draft.id }.sorted(by: FamilyTreeLayout.olderFirst) }
    private var unlinkedChildren: [Child] {
        children.filter { c in !persons.contains { $0.childId == c.id && $0.id != draft.id } }
    }

    var body: some View {
        NavigationStack {
            Form {
                Group {
                if editing == nil, !unlinkedMembers.isEmpty, draft.childId == nil, draft.name.isEmpty {
                    Section {
                        ForEach(unlinkedMembers) { m in
                            Button {
                                draft.name = m.name
                                // Fødselsdagen fra Mere → Dig, hvis den er sat (gemt som familie-fødselsdag).
                                if let b = birthdays.first(where: { $0.name.caseInsensitiveCompare(m.name) == .orderedSame }) {
                                    hasBirth = true; birth = b.date
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "person.circle").font(.title2).foregroundStyle(Theme.neutralDark)
                                    Text(m.name + (m.id == state.user?.id ? " (dig)" : ""))
                                    Spacer()
                                    Image(systemName: "plus.circle").foregroundStyle(Theme.muted)
                                }
                            }
                            .foregroundStyle(Theme.text)
                        }
                    } header: {
                        Text("Hurtigt: jer forældre")
                    }
                }

                if editing == nil, !unlinkedChildren.isEmpty, draft.childId == nil, draft.name.isEmpty {
                    Section {
                        ForEach(unlinkedChildren) { c in
                            Button {
                                draft.childId = c.id
                                draft.name = c.name
                                if let b = c.birthDate { hasBirth = true; birth = b }
                            } label: {
                                HStack { ChildAvatar(child: c, size: 32); Text(c.name); Spacer()
                                    Image(systemName: "plus.circle").foregroundStyle(Theme.muted) }
                            }
                            .foregroundStyle(Theme.text)
                        }
                    } header: {
                        Text("Hurtigt: et af jeres børn")
                    } footer: {
                        Text("Navn, billede og fødselsdag følger automatisk med fra barnets side.")
                    }
                }

                Section("Person") {
                    TextField("Navn", text: $draft.name)
                        .disabled(draft.childId != nil)
                    TextField("Rolle (fx Mormor, Farfar, Moster)", text: $draft.role)
                    if draft.childId == nil {
                        Toggle("Fødselsdato", isOn: $hasBirth.animation())
                        if hasBirth {
                            DatePicker("Født", selection: $birth, in: ...Date(), displayedComponents: .date)
                        }
                        Toggle("Er gået bort", isOn: $hasDeath.animation())
                        if hasDeath {
                            DatePicker("Død", selection: $death, in: ...Date(), displayedComponents: .date)
                        }
                        PhotoField(data: $draft.photo, title: "Vælg billede")
                    } else if let c = children.first(where: { $0.id == draft.childId }) {
                        HStack { ChildAvatar(child: c, size: 32); Text("Koblet til \(c.name)") }
                        Button("Fjern kobling", role: .destructive) { draft.childId = nil }
                    }
                }

                if !others.isEmpty {
                    Section {
                        relationPicker("Forælder 1", index: 0)
                        relationPicker("Forælder 2", index: 1)
                    } header: {
                        Text("Forældre")
                    } footer: {
                        Text("Vælg kun dem, der findes i træet. Et barn med kun én forælder her hænger under den forælder — fx i en sammenbragt familie.")
                    }

                    Section {
                        ForEach(Array(draft.partnerIds.enumerated()), id: \.offset) { i, id in
                            HStack {
                                Text(others.first { $0.id == id }?.name ?? "Ukendt")
                                Spacer()
                                Button(role: .destructive) { draft.partnerIds.remove(at: i) } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        Menu {
                            ForEach(others.filter { !draft.partnerIds.contains($0.id) }) { p in
                                Button(p.name) { draft.partnerIds.append(p.id) }
                            }
                        } label: {
                            Label("Tilføj partner", systemImage: "plus.circle")
                        }
                    } header: {
                        Text("Partnere")
                    } footer: {
                        Text("Nuværende og tidligere. Fælles børn hænger under parret.")
                    }
                }

                if editing != nil {
                    Section {
                        Button("Fjern fra træet", role: .destructive) { confirmDelete = true }
                    }
                }
                }.listRowBackground(Theme.card)
            }
            .themedList()
            .navigationTitle(editing == nil ? "Ny person" : "Redigér person")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annullér") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gem") { Task { await save() } }
                        .disabled(saving || draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Fjern personen fra træet?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Fjern", role: .destructive) { Task { await delete() } }
            }
            .saveErrorAlert($saveError)
            .onAppear {
                guard let editing else { return }
                draft = editing
                if let b = editing.birthDate { hasBirth = true; birth = b }
                if let d = editing.deathDate { hasDeath = true; death = d }
            }
        }
    }

    private func relationPicker(_ label: String, index: Int) -> some View {
        let current = draft.parentIds.indices.contains(index) ? draft.parentIds[index] : ""
        let otherParent = draft.parentIds.indices.contains(1 - index) ? draft.parentIds[1 - index] : ""
        return Picker(label, selection: Binding(
            get: { current },
            set: { value in
                var ids = draft.parentIds
                while ids.count < 2 { ids.append("") }
                ids[index] = value
                draft.parentIds = ids.filter { !$0.isEmpty }
            })) {
            Text("Ingen").tag("")
            ForEach(others.filter { $0.id != otherParent }) { p in
                Text(p.name + (p.role.isEmpty ? "" : " (\(p.role))")).tag(p.id)
            }
        }
    }

    private func save() async {
        draft.name = draft.name.trimmingCharacters(in: .whitespaces)
        draft.role = draft.role.trimmingCharacters(in: .whitespaces)
        draft.birthDate = hasBirth ? birth : nil
        draft.deathDate = hasDeath ? death : nil
        let person = draft
        await performSave(saving: $saving, errorMessage: $saveError, dismiss: dismiss) {
            try await state.store.savePerson(familyId: familyId, person)
        }
    }

    private func delete() async {
        let id = draft.id
        await performSave(saving: $saving, errorMessage: $saveError, dismiss: dismiss) {
            try await state.store.deletePerson(familyId: familyId, id: id)
            // Ryd henvisninger hos de andre, så træet ikke peger på en, der er væk.
            for var p in persons where p.parentIds.contains(id) || p.partnerIds.contains(id) {
                p.parentIds.removeAll { $0 == id }
                p.partnerIds.removeAll { $0 == id }
                try await state.store.savePerson(familyId: familyId, p)
            }
        }
    }
}
