import SwiftUI

struct MoreView: View {
    @EnvironmentObject var state: AppState
    @State private var family: Family?
    @State private var members: [AppUser] = []
    @State private var invite: String?
    @State private var busy = false
    @State private var showQR = false
    @State private var notificationsOn = NotificationManager.isEnabled
    @State private var notificationMessage: String?
    @State private var notificationBusy = false

    var body: some View {
        List {
            Section("Familie") {
                Text(family?.name ?? "—").font(.headline)
                ForEach(members) { m in
                    Label(m.name + (m.id == state.user?.id ? " (dig)" : ""), systemImage: "person")
                }
            }

            Section("Del med den anden forælder") {
                if let invite, let url = URL(string: invite), state.usingCloud {
                    ShareLink(item: url) {
                        Label("Send delelink", systemImage: "square.and.arrow.up")
                    }
                    Button { showQR = true } label: {
                        Label("Vis QR-kode", systemImage: "qrcode")
                    }
                    Text("Send linket, eller lad partneren scanne QR-koden med iPhonens kamera. Så får de adgang til hele familien.")
                        .font(.footnote).foregroundStyle(Theme.muted)
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
            } header: {
                Text("Notifikationer")
            } footer: {
                Text("Få besked når den anden forælder lægger noget nyt op.")
            }

            Section("Konto") {
                if let user = state.user { Text("Logget ind som \(user.name)") }
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
        guard let familyId = state.familyId else { return }
        family = try? await state.store.families(for: state.user?.id ?? "").first { $0.id == familyId }
        members = (try? await state.store.members(familyId: familyId)) ?? []
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
                notificationMessage = "Notifikationer er slået fra for Mindebog. Slå dem til i iPhonens Indstillinger → Mindebog → Notifikationer."
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
