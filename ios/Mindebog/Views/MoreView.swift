import SwiftUI

struct MoreView: View {
    @EnvironmentObject var state: AppState
    @State private var family: Family?
    @State private var members: [AppUser] = []
    @State private var invite: String?
    @State private var busy = false
    @State private var showQR = false
    @State private var shareIsPublic = false
    @State private var displayName = ""
    @State private var notificationsOn = NotificationManager.isEnabled
    @State private var notificationMessage: String?
    @State private var notificationBusy = false
    @State private var remindersOn = Reminders.isEnabled

    var body: some View {
        List {
            Section("Familie") {
                Text(family?.name ?? "—").font(.headline)
                ForEach(members) { m in
                    Label(m.name + (m.id == state.user?.id && !m.name.contains("dig") ? " (dig)" : ""), systemImage: "person")
                }
            }

            Section("Deling med familien") {
                if state.usingCloud {
                    Button { Task { await openSharing() } } label: {
                        Label(busy ? "Åbner…" : "Invitér og administrér deling", systemImage: "person.badge.plus")
                    }
                    .disabled(busy)
                    if shareIsPublic, let invite, let url = URL(string: invite) {
                        ShareLink(item: url) {
                            Label("Send delelink", systemImage: "square.and.arrow.up")
                        }
                        Button { showQR = true } label: {
                            Label("Vis QR-kode", systemImage: "qrcode")
                        }
                        Text("Alle med linket kan deltage. Lad partneren scanne QR-koden med iPhonens kamera.")
                            .font(.footnote).foregroundStyle(Theme.muted)
                    } else {
                        Text("Invitér partneren via Beskeder eller mail — så kan kun de åbne linket. Vil du bruge QR-kode, så vælg \"Alle med linket\" under delingsindstillinger.")
                            .font(.footnote).foregroundStyle(Theme.muted)
                    }
                    Text("Bedsteforældre og familie: invitér dem, og vælg \"Kun visning\" under Tilladelser — så kan de se alt, men ikke ændre noget.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                    if !state.canEdit {
                        Label("Du har kun visning af denne familie.", systemImage: "eye")
                            .font(.footnote).foregroundStyle(Theme.neutralDark)
                    }
                } else if let invite {
                    HStack {
                        Spacer()
                        Text(invite).font(.system(.title, design: .monospaced)).tracking(4)
                        Spacer()
                    }
                } else {
                    Button(busy ? "Opretter…" : "Opret delelink") { Task { await makeInvite() } }
                        .disabled(busy)
                }
                if let err = state.errorMessage {
                    Text(err).font(.footnote).foregroundStyle(Theme.rose)
                }
            }

            Section {
                Toggle(isOn: Binding(get: { notificationsOn }, set: { on in Task { await setNotifications(on) } })) {
                    Label("Nyt i familien", systemImage: "bell")
                }
                .disabled(notificationBusy || !state.usingCloud)
                if let notificationMessage {
                    Text(notificationMessage).font(.footnote).foregroundStyle(Theme.rose)
                }
                Toggle(isOn: Binding(get: { remindersOn }, set: { on in Task { await setReminders(on) } })) {
                    Label("Månedlig påmindelse", systemImage: "calendar.badge.clock")
                }
            } header: {
                Text("Notifikationer")
            } footer: {
                Text("Få besked når den anden forælder lægger noget nyt op — og en påmindelse på hver månedsdag (eller ny graviditetsuge), så I husker månedens billede.")
            }

            Section {
                TextField("Dit navn", text: $displayName)
                    .textContentType(.givenName)
                    .submitLabel(.done)
                    .onSubmit { state.setDisplayName(displayName) }
                if displayName.trimmingCharacters(in: .whitespaces) != (state.user?.name ?? "") {
                    Button("Gem navn") { state.setDisplayName(displayName) }
                        .disabled(displayName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Dit navn")
            } footer: {
                Text("Bruges i hilsenen på forsiden.")
            }

            Section("Konto") {
                Label(state.usingCloud ? "Data gemmes i din iCloud" : "Data gemmes kun i hukommelsen (ingen iCloud)",
                      systemImage: state.usingCloud ? "icloud" : "icloud.slash")
                    .font(.footnote).foregroundStyle(Theme.muted)
                Button("Log ud / skift bruger", role: .destructive) { state.signOut() }
            }
        }
        .navigationTitle("Mere")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showQR) {
            if let invite {
                NavigationStack {
                    VStack(spacing: 20) {
                        Text("Scan med kameraet")
                            .font(.serifTitle(22))
                        QRCodeView(text: invite)
                            .frame(maxWidth: 280)
                        Text("Partneren åbner kameraet på sin iPhone, peger på koden og trykker på linket, der dukker op.")
                            .font(.footnote).foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                        Spacer()
                    }
                    .padding(.top, 32)
                    .frame(maxWidth: .infinity)
                    .background(Theme.bg.ignoresSafeArea())
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Færdig") { showQR = false } }
                    }
                }
                .presentationDetents([.large])
            }
        }
        .task { await load() }
    }

    private func load() async {
        if displayName.isEmpty {
            let current = state.user?.name ?? ""
            displayName = current == "Forælder" ? "" : current
        }
        guard let familyId = state.familyId else { return }
        family = try? await state.store.families(for: state.user?.id ?? "").first { $0.id == familyId }
        members = (try? await state.store.members(familyId: familyId)) ?? []
        await refreshShare()
    }

    /// Læser delingens nuværende indstilling: link + QR vises kun ved "alle med linket".
    private func refreshShare() async {
        guard let cloud = state.store as? CloudKitStore, let familyId = state.familyId,
              let (share, _) = try? await cloud.shareForSharing(familyId: familyId) else { return }
        shareIsPublic = share.publicPermission != .none
        invite = share.url?.absoluteString
    }

    private func openSharing() async {
        guard let cloud = state.store as? CloudKitStore, let familyId = state.familyId else { return }
        busy = true
        state.errorMessage = nil
        do {
            let (share, container) = try await cloud.shareForSharing(familyId: familyId)
            CloudSharing.present(share: share, container: container) {
                Task { await load() }
            }
        } catch {
            state.errorMessage = error.localizedDescription
        }
        busy = false
    }

    private func setNotifications(_ on: Bool) async {
        notificationBusy = true
        notificationMessage = nil
        if on {
            switch await NotificationManager.enable() {
            case .enabled:
                notificationsOn = true
            case .denied:
                notificationsOn = false
                notificationMessage = "Notifikationer er slået fra for Vores familie. Slå dem til i iPhonens Indstillinger → Vores familie → Notifikationer."
            case .failed(let message):
                notificationsOn = false
                notificationMessage = "Kunne ikke slå notifikationer til: \(message)"
            }
        } else {
            await NotificationManager.disable()
            notificationsOn = false
        }
        notificationBusy = false
    }

    private func setReminders(_ on: Bool) async {
        notificationMessage = nil
        if on {
            let kids = (try? await state.store.children(familyId: state.familyId ?? "")) ?? []
            remindersOn = await Reminders.enable(children: kids)
            if !remindersOn {
                notificationMessage = "Notifikationer er slået fra for Vores familie. Slå dem til i iPhonens Indstillinger → Vores familie → Notifikationer."
            }
        } else {
            await Reminders.disable()
            remindersOn = false
        }
    }

    private func makeInvite() async {
        guard let user = state.user, let familyId = state.familyId else { return }
        busy = true
        state.errorMessage = nil
        do {
            invite = try await state.store.createInvite(userId: user.id, familyId: familyId)
        } catch {
            state.errorMessage = error.localizedDescription
        }
        busy = false
    }
}
