import SwiftUI

@main
struct MindebogApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .tint(Theme.tint)
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    // Datalag: MemoryStore til simulator/build. Skiftes til CloudKitStore i fase 2b.
    let store: Store = MemoryStore()

    @Published var user: AppUser?
    @Published var familyId: String?
    @Published var errorMessage: String?

    func signIn(name: String) async {
        do {
            user = try await store.signIn(name: name)
            familyId = nil
        } catch { errorMessage = error.localizedDescription }
    }

    func createFamily(name: String) async {
        guard let user else { return }
        do {
            let family = try await store.createFamily(userId: user.id, name: name)
            familyId = family.id
        } catch { errorMessage = error.localizedDescription }
    }

    func acceptInvite(code: String) async {
        guard let user else { return }
        do {
            let family = try await store.acceptInvite(userId: user.id, code: code)
            familyId = family.id
        } catch { errorMessage = error.localizedDescription }
    }

    func signOut() {
        user = nil
        familyId = nil
    }
}
