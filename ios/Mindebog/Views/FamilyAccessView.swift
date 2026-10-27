import SwiftUI

/// "Familie og adgang": hvem der er med, hvad de må, og to tydelige måder at invitere på.
/// Erstatter Apples generelle delingsmenu, som var svær at forstå.
struct FamilyAccessView: View {
    @EnvironmentObject var state: AppState
    let familyName: String

    @State private var people: [FamilyParticipant] = []
    @State private var children: [Child] = []
    @State private var isOwner = false
    @State private var busy = false
    @State private var loaded = false
    @State private var error: String?
    @State private var paywall: PaywallReason?
    @State private var removing: FamilyParticipant?

    private var cloud: CloudKitStore? { state.store as? CloudKitStore }

    var body: some View {
        List {
            Group {
            Section {
                if !loaded {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if people.isEmpty {
                    Text("Familien er ikke delt med nogen endnu.").font(.footnote).foregroundStyle(Theme.muted)
                }
                ForEach(people) { person in row(person) }
            } header: {
                Text("Hvem er med")
            } footer: {
                if isOwner && people.count > 1 {
                    Text("Tryk på en person for at ændre deres adgang eller fjerne dem.")
                }
            }

            if isOwner {
                Section {
                    Button { Task { await invite(.edit) } } label: {
                        inviteLabel("Invitér til at redigere", "Fx din partner (gratis). Kan lægge op, ændre og slette.",
                                    "person.badge.plus", Theme.tint)
                    }
                    Button { Task { await invite(.view) } } label: {
                        inviteLabel("Invitér med kun visning", "Fx bedsteforældre (Premium). Kan se alt, men ikke ændre noget.",
                                    "eye", Theme.green)
                    }
                } header: {
                    Text("Invitér")
                } footer: {
                    Text("Invitationen sendes via Beskeder eller mail. Personen skal have en iPhone og trykke på linket for at komme med. Et barn med egen Apple-konto inviteres med kun visning — tryk bagefter på barnet i listen og vælg \"Det er et af børnene\". Så ser barnet sin egen bog først, \"(dig)\" ved sit navn, og først brevene, når de åbnes.")
                }
                Section {
                    ForEach(children) { child in
                        NavigationLink { ChildAccessView(child: child) } label: {
                            HStack(spacing: 12) {
                                ChildAvatar(child: child, size: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(child.name).font(.subheadline.weight(.medium)).foregroundStyle(Theme.text)
                                    Text(child.ownZone == nil ? "Ikke delt uden for familien" : "Delt — forælderen ser kun \(child.name), ikke resten af familien")
                                        .font(.caption).foregroundStyle(Theme.muted)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Forælder uden for familien")
                } footer: {
                    Text("Til sammenbragte familier: et barns anden forælder, der ikke er med i familien her, kan få adgang til KUN dét barn. De ser ikke andre børn, minder, begivenheder, rejser eller hvem der er i familien. Vælg barnet for at invitere.")
                }
            } else if loaded {
                Section {
                    Label(state.canEdit ? "Du kan redigere i familien." : "Du har kun visning af familien.",
                          systemImage: state.canEdit ? "pencil" : "eye")
                        .font(.footnote).foregroundStyle(Theme.neutralDark)
                } footer: {
                    Text("Kun den, der har oprettet familien, kan invitere og ændre adgang.")
                }
            }

            if let error {
                Section { Text(error).font(.footnote).foregroundStyle(Theme.rose) }
            }
            }.listRowBackground(Theme.card)
        }
        .themedList()
        .navigationTitle("Familie og adgang")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if busy { ProgressView().controlSize(.large) } }
        .sheet(item: $paywall) { PaywallView(reason: $0) }
        .confirmationDialog(removing.map { "Fjern \($0.name) fra familien?" } ?? "",
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible) {
            Button("Fjern", role: .destructive) {
                if let p = removing { Task { await remove(p) } }
            }
        } message: {
            Text("De kan ikke længere se familien. Det, de har lagt op, bliver liggende.")
        }
        .refreshable { await load() }
        .task { await load() }
    }

    // MARK: Rækker

    @ViewBuilder
    private func row(_ p: FamilyParticipant) -> some View {
        let content = HStack(spacing: 12) {
            Circle().fill(color(p.access).opacity(0.15)).frame(width: 36, height: 36)
                .overlay(Text(initials(p.name)).font(.system(size: 13, weight: .semibold)).foregroundStyle(color(p.access)))
            VStack(alignment: .leading, spacing: 2) {
                Text(p.name + (p.isMe ? " (dig)" : "")).font(.subheadline.weight(.medium)).foregroundStyle(Theme.text)
                HStack(spacing: 6) {
                    Label(p.access.label, systemImage: icon(p.access))
                    if p.pending { Text("· Inviteret") }
                    if let child = linkedChild(p) { Text("· \(child.name)s egen konto") }
                }
                .font(.caption).foregroundStyle(Theme.muted)
            }
            Spacer()
            if isOwner && p.access != .owner {
                Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(Theme.muted)
            }
        }

        if isOwner && p.access != .owner {
            Menu {
                Button { Task { await setAccess(p, readOnly: false) } } label: {
                    Label("Kan redigere", systemImage: p.access == .editor ? "checkmark" : "pencil")
                }
                Button { Task { await setAccess(p, readOnly: true) } } label: {
                    Label("Kun visning", systemImage: p.access == .viewer ? "checkmark" : "eye")
                }
                // Barnets egen konto (#48): koblet til barnets profil ser det "(dig)" og kun åbnede breve.
                if !p.pending, !children.isEmpty {
                    Divider()
                    Menu {
                        ForEach(children.filter { !$0.onTheWay }) { child in
                            Button { Task { await link(p, to: child) } } label: {
                                Label(child.name, systemImage: child.linkedUserId == p.id ? "checkmark" : "person")
                            }
                        }
                        if linkedChild(p) != nil {
                            Divider()
                            Button { Task { await link(p, to: nil) } } label: { Label("Er ikke et barn", systemImage: "xmark") }
                        }
                    } label: {
                        Label(linkedChild(p) == nil ? "Det er et af børnene …" : "Barn: \(linkedChild(p)!.name)",
                              systemImage: "figure.child")
                    }
                }
                Divider()
                Button(role: .destructive) { removing = p } label: {
                    Label("Fjern fra familien", systemImage: "person.badge.minus")
                }
            } label: { content }
        } else {
            content
        }
    }

    private func inviteLabel(_ title: String, _ detail: String, _ symbol: String, _ tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 17)).foregroundStyle(tint).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                Text(detail).font(.caption).foregroundStyle(Theme.muted)
            }
        }
        .padding(.vertical, 2)
    }

