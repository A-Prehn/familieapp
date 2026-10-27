import SwiftUI

struct MoreView: View {
    @EnvironmentObject var state: AppState
    @State private var family: Family?
    @State private var allFamilies: [Family] = []
    @State private var showNewFamily = false
    @State private var newFamilyName = ""
    @State private var showDeleteFamily = false
    @State private var deleteConfirmName = ""
    @State private var deleting = false
    @State private var deleteError: String?

    private var isFamilyOwner: Bool { family != nil && family?.ownerId == state.user?.id }

    /// Sletning af familien: man skal skrive familiens navn præcist, så man ikke sletter den forkerte.
    private var deleteFamilySheet: some View {
        let name = family?.name ?? ""
        let matches = !name.isEmpty && deleteConfirmName.trimmingCharacters(in: .whitespaces) == name
        return NavigationStack {
            Form {
                Group {
                Section {
                    Label("Det kan ikke fortrydes", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.rose).font(.headline)
                    Text("Hele familien \"\(name)\" slettes for altid: alle børn, billeder, video, dagbøger, minder, opskrifter og kommentarer. Den forsvinder også for alle, den er delt med\(members.count > 1 ? " (\(members.count - 1) andre)" : "").")
                        .font(.subheadline)
                    Text("Tag evt. en eksport først under Mere → Eksportér.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                }
                Section {
                    TextField(name, text: $deleteConfirmName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Skriv familiens navn for at bekræfte")
                }
                if let deleteError {
                    Section { Text(deleteError).font(.footnote).foregroundStyle(Theme.rose) }
                }
                Section {
                    Button(role: .destructive) {
                        Task {
                            deleting = true
                            defer { deleting = false }
                            do {
                                try await state.deleteFamily(state.familyId ?? "")
                                Haptics.success()
                                showDeleteFamily = false
                                await load()
                            } catch {
                                deleteError = SaveError.message(for: error)
                            }
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if deleting { ProgressView() } else { Text("Slet familien for altid").bold() }
                            Spacer()
                        }
                    }
                    .disabled(!matches || deleting)
                }
                }.listRowBackground(Theme.card)
            }
            .themedList()
            .navigationTitle("Slet familie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annullér") { showDeleteFamily = false } } }
            .interactiveDismissDisabled(deleting)
        }
    }
    @State private var members: [AppUser] = []
    @State private var invite: String?
    @State private var busy = false
    @State private var loading = false   // henter fra iCloud: vises øverst, så man kan se, at den arbejder (#58)
    @State private var showQR = false
    @State private var shareIsPublic = false
    @State private var displayName = ""
    @State private var notificationsOn = NotificationManager.isEnabled
    @State private var notificationMessage: String?
    @State private var notificationBusy = false
    @State private var remindersOn = Reminders.isEnabled
    @State private var bellyInterval = Reminders.bellyInterval
    @State private var bellyReminder = Reminders.bellyEnabled
    @State private var bellyWeekday = Reminders.bellyWeekday
    @State private var interviewReminder = Reminders.interviewEnabled
    @State private var onThisDay = OnThisDay.isEnabled
    @State private var weeklyQuestion = WeeklyQuestion.isEnabled
    @State private var winterWeek = SchoolHolidays.winterWeek
    @AppStorage(Appearance.key) private var appearance = Appearance.system.rawValue
    @State private var bellyTime: Date = {
        let m = Reminders.bellyMinutes
        return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
    }()
    @State private var myBirthday: CustomBirthday?
    @State private var birthdayDraft = Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
    @State private var birthdayBusy = false
    @State private var showExport = false
    @State private var paywall: PaywallReason?
    @State private var restoring = false
    @ObservedObject private var purchases = Purchases.shared

    var body: some View {
        List {
            Group {
            // Er man med i flere familier (fx sin egen og søsterens), kan man skifte her.
            if allFamilies.count > 1 {
                Section {
                    ForEach(allFamilies) { f in
                        Button {
                            state.switchFamily(f.id)
                            family = allFamilies.first { $0.id == f.id }; members = []   // den nye families data, ikke den gamles — listen bliver stående
                            Task { await load() }
                        } label: {
                            HStack {
                                Image(systemName: f.id == state.familyId ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(f.id == state.familyId ? Theme.green : Theme.muted)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(f.name).foregroundStyle(Theme.text)
                                    Text(f.ownerId == state.user?.id ? "Din familie" : "Delt med dig")
                                        .font(.caption).foregroundStyle(Theme.muted)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Skift familie")
                } footer: {
                    Text("Du er med i flere familier. Vælg, hvilken du vil se. Hjem, Børn og Familie viser den valgte.")
                }
            }

            // En familie mere (fx søskendes eller en demofamilie). Mere end én egen familie kræver Premium.
            Section {
                Button {
                    Task {
                        // Familierne hentes, hvis listen ikke er indlæst endnu — ellers kunne man snige sig forbi Premium.
                        var own = allFamilies.filter { $0.ownerId == state.user?.id }
                        if allFamilies.isEmpty, let fetched = try? await state.store.families(for: state.user?.id ?? "") {
                            own = fetched.filter { $0.ownerId == state.user?.id }
                        }
                        if !state.isPremium && !own.isEmpty { paywall = .family; return }
                        newFamilyName = ""; showNewFamily = true
                    }
                } label: {
                    Label("Opret ny familie", systemImage: "plus.circle")
                }
                if isFamilyOwner {
                    Button(role: .destructive) { deleteConfirmName = ""; showDeleteFamily = true } label: {
                        Label("Slet \(family?.name ?? "familien")", systemImage: "trash")
                    }
                }
            } footer: {
                Text("Hver familie er helt adskilt og har sine egne børn, minder og deling. Mere end én egen familie kræver Premium. Kun den, der har oprettet en familie, kan slette den.")
            }
            .sheet(isPresented: $showDeleteFamily) { deleteFamilySheet }
            .alert("Ny familie", isPresented: $showNewFamily) {
                TextField("Navn (fx Demo)", text: $newFamilyName)
                Button("Annullér", role: .cancel) {}
                Button("Opret") {
                    let name = newFamilyName.trimmingCharacters(in: .whitespaces)
                    Task {
                        ScreenCache.clear()
                        await state.createFamily(name: name.isEmpty ? "Ny familie" : name)
                        NotificationCenter.default.post(name: .storeDidChange, object: nil)
                        await load()
                    }
                }
            } message: {
                Text("Du skifter til den nye familie. Jeres nuværende familie bliver liggende urørt.")
            }

            Section {
                if state.usingCloud {
                    NavigationLink {
                        FamilyAccessView(familyName: family?.name ?? "")
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "person.2.fill").foregroundStyle(Theme.tint).frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(family?.name ?? "Familie og adgang").font(.headline)
                                Text(loading && members.isEmpty ? "Henter fra iCloud…" : membersSummary)
                                    .font(.caption).foregroundStyle(Theme.muted)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    if state.canEdit {
                        DisclosureGroup("Flere muligheder") {
                            Button { Task { await openSharing() } } label: {
                                Label(busy ? "Åbner…" : "Apples delingsindstillinger", systemImage: "gearshape")
                            }
                            .disabled(busy)
                            if shareIsPublic, let invite, let url = URL(string: invite) {
                                ShareLink(item: url) { Label("Send delelink", systemImage: "square.and.arrow.up") }
                                Button { showQR = true } label: { Label("Vis QR-kode", systemImage: "qrcode") }
                            }
                        }
                        .font(.subheadline)
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
            } header: {
                Text("Familie og adgang")
            } footer: {
                if state.usingCloud {
                    Text(state.canEdit ? "Se hvem der er med, invitér partneren eller bedsteforældre, og vælg hvem der kun må se."
                                       : "Du har kun visning af denne familie.")
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
                Text("Du får besked, når en anden i familien lægger noget nyt op, fx \"Sheila har tilføjet et højdepunkt for Theo\".")
            }

            Section {
                Toggle(isOn: Binding(get: { remindersOn }, set: { on in Task { await setReminders(on) } })) {
                    Label("Påmindelse om billeder", systemImage: "calendar.badge.clock")
                }
                if remindersOn {
                    Toggle(isOn: Binding(
                        get: { bellyReminder },
                        set: { on in
                            bellyReminder = on
                            Reminders.bellyEnabled = on
                            Task { await rescheduleReminders() }
                        })) {
                        Label("Mavebillede (barn på vej)", systemImage: "leaf")
                    }
                }
                if remindersOn && bellyReminder {
                    Picker(selection: Binding(
                        get: { bellyInterval },
                        set: { value in
                            bellyInterval = value
                            Reminders.bellyInterval = value
                            Task { await rescheduleReminders() }
                        })) {
                        ForEach(Reminders.BellyInterval.allCases) { Text($0.label).tag($0) }
                    } label: {
                        Label("Hvor ofte", systemImage: "repeat")
                    }
                    Picker(selection: Binding(
                        get: { bellyWeekday },
                        set: { value in
                            bellyWeekday = value
                            Reminders.bellyWeekday = value
                            Task { await rescheduleReminders() }
                        })) {
                        ForEach(Reminders.weekdayOptions) { Text($0.label).tag($0.value) }
                    } label: {
                        Label("Ugedag", systemImage: "calendar")
                    }
                    DatePicker(selection: Binding(
                        get: { bellyTime },
                        set: { value in
                            bellyTime = value
                            let c = Calendar.current.dateComponents([.hour, .minute], from: value)
                            Reminders.bellyMinutes = (c.hour ?? 10) * 60 + (c.minute ?? 0)
                            Task { await rescheduleReminders() }
                        }), displayedComponents: .hourAndMinute) {
                        Label("Tidspunkt", systemImage: "clock")
                    }
                    .environment(\.locale, Locale(identifier: "da_DK"))
                }
                if remindersOn {
                    Toggle(isOn: Binding(
                        get: { interviewReminder },
                        set: { on in
                            interviewReminder = on
                            Reminders.interviewEnabled = on
                            Task { await rescheduleReminders() }
                        })) {
                        Label("Årligt interview", systemImage: "bubble.left.and.text.bubble.right")
                    }
                    Toggle(isOn: Binding(
                        get: { weeklyQuestion },
                        set: { on in
                            weeklyQuestion = on
                            WeeklyQuestion.isEnabled = on
                            Task { await rescheduleReminders() }
                        })) {
                        Label("Ugens spørgsmål", systemImage: "questionmark.bubble")
                    }
                    // Skoleferierne bruges til ugens spørgsmål og et kort på Hjem; kun vinterferien varierer.
                    Picker(selection: Binding(
                        get: { winterWeek },
                        set: { w in
                            winterWeek = w
                            SchoolHolidays.winterWeek = w
                            Task { await rescheduleReminders() }
                        })) {
                        Text("Uge 7").tag(7)
                        Text("Uge 8").tag(8)
                    } label: {
                        Label("Vinterferie", systemImage: "snowflake")
                    }
                    Toggle(isOn: Binding(
                        get: { onThisDay },
                        set: { on in
                            onThisDay = on
                            OnThisDay.isEnabled = on
                            NotificationCenter.default.post(name: .storeDidChange, object: nil)   // Hjem planlægger igen
                        })) {
                        Label("På denne dag", systemImage: "calendar.badge.clock")
                    }
                }
            } header: {
                Text("Påmindelser")
            } footer: {
                Text("Billeder: for et født barn hver måned på månedsdagen, og for et barn på vej så ofte, på den ugedag og det tidspunkt, du vælger — mavebilledet kan slås fra, hvis det ikke er dig, der tager det. Årligt interview: på hvert barns fødselsdag fra \(Reminders.interviewMinAge) år, og en uge efter, hvis I ikke er gået i gang. Ugens spørgsmål: lørdag kl. 10 et spørgsmål, der passer til barnets alder — tryk, og dagbogen åbner med spørgsmålet. På denne dag: kl. 9 på årsdagen for et minde fra et tidligere år. Vinterferie: uge 7 i det meste af landet, uge 8 i København og omegn — bruges til ugens spørgsmål efter ferien.")
            }

            Section {
                Picker(selection: $appearance) {
                    ForEach(Appearance.allCases) { Text($0.label).tag($0.rawValue) }
                } label: {
                    Label("Udseende", systemImage: "circle.lefthalf.filled")
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Udseende")
            } footer: {
                Text("Følg system skifter sammen med telefonen mellem lyst og mørkt.")
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

            Section {
                if state.isPremium {
                    Label(premiumText, systemImage: "heart.circle.fill")
                        .foregroundStyle(Theme.rose)
                    if purchases.hasOwnPremium && !purchases.ownsLifetime {
                        Button("Administrér abonnement") {
                            if let url = URL(string: "https://apps.apple.com/account/subscriptions") { UIApplication.shared.open(url) }
                        }
                    }
                } else {
                    Button { paywall = .general } label: {
                        Label("Få Premium", systemImage: "heart.circle")
                    }
                    Button(restoring ? "Gendanner…" : "Gendan køb") {
                        Task {
                            restoring = true
                            _ = await purchases.restore()
                            await state.refreshPremium()
                            restoring = false
                        }
                    }
                    .disabled(restoring)
                }
            } header: {
                Text("Premium")
            } footer: {
                Text(state.isPremium
                     ? "Premium gælder for hele familien, også dem I har delt med."
                     : "Gratis: to børn med alle sektioner, og din partner kan være med. Premium: flere børn, flere familier, deling med bedsteforældre og resten af familien, video, film og PDF-mindebog.")
            }

            Section {
                Button { showExport = true } label: {
                    Label("Eksportér alt", systemImage: "square.and.arrow.down.on.square")
                }
                .disabled(state.familyId == nil)
            } header: {
                Text("Dine data")
            } footer: {
                Text("Hent alle billeder, videoer, tekster og mindebøger ud i én ZIP-fil — fx som backup, eller hvis I en dag vil stoppe med appen.")
            }

            Section("Konto") {
                Label(state.usingCloud ? "Data gemmes i din iCloud" : "Data gemmes kun i hukommelsen (ingen iCloud)",
                      systemImage: state.usingCloud ? "icloud" : "icloud.slash")
                    .font(.footnote).foregroundStyle(Theme.muted)
                Button("Log ud / skift bruger", role: .destructive) { state.signOut() }
            }
            }.listRowBackground(Theme.card)
        }
        .themedList()
        .navigationTitle("Mere")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if loading { ProgressView().tint(Theme.muted) }
            }
        }
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
        .sheet(isPresented: $showExport) { ExportView() }
        .sheet(item: $paywall) { PaywallView(reason: $0) }
        .task { await load() }
        .reloadOnStoreChange { await load() }
    }

    private func load() async {
        if displayName.isEmpty {
            let current = state.user?.name ?? ""
            displayName = current == "Forælder" ? "" : current
        }
        guard let familyId = state.familyId else { return }
        // Vis det sidst viste med det samme; alt hentes så samtidig i baggrunden.
        let cacheKey = "more_\(familyId)"
        if members.isEmpty, let cached = ScreenCache.load(MoreCache.self, key: cacheKey) {
            family = cached.family; members = cached.members
            myBirthday = cached.myBirthday; invite = cached.invite; shareIsPublic = cached.shareIsPublic
            if let b = cached.myBirthday { birthdayDraft = b.date }
        }
        // Familierne fra sidst (gemt på enheden) vises med det samme — iCloud opdaterer listen bagefter (#58).
        if !state.families.isEmpty {
            allFamilies = sortedFamilies(state.families, current: familyId)
            if family == nil { family = state.families.first { $0.id == familyId } }
        }
        let store = state.store
        let userId = state.user?.id ?? ""
        let birthdayId = UserDefaults.standard.string(forKey: myBirthdayKey(familyId))
        loading = true
        defer { loading = false }
        async let familiesTask = store.families(for: userId)
        async let membersTask = store.members(familyId: familyId)
        async let birthdaysTask: [CustomBirthday]? = birthdayId == nil ? nil : (try? await store.birthdays(familyId: familyId))
        // Kun læsning: delingen rettes først, når man åbner delingsindstillingerne (#58).
        async let shareTask: (isPublic: Bool, url: String?)? = (store as? CloudKitStore)?.shareInfo(familyId: familyId)
        if let fetched = try? await familiesTask {
            state.rememberFamilies(fetched)
            family = fetched.first { $0.id == familyId }
            allFamilies = sortedFamilies(fetched, current: familyId)
        }
        if let m = try? await membersTask { members = m }
        if let id = birthdayId, let found = (await birthdaysTask)?.first(where: { $0.id == id }) {
            myBirthday = found
            birthdayDraft = found.date
        }
        if let info = await shareTask { shareIsPublic = info.isPublic; invite = info.url }
        ScreenCache.save(MoreCache(family: family, families: allFamilies, members: members, myBirthday: myBirthday,
                                   invite: invite, shareIsPublic: shareIsPublic), key: cacheKey)
    }

    /// Alle familier vises — også tomme egne (fx en testfamilie), så de kan vælges og slettes. Den valgte først.
    private func sortedFamilies(_ fams: [Family], current: String) -> [Family] {
        fams.sorted { a, b in
            if (a.id == current) != (b.id == current) { return a.id == current }
            return a.name.localizedCompare(b.name) == .orderedAscending
        }
    }

    private struct MoreCache: Codable {
        var family: Family?; var families: [Family]; var members: [AppUser]; var myBirthday: CustomBirthday?
        var invite: String?; var shareIsPublic: Bool
    }

    private func myBirthdayKey(_ familyId: String) -> String { "mindebog.myBirthday.\(familyId)" }

    /// "3 personer · 1 med kun visning"
    private var membersSummary: String {
        let viewers = members.filter { $0.name.contains("kun visning") }.count
        let count = members.count
        var text = count == 1 ? "Kun dig" : "\(count) personer"
        if viewers > 0 { text += " · \(viewers) med kun visning" }
        return text
    }

    private var premiumText: String {
        if purchases.ownsLifetime { return "Premium for altid" }
        if purchases.hasOwnPremium { return "Premium (abonnement)" }
        return "Premium via familien"
    }

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
            await WidgetSync.refresh(store: state.store, familyId: familyId, familyName: family?.name ?? "", force: true)
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
        // Gratis: én partner, der kan redigere. Flere personer og kun-visning kræver Premium.
        if !state.isPremium && members.count > 1 { paywall = .sharing; return }
        guard let cloud = state.store as? CloudKitStore, let familyId = state.familyId else { return }
        busy = true
        state.errorMessage = nil
        do {
            let (share, container) = try await cloud.shareForSharing(familyId: familyId)
            CloudSharing.present(share: share, container: container, invite: state.isPremium ? .all : .edit) {
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
        await Reminders.schedule(children: kids, force: true)
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
