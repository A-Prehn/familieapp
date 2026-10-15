import SwiftUI

struct HighlightsView: View {
    @EnvironmentObject var state: AppState
    let child: Child
    @State private var items: [Highlight] = []
    @State private var showAdd = false
    @State private var lightbox: LightboxState?

    var body: some View {
        ScrollView {
            if items.isEmpty {
                ContentUnavailableView("Ingen højdepunkter endnu", systemImage: "star")
                    .padding(.top, 60)
            } else {
                // Tidslinje som på websitet; uden dato bruges oprettelsesåret.
                TimelineView(items: items,
                             year: { Calendar.current.component(.year, from: $0.date ?? $0.createdAt) }) { highlight in
                    card(highlight)
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
        .fullScreenCover(item: $lightbox) { LightboxView(state: $0) }
        .refreshable { await load() }
        .task { await load() }
    }

    private func card(_ highlight: Highlight) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let date = highlight.date {
                Text(Fmt.long(date)).font(.caption).foregroundStyle(Theme.muted)
            }
            Text(highlight.text)
                .font(.serifTitle(16))
                .foregroundStyle(Theme.text)
            ForEach(highlight.photos.indices, id: \.self) { index in
                Color.clear
                    .aspectRatio(4.0 / 3.0, contentMode: .fit)
                    .overlay { DataImage(data: highlight.photos[index]) }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onTapGesture {
                        lightbox = LightboxState(photos: highlight.photos, index: index)
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.sep))
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
    @State private var photos: [Data] = []

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Dato", selection: $date, displayedComponents: .date)
                Section("Tekst") {
                    TextField("Hvad skete der?", text: $text, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section("Billeder") {
                    MultiPhotoField(photos: $photos)
                }
            }
            .navigationTitle("Nyt højdepunkt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annullér") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gem") {
                        Task {
                            _ = try? await state.store.addHighlight(childId: childId, date: date, text: text, photos: photos)
                            dismiss()
                        }
                    }
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty && photos.isEmpty)
                }
            }
        }
    }
}
