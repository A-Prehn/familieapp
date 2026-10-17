import SwiftUI
import PhotosUI

/// "Fødselsdage" under et barn: vælg fødselsdagen øverst (1 år, 2 år …) og se eller tilføj
/// billederne fra netop den dag. Gemmes som billedserie med alderen som billedtekst.
struct BirthdayPhotosView: View {
    @EnvironmentObject var state: AppState
    @Namespace private var zoomNS   // zoom-overgang til fuld skærm (iOS 18)
    let child: Child

    @State private var items: [GalleryItem] = []
    @State private var age: Int = 1
    @State private var loaded = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showSuggestions = false
    @State private var showPicker = false
    @State private var loadingItems = true
    @State private var adding = 0
    @State private var editing: GalleryItem?
    @State private var lightbox: LightboxState?
    @State private var error: String?

    private let columns = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]

    /// Antal fødselsdage indtil nu (mindst 1, så man kan forberede den første).
    private var currentAge: Int {
        guard let birth = child.birthDate else { return 1 }
        return max(1, Calendar.current.dateComponents([.year], from: birth, to: Date()).year ?? 1)
    }
    private var ages: [Int] {
        let withPhotos = Set(items.compactMap { Int($0.caption) })
        return Array(1...max(currentAge, withPhotos.max() ?? 1)).reversed()
    }
    private var forAge: [GalleryItem] {
        items.filter { Int($0.caption) == age }.sorted { $0.shownDate < $1.shownDate }
    }
    private func count(_ a: Int) -> Int { items.filter { Int($0.caption) == a }.count }

    private var birthdayDate: Date? {
        child.birthDate.flatMap { Calendar.current.date(byAdding: .year, value: age, to: $0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Vælg fødselsdag
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ages, id: \.self) { a in
                            Button { withAnimation(.easeInOut(duration: 0.15)) { age = a } } label: {
                                VStack(spacing: 2) {
                                    Text(a == 1 ? "1 år" : "\(a) år").font(.system(size: 15, weight: .semibold))
                                    Text(count(a) == 0 ? "–" : "\(count(a))").font(.caption2)
                                        .foregroundStyle(age == a ? Theme.bg.opacity(0.8) : Theme.muted)
                                }
                                .frame(minWidth: 52)
                                .padding(.vertical, 8).padding(.horizontal, 10)
                                .background(RoundedRectangle(cornerRadius: 12).fill(age == a ? Theme.rose : Theme.card))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(age == a ? Theme.rose : Theme.sep))
                                .foregroundStyle(age == a ? Color.white : Theme.text)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 2)
                }

                // Overskrift for den valgte fødselsdag
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(child.name) fylder \(age)").font(.serifTitle(22)).foregroundStyle(Theme.text)
                    if let d = birthdayDate { Text(Fmt.long(d)).font(.caption).foregroundStyle(Theme.muted) }
                }

                if adding > 0 {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Gemmer \(adding) billede\(adding == 1 ? "" : "r")…").font(.footnote).foregroundStyle(Theme.muted)
                    }
                }

                if items.isEmpty && loadingItems {
                    ShimmerGrid(columns: 3).padding(-16)
                } else if forAge.isEmpty && adding == 0 {
                    VStack(spacing: 10) {
                        Image(systemName: "gift").font(.system(size: 34, weight: .light)).foregroundStyle(Theme.rose)
                        Text("Ingen billeder fra \(age)-års fødselsdagen endnu.")
                            .font(.subheadline).foregroundStyle(Theme.muted)
                        if state.canEdit {
                            Button { showPicker = true } label: {
                                Label("Tilføj billeder", systemImage: "photo.badge.plus")
                            }
                            .buttonStyle(.borderedProminent)
                            .padding(.top, 4)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                } else {
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(Array(forAge.enumerated()), id: .element.id) { i, item in
                            Color.clear
                                .aspectRatio(1, contentMode: .fit)
                                .overlay { if let p = item.photo { DataImage(data: p) } else { Theme.bgDark } }
                                .zoomSource(id: item.id, in: zoomNS)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .softAppear(index: i)
                                .contentShape(Rectangle())
                                .onTapGesture { open(item) }
                                .contextMenu {
                                    if state.canEdit {
                                        Button { editing = item } label: { Label("Redigér / kommentar", systemImage: "pencil") }
                                    }
                                }
                        }
                    }
                }

                if let error { Text(error).font(.footnote).foregroundStyle(Theme.rose) }
            }
            .padding(16)
        }
        .paperBackground()
        .navigationTitle("Fødselsdage")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if state.canEdit {
                    // Apples billedvælger kan ikke ligge direkte i en menu — den åbnes via en knap.
                    Menu {
                        Button { showPicker = true } label: { Label("Vælg billeder", systemImage: "photo.on.rectangle") }
                        Button { showSuggestions = true } label: { Label("Forslag fra Fotos", systemImage: "sparkles") }
                    } label: { Image(systemName: "plus") }
                }
            }
        }
        .photosPicker(isPresented: $showPicker, selection: $pickerItems, maxSelectionCount: 30, matching: .images)
        .sheet(isPresented: $showSuggestions) {
            PhotoSuggestionsView(days: 31) { picked in Task { await add(picked) } }
        }
        .sheet(item: $editing, onDismiss: { Task { await load() } }) { item in
            AddGalleryItemView(childId: child.id, kind: .birthday, editing: item)
        }
        .fullScreenCover(item: $lightbox) { LightboxView(state: $0).zoomTarget(id: $0.sourceId, in: zoomNS) }
        .onChange(of: pickerItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task {
                var datas: [Data] = []
                for item in newItems {
                    if let raw = try? await item.loadTransferable(type: Data.self) { datas.append(ImageTools.resized(raw) ?? raw) }
                }
                pickerItems = []
                await add(datas)
            }
        }
        .refreshable { await load() }
        .reloadOnStoreChange { await load() }
        .task {
            if !loaded { loaded = true; age = currentAge }
            await load()
        }
    }

    private func open(_ item: GalleryItem) {
        let list = forAge.filter { $0.photo != nil }
        guard let i = list.firstIndex(where: { $0.id == item.id }) else { return }
        lightbox = LightboxState(photos: list.compactMap(\.photo), index: i, captions: list.map(\.note), sourceId: item.id)
    }

    private func load() async {
        items = (try? await state.store.gallery(childId: child.id, kind: .birthday)) ?? []
        loadingItems = false
    }

    /// Gemmer billederne til den valgte fødselsdag, ét ad gangen, mens man kan se dem dukke op.
    private func add(_ photos: [Data]) async {
        guard !photos.isEmpty else { return }
        let caption = "\(age)"
        adding += photos.count
        error = nil
        for photo in photos {
            do {
                let item = try await state.store.addGalleryItem(childId: child.id, kind: .birthday, caption: caption, photo: photo)
                items.append(item)
            } catch {
                self.error = SaveError.message(for: error)
            }
            adding -= 1
        }
    }
}
