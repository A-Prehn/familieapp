import SwiftUI

// Reaktioner og kommentarer fra familien — også bedsteforældre med "kan redigere".
// Alle familiens kommentarer hentes én gang (CommentsModel) og vises som en lille linje
// under hvert kort: "❤️ 2 · 💬 1". Tryk åbner arket med reaktioner, kommentarer og felt.

/// Familiens kommentarer, samlet ét sted og hentet én gang pr. familie.
@MainActor
final class CommentsModel: ObservableObject {
    @Published private(set) var byTarget: [String: [Comment]] = [:]
    /// Det åbne ark. Vises fra appens rod (ikke inde fra kortet, hvor det arvede kortets bredde).
    @Published var open: OpenTarget?
    struct OpenTarget: Identifiable { let id: String; let title: String }
    /// Fejl ved sidste gem (fx "Kun visning") — vises i arket.
    @Published var lastError: String?
    private var loadedFamily: String?
    private var loading = false
    private var reloadWanted = false

    func comments(for targetId: String) -> [Comment] { byTarget[targetId] ?? [] }

    func load(state: AppState, force: Bool = false) async {
        guard let familyId = state.familyId else { return }
        if loading { if force { reloadWanted = true }; return }   // kører allerede: hent igen bagefter
        if !force, loadedFamily == familyId { return }
        loading = true
        defer { loading = false }
        let cacheKey = "comments_\(familyId)"
        if byTarget.isEmpty, let cached = ScreenCache.load([Comment].self, key: cacheKey) { apply(cached) }
        if let fresh = try? await state.store.comments(familyId: familyId) {
            apply(fresh)
            loadedFamily = familyId
            ScreenCache.save(fresh, key: cacheKey)
        }
        if reloadWanted {
            reloadWanted = false
            loading = false
            await load(state: state, force: true)
        }
    }

    private func apply(_ list: [Comment]) {
        byTarget = Dictionary(grouping: list, by: \.targetId)
    }

    /// Slår en reaktion til eller fra for den, der er logget ind.
    func toggleReaction(_ emoji: String, on targetId: String, state: AppState) async {
        guard let familyId = state.familyId, let user = state.user else { return }
        // Vises med det samme; går gemningen galt, rulles det tilbage, og fejlen vises i arket.
        lastError = nil
        if let mine = comments(for: targetId).first(where: { $0.isReaction && $0.emoji == emoji && $0.authorId == user.id }) {
            byTarget[targetId]?.removeAll { $0.id == mine.id }
            do { try await state.store.deleteComment(familyId: familyId, id: mine.id) }
            catch { byTarget[targetId, default: []].append(mine); lastError = SaveError.message(for: error) }
        } else {
            let c = Comment(id: newId("re"), targetId: targetId, emoji: emoji, authorId: user.id, authorName: user.name)
            byTarget[targetId, default: []].append(c)
            Haptics.light()
            do { try await state.store.addComment(familyId: familyId, c) }
            catch { byTarget[targetId]?.removeAll { $0.id == c.id }; lastError = SaveError.message(for: error) }
        }
    }

    func add(text: String, on targetId: String, state: AppState) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let familyId = state.familyId, let user = state.user else { return }
        lastError = nil
        let c = Comment(id: newId("co"), targetId: targetId, text: trimmed, authorId: user.id, authorName: user.name)
        byTarget[targetId, default: []].append(c)
        do { try await state.store.addComment(familyId: familyId, c) }
        catch { byTarget[targetId]?.removeAll { $0.id == c.id }; lastError = SaveError.message(for: error) }
    }

    func delete(_ comment: Comment, state: AppState) async {
        guard let familyId = state.familyId else { return }
        lastError = nil
        byTarget[comment.targetId]?.removeAll { $0.id == comment.id }
        do { try await state.store.deleteComment(familyId: familyId, id: comment.id) }
        catch { byTarget[comment.targetId, default: []].append(comment); lastError = SaveError.message(for: error) }
    }
}

