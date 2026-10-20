import SwiftUI
import CloudKit

@main
struct MindebogApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState()
    @StateObject private var comments = CommentsModel()
    @AppStorage(Appearance.key) private var appearance = Appearance.system.rawValue

    init() {
        // Sættes før fanebjælken findes — ellers vises ikonerne sorte, indtil siden tegnes igen.
        // Kun farven: ingen egen UITabBarAppearance, så iOS 26 beholder Liquid Glass.
        UITabBar.appearance().unselectedItemTintColor = UIColor(Theme.muted)
        WidgetSync.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .environmentObject(comments)
                .sheet(item: $comments.open) { target in
                    CommentsSheet(targetId: target.id, title: target.title)
                        .environmentObject(state)
                        .environmentObject(comments)
                }
                // Kommentarer fra de andre i familien: hent igen, når noget er gemt, og ved familieskift.
                .onReceive(NotificationCenter.default.publisher(for: .storeDidChange)) { _ in
                    Task { await comments.load(state: state, force: true) }
                }
                .onChange(of: state.familyId) { _, _ in Task { await comments.load(state: state, force: true) } }
                .tint(Theme.tint)
                // Lyst, mørkt eller følg system — vælges under Mere → Udseende.
                .preferredColorScheme(Appearance(rawValue: appearance)?.colorScheme)
                .task { await state.bootstrap() }
                .onReceive(NotificationCenter.default.publisher(for: .cloudKitShareAccepted)) { note in
                    if let zoneName = note.object as? String {
                        Task { await state.didAcceptShare(zoneName: zoneName) }
                    }
                }
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    // Vælges ved opstart: CloudKit når iCloud er logget ind, ellers hukommelse.
    @Published private(set) var store: Store = MemoryStore()
    @Published private(set) var usingCloud = false
    @Published private(set) var ready = false

    @Published var user: AppUser?
    @Published var familyId: String?
    @Published var errorMessage: String?
    /// false for "Kun visning" (fx bedsteforældre): tilføj/redigér/slet skjules overalt.
    @Published private(set) var canEdit: Bool =
        UserDefaults.standard.object(forKey: "mindebog.canEdit") as? Bool ?? true

    /// Læser ens adgang til familien fra iCloud (ejer / kan redigere / kun visning).
    func refreshPermissions() async {
        guard let familyId else { return }
        let value = await store.canEdit(familyId: familyId)
        canEdit = value
        UserDefaults.standard.set(value, forKey: "mindebog.canEdit")
        await refreshPremium()
    }

    // MARK: Premium

    /// Premium, hvis man selv har købt — eller hvis en anden i familien har (gemt på familien i iCloud).
    @Published private(set) var isPremium: Bool = UserDefaults.standard.bool(forKey: "mindebog.premium")
    /// Gratis-versionen: to børn. Flere børn, deling, video og PDF-bog kræver Premium.
    static let freeChildLimit = 2

    func refreshPremium() async {
        let purchases = Purchases.shared
        await purchases.refreshEntitlements()
        var premium = purchases.hasOwnPremium
        if let familyId {
            // Ens eget køb deles med familien, så partner og bedsteforældre også får glæde af det.
            if let own = purchases.ownUntil, own > Date() {
                try? await store.setFamilyPremium(familyId: familyId, until: own)
            }
            if let shared = await store.familyPremium(familyId: familyId), shared > Date() { premium = true }
        }
        isPremium = premium
        UserDefaults.standard.set(premium, forKey: "mindebog.premium")
    }

    private let userIdKey = "mindebog.userId"
    private let familyKey = "mindebog.familyId"
    private let usedCloudKey = "mindebog.usedCloud"

    func bootstrap() async {
        guard !ready else { return }
        let defaults = UserDefaults.standard

        // Hurtig vej: kendt bruger + familie fra sidst i iCloud → vis appen med det samme
        // og tjek iCloud/familie i baggrunden (skærmene viser deres cache imens).
        if defaults.bool(forKey: usedCloudKey),
           let savedId = defaults.string(forKey: userIdKey),
           let savedFamily = defaults.string(forKey: familyKey) {
            store = CloudKitStore()
            usingCloud = true
            user = try? await store.user(id: savedId)   // lokal opslag, intet netværk
            familyId = savedFamily
            ready = true
            Task { await verifyInBackground(userId: savedId, familyId: savedFamily) }
            return
        }

        let status = (try? await CKContainer(identifier: "iCloud.net.prehn.mindebog").accountStatus()) ?? .couldNotDetermine
        if status == .available {
            store = CloudKitStore()
            usingCloud = true
            defaults.set(true, forKey: usedCloudKey)
        }
        // Genskab session.
        if let savedId = defaults.string(forKey: userIdKey),
           let restored = try? await store.user(id: savedId) {
            user = restored
            let fams = (try? await store.families(for: restored.id)) ?? []
            let saved = defaults.string(forKey: familyKey)
            familyId = fams.first { $0.id == saved }?.id ?? fams.first?.id
        }
        ready = true
        Task { await publishDisplayName(); await refreshPermissions() }
    }

    /// Efter hurtig opstart: hvis iCloud er logget ud eller familien er væk, ret op.
    private func verifyInBackground(userId: String, familyId savedFamily: String) async {
        let status = (try? await CKContainer(identifier: "iCloud.net.prehn.mindebog").accountStatus()) ?? .couldNotDetermine
        if status == .noAccount {
            UserDefaults.standard.set(false, forKey: usedCloudKey)
            store = MemoryStore()
            usingCloud = false
            signOut()
            return
        }
        guard status == .available, let fams = try? await store.families(for: userId) else { return }
        if !fams.contains(where: { $0.id == savedFamily }) {
            setFamily(fams.first?.id)
        }
        await publishDisplayName()   // også for navne sat før denne version
        await refreshPermissions()
        // Første gang: hent iCloud-"change tokens", så notifikations-udvidelsen kun ser nyt.
        if NotificationManager.isEnabled { await ChangeFeed.seedIfNeeded() }
    }

    func signIn(name: String) async {
        do {
            let u = try await store.signIn(name: name)
            user = u
            UserDefaults.standard.set(u.id, forKey: userIdKey)
            let fams = (try? await store.families(for: u.id)) ?? []
            setFamily(fams.first?.id)
        } catch { errorMessage = error.localizedDescription }
    }

    func createFamily(name: String) async {
        guard let user else { return }
        do {
            let family = try await store.createFamily(userId: user.id, name: name)
            setFamily(family.id)
        } catch { errorMessage = error.localizedDescription }
    }

    /// Sletter familien (kun ejeren) og skifter til en anden familie — eller til opstart, hvis der ikke er flere.
    func deleteFamily(_ id: String) async throws {
        guard let user else { return }
        try await store.deleteFamily(familyId: id)
        ScreenCache.clear()
        let rest = ((try? await store.families(for: user.id)) ?? []).filter { $0.id != id }
        setFamily(rest.first?.id)
        NotificationCenter.default.post(name: .storeDidChange, object: nil)
    }

    func acceptInvite(code: String) async {
        guard let user else { return }
        do {
            let family = try await store.acceptInvite(userId: user.id, code: code)
            setFamily(family.id)
        } catch { errorMessage = error.localizedDescription }
    }

    /// Kaldes når brugeren har trykket på et delelink og iOS har accepteret delingen.
    func didAcceptShare(zoneName: String) async {
        guard let user else { return }
        // Et enkelt barn delt med én (den anden forælder): vis det under Børn.
        if zoneName.hasPrefix(CloudKitStore.childZonePrefix) {
            NotificationCenter.default.post(name: .storeDidChange, object: nil)
            return
        }
        let fams = (try? await store.families(for: user.id)) ?? []
        if let match = fams.first(where: { $0.id == zoneName }) {
            setFamily(match.id)
        }
    }

    /// Navnet bruges i hilsenen på Hjem. Gemmes lokalt på enheden (samme nøgle som CloudKitStore).
    func setDisplayName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, var current = user else { return }
        UserDefaults.standard.set(trimmed, forKey: "mindebog.displayName")
        current.name = trimmed
        user = current
        Task { await publishDisplayName() }
    }

    /// Gemmer navnet i familien, så de andre medlemmer ser det i stedet for "Deltager".
    func publishDisplayName() async {
        guard let user, let familyId, user.name != "Forælder" else { return }
        try? await store.setMemberName(familyId: familyId, userId: user.id, name: user.name)
    }

    func signOut() {
        user = nil
        familyId = nil
        UserDefaults.standard.removeObject(forKey: userIdKey)
        UserDefaults.standard.removeObject(forKey: familyKey)
        ScreenCache.clear()
    }

    /// Skift til en anden familie, man er med i (fx søsterens, man følger med kun visning).
    func switchFamily(_ id: String) {
        guard id != familyId else { return }
        ScreenCache.clear()          // så den forrige families skærme ikke vises et øjeblik
        setFamily(id)
        NotificationCenter.default.post(name: .storeDidChange, object: nil)
    }

    private func setFamily(_ id: String?) {
        familyId = id
        if let id { UserDefaults.standard.set(id, forKey: familyKey) }
        else { UserDefaults.standard.removeObject(forKey: familyKey) }
        if id != nil { Task { await publishDisplayName(); await refreshPermissions() } }   // fx lige efter man har accepteret en deling
    }
}
