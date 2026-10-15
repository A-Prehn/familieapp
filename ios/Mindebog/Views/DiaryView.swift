import SwiftUI

struct DiaryView: View {
    @EnvironmentObject var state: AppState
    let child: Child
    @State private var entries: [DiaryEntry] = []
    @State private var showAdd = false
    @State private var lightbox: LightboxState?

    var body: some View {
        ScrollView {
            if entries.isEmpty {
                ContentUnavailableView("Ingen indlæg endnu", systemImage: "book")
                    .padding(.top, 60)
            } else {
                VStack(spacing: 12) {
                    ForEach(entries) { entry in
                        card(entry)
                    }
                }
                .padding(16)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(child.onTheWay ? "Svangerskabsdagbog" : "Dagbog")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAdd, onDismiss: { Task { await load() } }) {
            AddDiaryView(childId: child.id)
        }
        .fullScreenCover(item: $lightbox) { LightboxView(state: $0) }
        .refreshable { await load() }
        .task { await load() }
    }

    private func card(_ entry: DiaryEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let photo = entry.photo {
                Color.clear
                    .aspectRatio(4.0 / 3.0, contentMode: .fit)
                    .overlay { DataImage(data: photo) }
                    .clipped()
                    .onTapGesture { lightbox = LightboxState(photos: [photo]) }
            }
            VStack(alignment: .leading, spacing: 4) {
                if let date = entry.date {
                    Text(Fmt.long(date)).font(.caption).foregroundStyle(Theme.muted)
                }
                Text(entry.text).font(.body).foregroundStyle(Theme.text)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.sep))
    }

    private func load() async {
        entries = (try? await state.store.diary(childId: child.id)) ?? []
    }
}

struct AddDiaryView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let childId: String
    @State private var date = Date()
    @State private var text = ""
    @State private var photo: Data?

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Dato", selection: $date, displayedComponents: .date)
                Section("Tekst") {
                    TextField("Skriv dit indlæg…", text: $text, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section("Billede") {
                    PhotoField(data: $photo)
                }
            }
            .navigationTitle("Nyt indlæg")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annullér") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gem") {
                        Task {
                            _ = try? await state.store.addDiary(childId: childId, date: date, text: text, photo: photo)
                            dismiss()
                        }
                    }
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty && photo == nil)
                }
            }
        }
    }
}
