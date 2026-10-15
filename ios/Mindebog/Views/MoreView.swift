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
    @State private var bellyInterval = Reminders.bellyInterval
    @State private var myBirthday: CustomBirthday?
    @State private var birthdayDraft = Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
    @State private var birthdayBusy = false

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
                    Label("Påmindelse om billeder", systemImage: "calendar.badge.clock")
                }
                if remindersOn {
                    Picker(selection: Binding(
                        get: { bellyInterval },
                        set: { value in
                            bellyInterval = value
                            Reminders.bellyInterval = value
                            Task { await rescheduleReminders() }
                        })) {
                        ForEach(Reminders.BellyInterval.allCases) { Text($0.label).tag($0) }
                    } label: {
                        Label("Mavebillede (barn på vej)", systemImage: "leaf")
                    }
                }
            } header: {
                Text("Notifikationer")
            } footer: {
                Text("Få besked når den anden forælder lægger noget nyt op. Påmindelsen kommer på hver månedsdag for børn, der er født — og for et barn på vej så ofte som du vælger, så I husker mavebilledet.")
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
                if state.familyId != nil && state.canEdit {
                    DatePicker("Din fødselsdag", selection: $birthdayDraft, in: ...Date(), displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "da_DK"))
                    if birthdayChanged {
                        Button(birthdayBusy ? "Gemmer…" : (myBirthday == nil ? "Tilføj fødselsdag" : "Gem fødselsdag")) {
                            Task { await saveMyBirthday() }
                        }
                        .disabled(birthdayBusy)
                    }
                }
            } header: {
                Text("Dig")
            } footer: {
                Text("Navnet bruges i hilsenen på forsiden. Din fødselsdag kommer med i familiens fødselsdage og i widgettens nedtælling.")
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
        if let id = UserDefaults.standard.string(forKey: myBirthdayKey(familyId)),
           let found = (try? await state.store.birthdays(familyId: familyId))?.first(where: { $0.id == id }) {
            myBirthday = found
            birthdayDraft = found.date
        }
        await refreshShare()
    }

    private func myBirthdayKey(_ familyId: String) -> String { "mindebog.myBirthday.\(familyId)" }

    private var birthdayChanged: Bool {
        guard let myBirthday else { return true }
        return !Calendar.current.isDate(myBirthday.date, inSameDayAs: birthdayDraft)
    }

    /// Forælderens egen fødselsdag gemmes som en almindelig familie-fødselsdag (navn = ens navn),
    /// så den anden forælder også ser den, og den kommer med i widgettens nedtælling.
    private func saveMyBirthday() async {
        guard let familyId = state.familyId else { return }
        birthdayBusy = true
        defer { birthdayBusy = false }
        let current = state.user?.name ?? ""
        let name = (current.isEmpty || current == "Forælder") ? "Mor/far" : current
        do {
            if var existing = myBirthday {
                existing.date = birthdayDraft
                existing.name = name
                try await state.store.updateBirthday(familyId: familyId, existing)
                myBirthday = existing
            } else {
                let created = try await state.store.addBirthday(familyId: familyId, name: name, date: birthdayDraft, emoji: "🎉")
                UserDefaults.standard.set(created.id, forKey: myBirthdayKey(familyId))
                myBirthday = created
            }
            await WidgetSync.refresh(store: state.store, familyId: familyId, familyName: family?.name ?? "")
        } catch {
            state.errorMessage = error.localizedDescription
        }
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

    private func rescheduleReminders() async {
        let kids = (try? await state.store.children(familyId: state.familyId ?? "")) ?? []
        await Reminders.schedule(children: kids)
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
