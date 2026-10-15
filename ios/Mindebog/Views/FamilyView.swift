import SwiftUI

struct FamilyView: View {
    @EnvironmentObject var state: AppState

    enum Tab: String, CaseIterable, Identifiable {
        case events = "Begivenheder"
        case vacations = "Ferier"
        case birthdays = "Fødselsdage"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .events
    @State private var family: Family?
    @State private var events: [FamilyEvent] = []
    @State private var vacations: [Vacation] = []
    @State private var children: [Child] = []
    @State private var customBirthdays: [CustomBirthday] = []
    @State private var activeSheet: Tab?
    @State private var lightbox: LightboxState?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                switch tab {
                case .events: eventsList
                case .vacations: vacationsList
                case .birthdays: birthdaysList
                }
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Fælles")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { activeSheet = tab } label: { Image(systemName: "plus") }
            }
        }
        .sheet(item: $activeSheet, onDismiss: { Task { await load() } }) { which in
            switch which {
            case .events: AddEventView(familyId: state.familyId ?? "")
            case .vacations: AddVacationView(familyId: state.familyId ?? "")
            case .birthdays: AddBirthdayView(familyId: state.familyId ?? "")
            }
        }
        .fullScreenCover(item: $lightbox) { LightboxView(state: $0) }
        .refreshable { await load() }
        .task { await load() }
    }

    // MARK: Begivenheder
    @ViewBuilder
    private var eventsList: some View {
        if events.isEmpty {
            ContentUnavailableView("Ingen begivenheder endnu", systemImage: "calendar")
                .padding(.top, 40)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                    if index > 0 { Divider() }
                    HStack(alignment: .top, spacing: 14) {
                        VStack(spacing: 0) {
                            Text(monthShort(event.date))
                                .font(.caption2).foregroundStyle(Theme.muted)
                            Text(dayNumber(event.date))
                                .font(.serifTitle(20))
                        }
                        .frame(width: 44)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(event.title).font(.system(size: 15, weight: .medium))
                            if !event.details.isEmpty {
                                Text(event.details).font(.footnote).foregroundStyle(Theme.muted)
                            }
                            if let photo = event.photo {
                                Color.clear
                                    .aspectRatio(4.0 / 3.0, contentMode: .fit)
                                    .overlay { DataImage(data: photo) }
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .onTapGesture { lightbox = LightboxState(photos: [photo]) }
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 12)
                }
            }
            .padding(.horizontal, 16)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.sep))
        }
    }

    // MARK: Ferier
    @ViewBuilder
    private var vacationsList: some View {
        if vacations.isEmpty {
            ContentUnavailableView("Ingen ferier endnu", systemImage: "beach.umbrella")
                .padding(.top, 40)
        } else {
            VStack(spacing: 12) {
                ForEach(vacations) { vacation in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(vacation.title).font(.serifTitle(16))
                        if let range = dateRange(vacation) {
                            Text(range).font(.caption).foregroundStyle(Theme.muted)
                        }
                        if !vacation.details.isEmpty {
                            Text(vacation.details).font(.footnote).foregroundStyle(Theme.muted)
                        }
                        if let photo = vacation.photo {
                            Color.clear
                                .aspectRatio(4.0 / 3.0, contentMode: .fit)
                                .overlay { DataImage(data: photo) }
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .onTapGesture { lightbox = LightboxState(photos: [photo]) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.sep))
                }
            }
        }
    }

    // MARK: Fødselsdage
    private struct BirthdayRow: Identifiable {
        let id: String
        let name: String
        let emoji: String
        let date: Date
        let days: Int
        let turning: Int
    }

    private var birthdayRows: [BirthdayRow] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var rows: [BirthdayRow] = []

        func make(id: String, name: String, emoji: String, date: Date) -> BirthdayRow {
            let next = Fmt.nextOccurrence(of: date, from: today)
            let days = cal.dateComponents([.day], from: today, to: next).day ?? 0
            let turning = cal.component(.year, from: next) - cal.component(.year, from: date)
            return BirthdayRow(id: id, name: name, emoji: emoji, date: date, days: days, turning: turning)
        }

        for child in children {
            if let birth = child.birthDate {
                let emoji = child.gender == .girl ? "👧" : (child.gender == .boy ? "👦" : "🧒")
                rows.append(make(id: child.id, name: child.name, emoji: emoji, date: birth))
            }
        }
        for custom in customBirthdays {
            rows.append(make(id: custom.id, name: custom.name, emoji: custom.emoji, date: custom.date))
        }
        return rows.sorted { $0.days < $1.days }
    }

    @ViewBuilder
    private var birthdaysList: some View {
        let rows = birthdayRows
        if rows.isEmpty {
            ContentUnavailableView("Ingen fødselsdage endnu", systemImage: "gift")
                .padding(.top, 40)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider() }
                    HStack(spacing: 14) {
                        VStack(spacing: 0) {
                            if row.days == 0 {
                                Text("🎉").font(.title3)
                            } else {
                                Text("\(row.days)").font(.serifTitle(20))
                                Text(row.days == 1 ? "dag" : "dage")
                                    .font(.caption2).foregroundStyle(Theme.muted)
                            }
                        }
                        .frame(width: 60)
                        .padding(.vertical, 8)
                        .background(Theme.bgDark)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(row.emoji) \(row.name)").font(.system(size: 15, weight: .medium))
                            Text("\(dayMonth(row.date)) · fylder \(row.turning)")
                                .font(.footnote).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 12)
                }
            }
            .padding(.horizontal, 16)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.sep))
        }
    }

    // MARK: Hjælpere
    private static let danish = Locale(identifier: "da_DK")

    private func monthShort(_ date: Date?) -> String {
        guard let date else { return "—" }
        let f = DateFormatter()
        f.locale = Self.danish
        f.dateFormat = "MMM"
        return f.string(from: date).uppercased()
    }

    private func dayNumber(_ date: Date?) -> String {
        guard let date else { return "·" }
        return String(Calendar.current.component(.day, from: date))
    }

    private func dayMonth(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Self.danish
        f.dateFormat = "d. MMMM"
        return f.string(from: date)
    }

    private func dateRange(_ vacation: Vacation) -> String? {
        switch (vacation.startDate, vacation.endDate) {
        case let (start?, end?): return "\(Fmt.long(start)) – \(Fmt.long(end))"
        case let (start?, nil): return Fmt.long(start)
        case let (nil, end?): return Fmt.long(end)
        default: return nil
        }
    }

    private func load() async {
        guard let familyId = state.familyId else { return }
        let userId = state.user?.id ?? ""
        family = try? await state.store.families(for: userId).first { $0.id == familyId }
        events = (try? await state.store.events(familyId: familyId)) ?? []
        vacations = (try? await state.store.vacations(familyId: familyId)) ?? []
        children = (try? await state.store.children(familyId: familyId)) ?? []
        customBirthdays = (try? await state.store.birthdays(familyId: familyId)) ?? []
    }
}

