import SwiftUI

struct HighlightsView: View {
    @EnvironmentObject var state: AppState
    let child: Child
    @State private var items: [Highlight] = []
    @State private var showAdd = false

    var body: some View {
        ScrollView {
            if items.isEmpty {
                ContentUnavailableView("Ingen højdepunkter endnu", systemImage: "star")
                    .padding(.top, 60)
            } else {
                VStack(spacing: 12) {
                    ForEach(items) { h in
                        VStack(alignment: .leading, spacing: 4) {
                            if let date = h.date {
                                Text(date, style: .date).font(.caption).foregroundStyle(Theme.muted)
                            }
                            Text(h.text).font(.body).foregroundStyle(Theme.text)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.sep))
                    }
                }
                .padding(16)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Højdepunkter")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAdd, onDismiss: { Task { await load() } }) {
            AddHighlightView(childId: child.id)
        }
        .task { await load() }
    }

    private func load() async {
        items = (try? await state.store.highlights(childId: child.id)) ?? []
    }
}

struct AddHighlightView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let childId: String
    @State private var date = Date()
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Dato", selection: $date, displayedComponents: .date)
                Section("Tekst") {
                    TextField("Hvad skete der?", text: $text, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Nyt højdepunkt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annullér") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gem") {
                        Task {
                            _ = try? await state.store.addHighlight(childId: childId, date: date, text: text)
                            dismiss()
                        }
                    }
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
