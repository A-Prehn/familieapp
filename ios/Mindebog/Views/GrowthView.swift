import SwiftUI
import Charts

// Vækst: vægt, højde og hovedomkreds over tid, tegnet efter alder i måneder.
// Fødselsvægt/-længde fra Milepæle kommer automatisk med som første punkt.
// (Officielle WHO-referencekurver er bevidst udeladt, indtil de kan indlæses fra de
//  officielle tabeller — forkerte referencekurver er værre end ingen.)
struct GrowthView: View {
    @EnvironmentObject var state: AppState
    let child: Child
    @State private var measurements: [Measurement] = []
    @State private var birthWeight: Int?
    @State private var birthLength: Double?
    @State private var metric: Metric = .weight
    @State private var editing: Measurement?
    @State private var showAdd = false

    enum Metric: String, CaseIterable, Identifiable {
        case weight = "Vægt", height = "Højde", head = "Hoved"
        var id: String { rawValue }
        var unit: String { self == .weight ? "kg" : "cm" }
    }

    private struct Point: Identifiable {
        let id: String
        let months: Double
        let value: Double
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Måling", selection: $metric) {
                    ForEach(Metric.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                chartCard

                SectionLabel("Målinger")
                if measurements.isEmpty {
                    Text("Ingen målinger endnu. Tryk + for at tilføje vægt og højde fra fx sundhedsplejersken.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(measurements.reversed().enumerated()), id: \.element.id) { index, m in
                            if index > 0 { Divider() }
                            row(m)
                        }
                    }
                    .padding(.horizontal, 14)
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.sep))
                }
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Vækst")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if state.canEdit { Button { showAdd = true } label: { Image(systemName: "plus") } }
            }
        }
        .sheet(isPresented: $showAdd, onDismiss: { Task { await load() } }) {
            MeasurementEditView(childId: child.id)
        }
        .sheet(item: $editing, onDismiss: { Task { await load() } }) { m in
            MeasurementEditView(childId: child.id, editing: m)
        }
        .refreshable { await load() }
        .task { await load() }
        .reloadOnStoreChange { await load() }
    }

    // MARK: Graf
    private var points: [Point] {
        guard let birth = child.birthDate else { return [] }
        func months(_ date: Date) -> Double { date.timeIntervalSince(birth) / 86_400 / 30.4375 }
        var out: [Point] = []
        switch metric {
        case .weight:
            if let w = birthWeight { out.append(Point(id: "birth", months: 0, value: Double(w) / 1000)) }
            out += measurements.compactMap { m in m.weightGrams.map { Point(id: m.id, months: months(m.date), value: Double($0) / 1000) } }
        case .height:
            if let l = birthLength { out.append(Point(id: "birth", months: 0, value: l)) }
            out += measurements.compactMap { m in m.heightCm.map { Point(id: m.id, months: months(m.date), value: $0) } }
        case .head:
            out += measurements.compactMap { m in m.headCm.map { Point(id: m.id, months: months(m.date), value: $0) } }
        }
        return out.sorted { $0.months < $1.months }
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(metric.rawValue) (\(metric.unit))").font(.caption).foregroundStyle(Theme.muted)
            if points.count < 2 {
                Text("Kurven tegnes, når der er mindst to målinger.")
                    .font(.footnote).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                Chart(points) { p in
                    LineMark(x: .value("Alder (mdr.)", p.months), y: .value(metric.rawValue, p.value))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(ChildPalette.color(for: child))
                    PointMark(x: .value("Alder (mdr.)", p.months), y: .value(metric.rawValue, p.value))
                        .foregroundStyle(ChildPalette.color(for: child))
                }
                .chartXAxisLabel("Alder i måneder")
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 220)
            }
        }
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.sep))
    }

    private func row(_ m: Measurement) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.long(m.date)).font(.subheadline.weight(.medium))
                Text(summary(m)).font(.footnote).foregroundStyle(Theme.muted)
            }
            Spacer()
            if state.canEdit {
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.muted)
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture { if state.canEdit { editing = m } }
    }

    private func summary(_ m: Measurement) -> String {
        var parts: [String] = []
        if let g = m.weightGrams { parts.append(MilestoneValue.display(String(g), kind: .weight)) }
        if let h = m.heightCm { parts.append(MilestoneValue.display(String(h), kind: .length)) }
        if let c = m.headCm { parts.append("hoved " + MilestoneValue.display(String(c), kind: .length)) }
        return parts.joined(separator: " · ")
    }

    private func load() async {
        let cacheKey = "growth_\(child.id)"
        if measurements.isEmpty, let cached = ScreenCache.load(GrowthCache.self, key: cacheKey) { apply(cached) }
        guard let m = try? await state.store.measurements(childId: child.id),
              let ms = try? await state.store.milestones(childId: child.id) else { return }
        let fresh = GrowthCache(measurements: m, milestones: ms)
        apply(fresh)
        ScreenCache.save(fresh, key: cacheKey)
    }

    private struct GrowthCache: Codable { var measurements: [Measurement]; var milestones: [String: MilestoneEntry] }

    private func apply(_ c: GrowthCache) {
        measurements = c.measurements
        birthWeight = c.milestones["birth_weight"]?.value.flatMap(MilestoneValue.grams)
        birthLength = c.milestones["birth_length"]?.value.flatMap(MilestoneValue.centimeters)
    }
}

