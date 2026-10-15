import SwiftUI

struct MoreView: View {
    @EnvironmentObject var state: AppState
    @State private var family: Family?
    @State private var members: [AppUser] = []
    @State private var code: String?

    var body: some View {
        List {
            Section("Familie") {
                Text(family?.name ?? "—").font(.headline)
                ForEach(members) { m in
                    Label(m.name + (m.id == state.user?.id ? " (dig)" : ""), systemImage: "person")
                }
            }
            Section("Del med den anden forælder") {
                if let code {
                    HStack {
                        Spacer()
                        Text(code).font(.system(.title, design: .monospaced)).tracking(4)
                        Spacer()
                    }
                } else {
                    Button("Opret invitationskode") { Task { await makeInvite() } }
                }
                Text("Del koden, så I begge kan lægge op og se alt i realtid (CKShare i den rigtige app).")
                    .font(.footnote).foregroundStyle(Theme.muted)
            }
            Section("Konto") {
                if let user = state.user { Text("Logget ind som \(user.name)") }
                Button("Log ud / skift bruger", role: .destructive) { state.signOut() }
            }
            Section {
                Text("Prototype: data ligger lokalt. I den rigtige app gemmes alt i din egen iCloud via CloudKit.")
                    .font(.footnote).foregroundStyle(Theme.muted)
            }
        }
        .navigationTitle("Mere")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        guard let familyId = state.familyId else { return }
        family = try? await state.store.families(for: state.user?.id ?? "").first { $0.id == familyId }
        members = (try? await state.store.members(familyId: familyId)) ?? []
    }

    private func makeInvite() async {
        guard let user = state.user, let familyId = state.familyId else { return }
        code = try? await state.store.createInvite(userId: user.id, familyId: familyId)
    }
}