    private func color(_ a: FamilyParticipant.Access) -> Color {
        switch a { case .owner: Theme.rose; case .editor: Theme.tint; case .viewer: Theme.green }
    }
    private func icon(_ a: FamilyParticipant.Access) -> String {
        switch a { case .owner: "crown"; case .editor: "pencil"; case .viewer: "eye" }
    }
    private func initials(_ name: String) -> String { AboutPicker.initials(name) }

    // MARK: Handlinger

    private struct Cached: Codable { var people: [FamilyParticipant]; var isOwner: Bool }

    private func load() async {
        guard let cloud, let familyId = state.familyId else { loaded = true; return }
        // Vis listen fra sidst med det samme; delingen hentes så i baggrunden.
        let cacheKey = "access_\(familyId)"
        if people.isEmpty, let cached = ScreenCache.load(Cached.self, key: cacheKey) {
            people = cached.people
            isOwner = cached.isOwner
            loaded = true
        }
        async let ownerTask = cloud.isShareOwner(familyId: familyId)
        async let peopleTask = cloud.participants(familyId: familyId)
        children = (try? await state.store.children(familyId: familyId)) ?? []
        let owner = await ownerTask
        guard let fresh = try? await peopleTask else { loaded = true; return }
        isOwner = owner
        people = fresh
        loaded = true
        ScreenCache.save(Cached(people: fresh, isOwner: owner), key: cacheKey)
    }

    private func invite(_ kind: CloudSharing.Invite) async {
        // Gratis: én partner, der kan redigere. Bedsteforældre (kun visning) og flere personer kræver Premium.
        if !state.isPremium {
            let others = people.filter { $0.access != .owner }
            if kind != .edit || !others.isEmpty { paywall = .sharing; return }
        }
        guard let cloud, let familyId = state.familyId else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            let (share, container) = try await cloud.shareForSharing(familyId: familyId)
            CloudSharing.present(share: share, container: container, invite: kind,
                                 title: familyName.isEmpty ? "Vores familie" : familyName) {
                Task { await load() }
            }
        } catch {
            self.error = "Kunne ikke åbne invitationen: \(error.localizedDescription)"
        }
    }

    private func setAccess(_ p: FamilyParticipant, readOnly: Bool) async {
        guard let cloud, let familyId = state.familyId else { return }
        busy = true
        defer { busy = false }
        do {
            try await cloud.setParticipant(familyId: familyId, id: p.id, readOnly: readOnly)
            await load()
        } catch {
            self.error = "Kunne ikke ændre adgangen: \(error.localizedDescription)"
        }
    }

    private func linkedChild(_ p: FamilyParticipant) -> Child? {
        children.first { $0.linkedUserId == p.id }
    }

    /// Kobler deltageren til et barn (eller fjerner koblingen med nil). Kun ét barn pr. konto.
    private func link(_ p: FamilyParticipant, to child: Child?) async {
        busy = true
        defer { busy = false }
        do {
            for var other in children where other.linkedUserId == p.id && other.id != child?.id {
                other.linkedUserId = nil
                _ = try await state.store.updateChild(other)
            }
            if var child, child.linkedUserId != p.id {
                child.linkedUserId = p.id
                _ = try await state.store.updateChild(child)
            }
            await load()
        } catch {
            self.error = "Kunne ikke gemme: \(error.userMessage)"
        }
    }

    private func remove(_ p: FamilyParticipant) async {
        guard let cloud, let familyId = state.familyId else { return }
        busy = true
        defer { busy = false; removing = nil }
        do {
            try await cloud.removeParticipant(familyId: familyId, id: p.id)
            await load()
        } catch {
            self.error = "Kunne ikke fjerne \(p.name): \(error.localizedDescription)"
        }
    }
}
