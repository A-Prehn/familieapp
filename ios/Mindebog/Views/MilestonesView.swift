import SwiftUI

struct MilestonesView: View {
    @EnvironmentObject var state: AppState
    @Namespace private var zoomNS   // zoom-overgang til fuld skærm (iOS 18)
    let child: Child
    @State private var entries: [String: MilestoneEntry] = [:]
    @State private var editing: MilestoneDef?
    @State private var lightbox: LightboxState?

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(Constants.milestones) { def in
                        tile(def).id(def.key)
                    }
                }
                .padding(16)
            }
            // Fra en notifikation: scroll til milepælen, og vis billederne, hvis der er nogen.
            .task(id: entries.count) { openJumpTarget(proxy) }
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Milepæle")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing, onDismiss: { Task { await load() } }) { def in
            MilestoneEditView(child: child, def: def, entry: entries[def.key])
        }
        .fullScreenCover(item: $lightbox) { LightboxView(state: $0).zoomTarget(id: $0.sourceId, in: zoomNS) }
        .refreshable { await load() }
        .task { await load() }
        .reloadOnStoreChange { await load() }
    }

    private func openJumpTarget(_ proxy: ScrollViewProxy) {
        let prefix = "ms_\(child.id)_"
        guard let id = JumpRequest.shared.recordId, id.hasPrefix(prefix), !entries.isEmpty else { return }
        JumpRequest.shared.recordId = nil
        let key = String(id.dropFirst(prefix.count))
        withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(key, anchor: .center) }
        if let photos = entries[key]?.photos, !photos.isEmpty {
            openLightbox(LightboxState.coverFirst(photos, sourceId: key))
        }
    }

    /// Fuld skærm: thumb med det samme, og originalerne så snart de er hentet (#62).
    private func openLightbox(_ shown: LightboxState) {
        lightbox = shown
        guard shown.needsOriginals, let key = shown.sourceId else { return }
        Task {
            await CloudKitStore.withOriginals { await load() }
            if let set = entries[key]?.photos, !set.photos.isEmpty { lightbox = LightboxState.coverFirst(set, sourceId: key) }
        }
    }

    /// Redigering kræver originalerne (ellers ville et gem ikke kunne ændre billederne).
    private func edit(_ def: MilestoneDef) {
        if entries[def.key]?.photos.loaded ?? true { editing = def; return }
        Task {
            await CloudKitStore.withOriginals { await load() }
            editing = def
        }
    }

    private func tile(_ def: MilestoneDef) -> some View {
        let entry = entries[def.key]
        let filled = entry?.value != nil || entry?.photo != nil
        return VStack(spacing: 0) {
            Group {
                if let photos = entry?.photos, !photos.isEmpty {
                    // Forsidebillede + billedtekst + "+N"; tryk viser alle billeder.
                    CoverPhotoView(set: photos, aspect: 4.0 / 3.0, cornerRadius: 0, zoomId: def.key, zoomNamespace: zoomNS) { openLightbox($0) }
                } else {
                    Color.clear
                        .aspectRatio(4.0 / 3.0, contentMode: .fit)
                        .overlay {
                            ZStack {
                                Theme.bgDark
                                Text(def.icon)
                                    .font(.system(size: 28))
                                    .opacity(filled ? 0.85 : 0.4)
                            }
                        }
                        .clipped()
                        .contentShape(Rectangle())
                        .onTapGesture { if state.canEdit { edit(def) } }
                }
            }

            VStack(spacing: 2) {
                Text(def.label)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                Text(displayValue(def, entry))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(filled ? Theme.text : Theme.muted.opacity(0.6))
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .onTapGesture { if state.canEdit { edit(def) } }
        }
        .background(filled ? Theme.card : Theme.bg)
        .clipShape(RoundedRectangle(cornerRadius: Radius.small))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.small)
                .stroke(filled ? Theme.green.opacity(0.35) : Theme.sep)
        )
    }

    private func displayValue(_ def: MilestoneDef, _ entry: MilestoneEntry?) -> String {
        guard let value = entry?.value else { return "—" }
        return MilestoneValue.display(value, kind: def.kind)
    }

    private func load() async {
        let cacheKey = "milestones_\(child.id)"
        if entries.isEmpty, let cached = ScreenCache.load([String: MilestoneEntry].self, key: cacheKey) { entries = cached }
        if let fresh = try? await state.store.milestones(childId: child.id) {
            entries = fresh
            ScreenCache.save(fresh, key: cacheKey)
        }
    }
}