// MARK: - Tilføj-formularer

struct AddEventView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let familyId: String
    @State private var title = ""
    @State private var date = Date()
    @State private var details = ""
    @State private var photo: Data?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Titel", text: $title)
                DatePicker("Dato", selection: $date, displayedComponents: .date)
                Section("Beskrivelse") {
                    TextField("Beskrivelse", text: $details, axis: .vertical).lineLimit(2...5)
                }
                Section("Billede") {
                    PhotoField(data: $photo)
                }
            }
            .navigationTitle("Ny begivenhed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annullér") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gem") {
                        Task {
                            _ = try? await state.store.addEvent(familyId: familyId, title: title, date: date,
                                                                details: details, photo: photo)
                            dismiss()
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct AddVacationView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let familyId: String
    @State private var title = ""
    @State private var start = Date()
    @State private var end = Date()
    @State private var details = ""
    @State private var photo: Data?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Titel (f.eks. Sommerhus i Skagen)", text: $title)
                DatePicker("Fra", selection: $start, displayedComponents: .date)
                DatePicker("Til", selection: $end, in: start..., displayedComponents: .date)
                Section("Beskrivelse") {
                    TextField("Beskrivelse", text: $details, axis: .vertical).lineLimit(2...5)
                }
                Section("Billede") {
                    PhotoField(data: $photo)
                }
            }
            .navigationTitle("Ny ferie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annullér") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gem") {
                        Task {
                            _ = try? await state.store.addVacation(familyId: familyId, title: title,
                                                                   start: start, end: end,
                                                                   details: details, photo: photo)
                            dismiss()
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct AddBirthdayView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let familyId: String
    @State private var name = ""
    @State private var date = Date()
    @State private var emoji = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Navn (f.eks. Mormor)", text: $name)
                DatePicker("Fødselsdato", selection: $date, in: ...Date(), displayedComponents: .date)
                TextField("Emoji (valgfri)", text: $emoji)
            }
            .navigationTitle("Ny fødselsdag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annullér") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gem") {
                        Task {
                            _ = try? await state.store.addBirthday(familyId: familyId, name: name, date: date, emoji: emoji)
                            dismiss()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
