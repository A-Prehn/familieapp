import SwiftUI
import CloudKit

@main
struct MindebogApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .tint(Theme.tint)
                // Temaet er designet lyst (cream); et rigtigt mørkt tema kommer senere.
                .preferredColorScheme(.light)
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

    private let userIdKey = "mindebog.userId"
    private let familyKey = "mindebog.familyId"

    func bootstrap() async {
        guard !ready else { return }
        let status = (try? await CKContainer(identifier: "iCloud.net.prehn.mindebog").accountStatus()) ?? .couldNotDetermine
        if status == .available {
            store = CloudKitStore()
            usingCloud = true
        }
        // Genskab session.
        if let savedId = UserDefaults.standard.string(forKey: userIdKey),
           let restored = try? await store.user(id: savedId) {
            user = restored
            let fams = (try? await store.families(for: restored.id)) ?? []
            let saved = UserDefaults.standard.string(forKey: familyKey)
            familyId = fams.first { $0.id == saved }?.id ?? fams.first?.id
        }
        ready = true
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
        let fams = (try? await store.families(for: user.id)) ?? []
        if let match = fams.first(where: { $0.id == zoneName }) {
            setFamily(match.id)
        }
    }

    func signOut() {
        user = nil
        familyId = nil
        UserDefaults.standard.removeObject(forKey: userIdKey)
        UserDefaults.standard.removeObject(forKey: familyKey)
    }

    private func setFamily(_ id: String?) {
        familyId = id
        if let id { UserDefaults.standard.set(id, forKey: familyKey) }
        else { UserDefaults.standard.removeObject(forKey: familyKey) }
    }
}
