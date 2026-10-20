import SwiftUI

// Familiens køkken: opskrifterne, der går i arv — mormors frikadeller, fars boller.
// Hver opskrift har hvem den er fra, ingredienser, fremgangsmåde, historien bag og billeder,
// også af den håndskrevne opskrift (scannes med kameraet).
struct RecipesView: View {
    @EnvironmentObject var state: AppState
    @Namespace private var zoomNS
    let recipes: [Recipe]
    var onEdit: (Recipe) -> Void
    var onAdd: () -> Void
    var onLightbox: (LightboxState) -> Void
    @State private var search = ""
    @State private var category: String?   // nil = alle

    /// Kun de kategorier, der faktisk bruges — i fast rækkefølge, egne kategorier til sidst.
    private var usedCategories: [String] {
        let used = Set(recipes.map(\.category).filter { !$0.isEmpty })
        return Recipe.categories.filter(used.contains) + used.subtracting(Recipe.categories).sorted()
    }

    private var shown: [Recipe] {
        var list = recipes
        if let category { list = list.filter { $0.category == category } }
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return list }
        return list.filter {
            $0.title.localizedCaseInsensitiveContains(q) || $0.fromWhom.localizedCaseInsensitiveContains(q)
                || $0.ingredients.localizedCaseInsensitiveContains(q) || $0.category.localizedCaseInsensitiveContains(q)
        }
    }

    private func chip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: { withAnimation(.easeInOut(duration: 0.15)) { action() } }) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(selected ? Theme.rose : Theme.card))
                .overlay(Capsule().stroke(selected ? Theme.rose : Theme.sep))
                .foregroundStyle(selected ? Color.white : Theme.text)
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        if recipes.isEmpty {
            VStack(spacing: 14) {
                Image(systemName: "fork.knife")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Theme.neutralDark)
                Text("Familiens køkken").font(.serifTitle(22))
                Text("Mormors frikadeller, fars søndagsboller, julens risalamande. Skriv opskrifterne ned — eller scan den håndskrevne seddel — så de går i arv.")
                    .font(.subheadline).foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                if state.canEdit {
                    Button { onAdd() } label: { Label("Tilføj den første opskrift", systemImage: "plus") }
                        .buttonStyle(.borderedProminent)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        } else {
            VStack(spacing: 12) {
                if recipes.count > 5 {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                        TextField("Søg i opskrifter eller ingredienser", text: $search)
                    }
                    .padding(10)
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.sep))
                }
                if usedCategories.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            chip("Alle", selected: category == nil) { category = nil }
                            ForEach(usedCategories, id: \.self) { c in
                                chip(c, selected: category == c) { category = category == c ? nil : c }
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                    .noTabSwipe()
                }
                if shown.isEmpty {
                    Text("Ingen opskrifter matcher.").font(.footnote).foregroundStyle(Theme.muted).padding(.top, 20)
                }
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, r in
                    NavigationLink { RecipeDetailView(recipe: r, onEdit: onEdit) } label: { card(r) }
                        .buttonStyle(.plain)
                        .softAppear(index: i)
                        .id(r.id)
                }
            }
        }
    }

    private func card(_ r: Recipe) -> some View {
        HStack(spacing: 12) {
            Group {
                if let photo = r.photo { DataImage(data: photo) }
                else { Theme.bgDark.overlay(Image(systemName: "fork.knife").foregroundStyle(Theme.neutralDark)) }
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(r.title).font(.serifTitle(16)).foregroundStyle(Theme.text).lineLimit(2)
                if !r.fromWhom.isEmpty {
                    Label(r.fromWhom, systemImage: "heart").font(.caption).foregroundStyle(Theme.neutralDark)
                }
                let n = r.ingredientLines.count
                let meta = [r.category, n > 0 ? "\(n) ingrediens\(n == 1 ? "" : "er")" : ""].filter { !$0.isEmpty }
                if !meta.isEmpty { Text(meta.joined(separator: " · ")).font(.caption2).foregroundStyle(Theme.muted) }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.muted)
        }
        .padding(12)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.sep))
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }
}

/// Én opskrift, til at lave mad efter: store ingredienser at krydse af, fremgangsmåden og historien.
struct RecipeDetailView: View {
    @EnvironmentObject var state: AppState
    @Namespace private var zoomNS
    let recipe: Recipe
    var onEdit: (Recipe) -> Void
    @State private var checked: Set<Int> = []
    @State private var lightbox: LightboxState?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !recipe.photos.isEmpty {
                    CoverPhotoView(set: recipe.photos, zoomId: recipe.id, zoomNamespace: zoomNS) { lightbox = $0 }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(recipe.title).font(.serifTitle(26)).foregroundStyle(Theme.text)
                    HStack(spacing: 12) {
                        if !recipe.fromWhom.isEmpty { Label(recipe.fromWhom, systemImage: "heart") }
                        if !recipe.servings.isEmpty { Label(recipe.servings, systemImage: "person.2") }
                    }
                    .font(.subheadline).foregroundStyle(Theme.neutralDark)
                }