/// Linjen under et kort: reaktioner med antal og antal kommentarer. Tryk åbner arket.
struct CommentsBar: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var comments: CommentsModel
    let targetId: String
    let title: String

    var body: some View {
        let list = comments.comments(for: targetId)
        let reactions = list.filter(\.isReaction)
        let texts = list.filter { !$0.isReaction }
        Button { comments.open = .init(id: targetId, title: title) } label: {
            HStack(spacing: 8) {
                if reactions.isEmpty && texts.isEmpty {
                    Label("Reagér", systemImage: "heart")
                } else {
                    ForEach(Comment.reactions, id: \.self) { emoji in
                        let n = reactions.filter { $0.emoji == emoji }.count
                        if n > 0 { Text("\(emoji) \(n)") }
                    }
                    if !texts.isEmpty { Label("\(texts.count)", systemImage: "bubble.left") }
                }
            }
            .font(.caption)
            .foregroundStyle(Theme.muted)
            .padding(.vertical, 2)
        }
        .buttonStyle(.borderless)
        .task { await comments.load(state: state) }
    }
}

/// Arket: reaktioner øverst, kommentarerne under, og et felt til en ny.
struct CommentsSheet: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var comments: CommentsModel
    @Environment(\.dismiss) private var dismiss
    let targetId: String
    let title: String
    @State private var draft = ""

    var body: some View {
        let list = comments.comments(for: targetId)
        let reactions = list.filter(\.isReaction)
        let texts = list.filter { !$0.isReaction }
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(title).font(.serifTitle(18)).foregroundStyle(Theme.text).lineLimit(3)

                    // Reaktioner: ét tryk slår ens egen til eller fra.
                    HStack(spacing: 8) {
                        ForEach(Comment.reactions, id: \.self) { emoji in
                            let mine = reactions.contains { $0.emoji == emoji && $0.authorId == state.user?.id }
                            let n = reactions.filter { $0.emoji == emoji }.count
                            Button {
                                Task { await comments.toggleReaction(emoji, on: targetId, state: state) }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(emoji)
                                    if n > 0 { Text("\(n)").font(.caption.weight(.semibold)) }
                                }
                                .padding(.horizontal, 10).padding(.vertical, 7)
                                .background(Capsule().fill(mine ? Theme.rose.opacity(0.18) : Theme.bgDark))
                                .overlay(Capsule().stroke(mine ? Theme.rose : Theme.sep))
                            }
                            .buttonStyle(.plain)
                            .disabled(!state.canEdit)
                        }
                    }
                    if !reactions.isEmpty {
                        Text(reactions.map(\.authorName).uniqued().joined(separator: ", "))
                            .font(.caption).foregroundStyle(Theme.muted)
                    }

                    if texts.isEmpty {
                        Text("Ingen kommentarer endnu.").font(.footnote).foregroundStyle(Theme.muted)
                    }
                    ForEach(texts) { c in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(c.authorName).font(.caption.weight(.semibold)).foregroundStyle(Theme.text)
                                Spacer()
                                Text(Fmt.long(c.createdAt)).font(.caption2).foregroundStyle(Theme.muted)
                            }
                            Text(c.text).font(.footnote).foregroundStyle(Theme.text)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Theme.sep))
                        .contextMenu {
                            if c.authorId == state.user?.id {
                                Button(role: .destructive) { Task { await comments.delete(c, state: state) } } label: {
                                    Label("Slet", systemImage: "trash")
                                }
                            }
                        }
                    }

                    if !state.canEdit {
                        Text("Med \"Kun visning\" kan man ikke reagere eller kommentere. Bed ejeren om adgangen \"Kan redigere\".")
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                    if let err = comments.lastError {
                        Text("Kunne ikke gemme: \(err)").font(.caption).foregroundStyle(Theme.rose)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.bg.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                if state.canEdit {
                    HStack(spacing: 8) {
                        TextField("Skriv en kommentar…", text: $draft, axis: .vertical)
                            .lineLimit(1...4)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Theme.card)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.large))
                            .overlay(RoundedRectangle(cornerRadius: Radius.large).stroke(Theme.sep))
                        Button {
                            let text = draft
                            draft = ""
                            Task { await comments.add(text: text, on: targetId, state: state) }
                        } label: {
                            Image(systemName: "arrow.up.circle.fill").font(.title2)
                        }
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(12)
                    .background(Theme.bg)
                }
            }
            .navigationTitle("Reaktioner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Luk") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.bg)
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}