/// Tilføj eller redigér én måling.
struct MeasurementEditView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let childId: String
    var editing: Measurement? = nil

    @State private var date = Date()
    @State private var weight = ""
    @State private var height = ""
    @State private var head = ""
    @State private var saving = false
    @State private var saveError: String?
    @State private var loaded = false
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Group {
                DatePicker("Dato", selection: $date, in: ...Date(), displayedComponents: .date)
                Section {
                    field("Vægt", "F.eks. 6450", $weight, "gram", .numberPad)
                    field("Højde", "F.eks. 64,5", $height, "cm", .decimalPad)
                    field("Hovedomkreds", "F.eks. 41", $head, "cm", .decimalPad)
                } footer: {
                    Text("Udfyld det, I har målt — resten kan stå tomt.")
                }
                if editing != nil {
                    Section {
                        Button("Slet måling", role: .destructive) { confirmDelete = true }
                    }
                }
                }.listRowBackground(Theme.card)
            }
            .themedList()
            .navigationTitle(editing == nil ? "Ny måling" : "Redigér måling")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annullér") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gem") { Task { await save() } }
                        .disabled(saving || (weight.isEmpty && height.isEmpty && head.isEmpty))
                }
            }
            .saveErrorAlert($saveError)
            .confirmationDialog("Slet målingen?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Slet", role: .destructive) {
                    Task {
                        await performSave(saving: $saving, errorMessage: $saveError, dismiss: dismiss) {
                            if let id = editing?.id { try await state.store.deleteMeasurement(childId: childId, id: id) }
                        }
                    }
                }
            }
            .onAppear {
                guard !loaded, let m = editing else { return }
                loaded = true
                date = m.date
                weight = m.weightGrams.map(String.init) ?? ""
                height = m.heightCm.map { String($0).replacingOccurrences(of: ".", with: ",") } ?? ""
                head = m.headCm.map { String($0).replacingOccurrences(of: ".", with: ",") } ?? ""
            }
        }
    }

    private func field(_ label: String, _ placeholder: String, _ text: Binding<String>,
                       _ unit: String, _ keyboard: UIKeyboardType) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 120)
            Text(unit).foregroundStyle(Theme.muted)
        }
    }

    private func save() async {
        let m = Measurement(id: editing?.id ?? newId("meas"), date: date,
                            weightGrams: MilestoneValue.grams(weight),
                            heightCm: MilestoneValue.centimeters(height),
                            headCm: MilestoneValue.centimeters(head))
        await performSave(saving: $saving, errorMessage: $saveError, dismiss: dismiss) {
            try await state.store.saveMeasurement(childId: childId, m)
        }
    }
}