                if !recipe.story.isEmpty {
                    Text(recipe.story)
                        .font(.system(.body, design: .serif)).italic()
                        .foregroundStyle(Theme.text)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.bgDark)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                if !recipe.ingredientLines.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel("Ingredienser")
                        ForEach(Array(recipe.ingredientLines.enumerated()), id: \.offset) { i, line in
                            Button {
                                if checked.contains(i) { checked.remove(i) } else { checked.insert(i); Haptics.light() }
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: checked.contains(i) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(checked.contains(i) ? Theme.green : Theme.muted)
                                    Text(line)
                                        .strikethrough(checked.contains(i))
                                        .foregroundStyle(checked.contains(i) ? Theme.muted : Theme.text)
                                        .multilineTextAlignment(.leading)
                                    Spacer(minLength: 0)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !recipe.method.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel("Sådan gør du")
                        Text(recipe.method).foregroundStyle(Theme.text)
                    }
                }

                CommentsBar(targetId: recipe.id, title: recipe.title)
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(recipe.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if state.canEdit { Button("Redigér") { onEdit(recipe) } }
            }
        }
        // Skærmen slukker ikke, mens man laver mad efter opskriften.
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .fullScreenCover(item: $lightbox) { LightboxView(state: $0).zoomTarget(id: $0.sourceId, in: zoomNS) }
    }
}

/// Tilføj eller redigér en opskrift. Den håndskrevne seddel kan scannes direkte ind som billede.
struct RecipeEditView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let familyId: String
    var editing: Recipe? = nil

    @State private var draft = Recipe(id: newId("rec"), title: "")
    @State private var saving = false
    @State private var saveError: String?
    @State private var confirmDelete = false
    @State private var scanning = false
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Group {
                Section {
                    TextField("Opskrift (fx Mormors frikadeller)", text: $draft.title)
                    TextField("Fra hvem (fx Mormor Inger)", text: $draft.fromWhom)
                    TextField("Til hvor mange (fx 4 personer)", text: $draft.servings)
                    Picker("Kategori", selection: $draft.category) {
                        Text("Ingen").tag("")
                        ForEach(Recipe.categories, id: \.self) { Text($0).tag($0) }
                        // En kategori fra en ældre/anden version, der ikke står i listen, mistes ikke.
                        if !draft.category.isEmpty && !Recipe.categories.contains(draft.category) {
                            Text(draft.category).tag(draft.category)
                        }
                    }
                }
                Section {
                    TextField("500 g hakket svinekød\n1 løg\n2 æg\n…", text: $draft.ingredients, axis: .vertical)
                        .lineLimit(5...20)
                } header: {
                    Text("Ingredienser")
                } footer: {
                    Text("Én ingrediens pr. linje — så kan de krydses af, når man laver maden.")
                }
                Section("Sådan gør du") {
                    TextField("Rør farsen, form frikadellerne med en ske dyppet i vand …", text: $draft.method, axis: .vertical)
                        .lineLimit(5...30)
                }
                Section {
                    TextField("Hvornår laves den, hvem elsker den, hvad er hemmeligheden?", text: $draft.story, axis: .vertical)
                        .lineLimit(2...10)
                } header: {
                    Text("Historien bag (valgfri)")
                }
                Section {
                    if DocumentScanner.isAvailable {
                        Button { scanning = true } label: {
                            Label("Scan den håndskrevne opskrift", systemImage: "doc.viewfinder")
                        }
                    }
                    PhotoSetEditor(set: $draft.photos)
                } header: {
                    Text("Billeder")
                } footer: {
                    Text("Fx retten på bordet, eller sedlen med mormors håndskrift.")
                }
                if editing != nil {
                    Section {
                        Button("Slet opskrift", role: .destructive) { confirmDelete = true }
                    }
                }
                }.listRowBackground(Theme.card)
            }
            .themedList()
            .navigationTitle(editing == nil ? "Ny opskrift" : "Redigér opskrift")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annullér") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gem") { save() }
                        .disabled(saving || draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .saveErrorAlert($saveError)
            .fullScreenCover(isPresented: $scanning) {
                DocumentScanner { pages in
                    for page in pages { draft.photos.append(ImageTools.resized(page, maxDimension: 1800) ?? page) }
                }
                .ignoresSafeArea()
            }
            .confirmationDialog("Slet opskriften?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Slet", role: .destructive) {
                    Task {
                        await performSave(saving: $saving, errorMessage: $saveError, dismiss: dismiss) {
                            if let id = editing?.id { try await state.store.deleteRecipe(familyId: familyId, id: id) }
                        }
                    }
                }
            } message: {
                Text("Opskriften og dens billeder slettes for hele familien.")
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let editing { draft = editing }
            }
        }
    }

    private func save() {
        draft.title = draft.title.trimmingCharacters(in: .whitespaces)
        let (store, familyId, recipe) = (state.store, familyId, draft)
        performSaveInBackground(label: "opskriften", dismiss: dismiss) {
            try await store.saveRecipe(familyId: familyId, recipe)
        }
    }
}