struct MilestoneEditView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let child: Child
    let def: MilestoneDef
    let entry: MilestoneEntry?

    @State private var hasValue = false      // dato/tid sat
    @State private var date = Date()
    @State private var text = ""             // fritekst, vægt (g), længde (cm)
    @State private var choice = ""
    @State private var photos = PhotoSet()
    @State private var saving = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                Group {
                valueSection
                Section {
                    PhotoSetEditor(set: $photos)
                } header: {
                    Text("Billeder")
                } footer: {
                    Text("Vælg ★ for det billede, der vises på milepælen.")
                }
                }.listRowBackground(Theme.card)
            }
            .themedList()
            .navigationTitle(def.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annullér") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gem") { Task { await save() } }
                        .disabled(saving)
                }
            }
            .saveErrorAlert($saveError)
            .onAppear(perform: prefill)
        }
    }

    // Felt der passer til milepælens type.
    @ViewBuilder
    private var valueSection: some View {
        switch def.kind {
        case .date:
            Section("Dato") {
                Toggle("Sæt dato", isOn: $hasValue)
                if hasValue {
                    DatePicker("Dato", selection: $date, displayedComponents: .date)
                }
            }
        case .time:
            Section("Klokkeslæt") {
                Toggle("Sæt tidspunkt", isOn: $hasValue)
                if hasValue {
                    DatePicker("Tidspunkt", selection: $date, displayedComponents: .hourAndMinute)
                        .environment(\.locale, Locale(identifier: "da_DK"))
                }
            }
        case .weight:
            Section {
                HStack {
                    TextField("F.eks. 3450", text: $text)
                        .keyboardType(.numberPad)
                    Text("gram").foregroundStyle(Theme.muted)
                }
            } header: {
                Text("Vægt")
            } footer: {
                if let g = Int(text), g > 0 {
                    Text("= \(MilestoneValue.display(String(g), kind: .weight)) (\(String(format: "%.2f", Double(g) / 1000).replacingOccurrences(of: ".", with: ",")) kg)")
                }
            }
        case .length:
            Section("Længde") {
                HStack {
                    TextField("F.eks. 52", text: $text)
                        .keyboardType(.decimalPad)
                    Text("cm").foregroundStyle(Theme.muted)
                }
            }
        case .choice(let options):
            Section("Vælg") {
                Picker(def.label, selection: $choice) {
                    Text("Ikke valgt").tag("")
                    ForEach(options, id: \.self) { Text($0).tag($0) }
                    // Bevar en ældre fritekst-værdi, som ikke er i listen.
                    if !choice.isEmpty && !options.contains(choice) {
                        Text(choice).tag(choice)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        case .text:
            Section("Værdi") {
                TextField("Skriv her…", text: $text)
            }
        }
    }

    private func prefill() {
        photos = entry?.photos ?? PhotoSet()
        let value = entry?.value ?? ""
        switch def.kind {
        case .date:
            if let parsed = Fmt.parseIso(value) { date = parsed; hasValue = true }
        case .time:
            if let t = MilestoneValue.parseTime(value),
               let d = Calendar.current.date(bySettingHour: t.hour, minute: t.minute, second: 0, of: Date()) {
                date = d; hasValue = true
            }
        case .weight:
            text = MilestoneValue.grams(value).map(String.init) ?? ""
        case .length:
            text = MilestoneValue.centimeters(value)
                .map { $0.truncatingRemainder(dividingBy: 1) == 0 ? String(Int($0)) : String($0).replacingOccurrences(of: ".", with: ",") } ?? ""
        case .choice:
            choice = value
        case .text:
            text = value
        }
    }

    private func save() async {
        let value: String?
        switch def.kind {
        case .date:
            value = hasValue ? Fmt.iso(date) : nil
        case .time:
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            value = hasValue ? String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0) : nil
        case .weight:
            value = MilestoneValue.grams(text).map(String.init)        // kun tal, i gram
        case .length:
            value = MilestoneValue.centimeters(text).map { cm in
                cm.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(cm)) : String(cm)
            }
        case .choice:
            value = choice.isEmpty ? nil : choice
        case .text:
            value = text
        }
        await performSave(saving: $saving, errorMessage: $saveError, dismiss: dismiss) {
            try await state.store.setMilestone(childId: child.id, key: def.key, value: value, photos: photos)
        }
    }
}
