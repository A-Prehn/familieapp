import SwiftUI

/// "Del med den anden forælder": ét barn deles for sig, så fx barnets anden forælder i et andet
/// hjem kun ser dét barn — ikke resten af familien. Første gang flyttes barnet til sin egen
/// iCloud-zone (kopi, bekræftelse, oprydning); familiens medlemmer beholder adgangen automatisk.
struct ChildAccessView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let child: Child

    @State private var people: [FamilyParticipant] = []
    @State private var shared = false
    @State private var busy = false
    @State private var moving = false
    @State private var loaded = false
    @State private var error: String?
    @State private var paywall: PaywallReason?
    @State private var removing: FamilyParticipant?

    private var cloud: CloudKitStore? { state.store as? CloudKitStore }

    var body: some View {
        List {
            Group {
            Section {
                Text("Til \(child.name)s anden forælder, som ikke er med i familien her. Den, du inviterer, ser kun \(child.name): dagbog, højdepunkter, billeder, interview og det andet under \(child.name). Resten af familien — minder, begivenheder, rejser og andre børn — kan de ikke se.")
                    .font(.footnote).foregroundStyle(Theme.muted)
                if !shared && loaded {
                    Text("Første gang flyttes \(child.name)s mindebog til sin egen plads i iCloud. Det tager et øjeblik, og alle i familien ser stadig \(child.name) som før.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                }
            } header: {
                Text("Sådan virker det")
            }

            if shared {
                Section {
                    if people.isEmpty && loaded {
                        Text("Ingen andre har adgang til \(child.name) endnu.").font(.footnote).foregroundStyle(Theme.muted)
                    }
                    ForEach(people) { person in row(person) }
                } header: {
                    Text("Hvem kan se \(child.name)")
                } footer: {
                    Text("Familiens medlemmer står her automatisk. Tryk på en person for at ændre adgang eller fjerne dem.")
                }
            }

            Section {
                Button { Task { await invite(.edit) } } label: {
                    inviteLabel("Invitér til at redigere", "Ser kun \(child.name) og kan skrive, lægge billeder op og rette.",
                                "person.badge.plus", Theme.tint)
                }
                Button { Task { await invite(.view) } } label: {
                    inviteLabel("Invitér med kun visning", "Ser kun \(child.name) og kan ikke ændre noget.",
                                "eye", Theme.green)
                }
            } header: {
                Text("Invitér forælder uden for familien")
            } footer: {
                Text("Invitationen sendes via Beskeder eller mail. Personen skal have en iPhone og trykke på linket.")
            }

            if let error {
                Section { Text(error).font(.footnote).foregroundStyle(Theme.rose) }
            }
            }.listRowBackground(Theme.card)
        }
        .themedList()
        .navigationTitle("\(child.name)s anden forælder")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Luk") { dismiss() } } }
        .interactiveDismissDisabled(moving)
        .overlay {
            if moving {
                VStack(spacing: 12) {
                    ProgressView().controlSize(.large)
                    Text("Flytter \(child.name)s mindebog…").font(.subheadline).foregroundStyle(Theme.text)
                    Text("Luk ikke appen. Billeder og videoer følger med.").font(.caption).foregroundStyle(Theme.muted)
                }
                .padding(24)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Theme.sep))
            } else if busy {
                ProgressView().controlSize(.large)
            }
        }
        .sheet(item: $paywall) { PaywallView(reason: $0) }
        .confirmationDialog(removing.map { "Fjern \($0.name)s adgang til \(child.name)?" } ?? "",
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible) {
            Button("Fjern", role: .destructive) { if let p = removing { Task { await remove(p) } } }
        }
        .task { await load() }
    }

    @ViewBuilder
    private func row(_ p: FamilyParticipant) -> some View {
        let content = HStack(spacing: 12) {
            Circle().fill(color(p.access).opacity(0.15)).frame(width: 36, height: 36)
                .overlay(Text(AboutPicker.initials(p.name)).font(.system(size: 13, weight: .semibold)).foregroundStyle(color(p.access)))
            VStack(alignment: .leading, spacing: 2) {
                Text(p.name + (p.isMe ? " (dig)" : "")).font(.subheadline.weight(.medium)).foregroundStyle(Theme.text)
                HStack(spacing: 6) {
                    Label(p.access.label, systemImage: icon(p.access))
                    if p.pending { Text("· Inviteret") }
                }
                .font(.caption).foregroundStyle(Theme.muted)
            }
            Spacer()
            if p.access != .owner { Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(Theme.muted) }
        }
        if p.access != .owner {
            Menu {
                Button { Task { await setAccess(p, readOnly: false) } } label: {
                    Label("Kan redigere", systemImage: p.access == .editor ? "checkmark" : "pencil")
                }
                Button { Task { await setAccess(p, readOnly: true) } } label: {
                    Label("Kun visning", systemImage: p.access == .viewer ? "checkmark" : "eye")
                }
                Divider()
                Button(role: .destructive) { removing = p } label: { Label("Fjern adgang", systemImage: "person.badge.minus") }
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

    // MARK: Handlinger

    private func load() async {
        guard let cloud else { loaded = true; return }
        shared = await cloud.childHasOwnZone(childId: child.id)
        if shared { people = (try? await cloud.childParticipants(childId: child.id)) ?? [] }
        loaded = true
    }

    private func invite(_ kind: CloudSharing.Invite) async {
        if !state.isPremium { paywall = .sharing; return }
        guard let cloud else { return }
        error = nil
        moving = !shared
        busy = true
        defer { busy = false; moving = false }
        do {
            let (share, container) = try await cloud.shareChild(childId: child.id, familyId: child.familyId)
            shared = true
            NotificationCenter.default.post(name: .storeDidChange, object: nil)
            CloudSharing.present(share: share, container: container, invite: kind, title: child.name) {
                Task { await load() }
            }
            await load()
        } catch {
            self.error = "Kunne ikke dele \(child.name): \(error.localizedDescription)"
        }
    }

    private func setAccess(_ p: FamilyParticipant, readOnly: Bool) async {
        guard let cloud else { return }
        busy = true
        defer { busy = false }
        do { try await cloud.setChildParticipant(childId: child.id, id: p.id, readOnly: readOnly); await load() }
        catch { self.error = "Kunne ikke ændre adgangen: \(error.localizedDescription)" }
    }

    private func remove(_ p: FamilyParticipant) async {
        guard let cloud else { return }
        busy = true
        defer { busy = false; removing = nil }
        do { try await cloud.removeChildParticipant(childId: child.id, id: p.id); await load() }
        catch { self.error = "Kunne ikke fjerne \(p.name): \(error.localizedDescription)" }
    }
}
