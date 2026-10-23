import SwiftUI

struct AboutMeView: View {
    @EnvironmentObject var state: AppState
    let child: Child
    @State private var answers: [String: String] = [:]
    @State private var editing: QuestionItem?

    struct QuestionItem: Identifiable {
        let question: String
        var id: String { question }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Constants.aboutMe) { section in
                    Text(section.title.uppercased())
                        .font(.caption2).tracking(1.4)
                        .foregroundStyle(Theme.muted)
                        .padding(.top, 24).padding(.bottom, 10).padding(.horizontal, 4)

                    VStack(spacing: 0) {
                        ForEach(Array(section.questions.enumerated()), id: \.element) { index, question in
                            if index > 0 { Divider() }
                            row(question)
                        }
                    }
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                    .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Theme.sep))
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Om dig")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing, onDismiss: { Task { await load() } }) { item in
            AnswerEditView(childId: child.id, question: item.question, answer: answers[item.question] ?? "")
        }
        .refreshable { await load() }
        .task { await load() }
        .reloadOnStoreChange { await load() }
    }

    private func row(_ question: String) -> some View {
        let answer = answers[question] ?? ""
        return VStack(alignment: .leading, spacing: 4) {
            Text(question).font(.footnote).foregroundStyle(Theme.muted)
            if answer.isEmpty {
                Text("Tryk for at svare").font(.subheadline).italic().foregroundStyle(Theme.muted.opacity(0.6))
            } else {
                Text(answer).font(.body).foregroundStyle(Theme.text)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .contentShape(Rectangle())
        .onTapGesture { if state.canEdit { editing = QuestionItem(question: question) } }
    }

    private func load() async {
        let cacheKey = "aboutme_\(child.id)"
        if answers.isEmpty, let cached = ScreenCache.load([String: String].self, key: cacheKey) { answers = cached }
        if let fresh = try? await state.store.answers(childId: child.id) {
            answers = fresh
            ScreenCache.save(fresh, key: cacheKey)
        }
    }
}

struct AnswerEditView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let childId: String
    let question: String
    @State var answer: String
    @State private var saving = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                Group {
                Section(question) {
                    TextField("Skriv svaret…", text: $answer, axis: .vertical)
                        .lineLimit(3...10)
                }
                }.listRowBackground(Theme.card)
            }
            .themedList()
            .navigationTitle("Svar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annullér") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gem") {
                        Task {
                            await performSave(saving: $saving, errorMessage: $saveError, dismiss: dismiss) {
                                try await state.store.setAnswer(childId: childId, question: question, answer: answer)
                            }
                        }
                    }
                    .disabled(saving)
                }
            }
            .saveErrorAlert($saveError)
        }
    }
}
