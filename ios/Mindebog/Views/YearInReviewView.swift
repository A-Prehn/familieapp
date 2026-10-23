import SwiftUI

// Årsopsummering: "Theos år 2025" (kalenderår) eller "Theos 3. år" (fra fødselsdag til fødselsdag).
// Tal for året, de bedste billeder og "Lav film af året" (Premium). Vises på Hjem i januar og
// omkring fødselsdagen, og kan altid findes på barnets side.

/// Hvilket år der opsummeres. Gemmes som tekst i notifikationer ("cal:2025" / "age:3").
enum YearSpec: Hashable {
    case calendar(Int)      // kalenderåret
    case age(Int)           // barnets n'te leveår (fra (n-1)-års fødselsdag til n-års fødselsdag)

    var raw: String {
        switch self {
        case .calendar(let y): return "cal:\(y)"
        case .age(let n): return "age:\(n)"
        }
    }
    init?(raw: String) {
        let parts = raw.split(separator: ":")
        guard parts.count == 2, let n = Int(parts[1]) else { return nil }
        switch parts[0] {
        case "cal": self = .calendar(n)
        case "age": self = .age(n)
        default: return nil
        }
    }

    func title(for child: Child) -> String {
        switch self {
        case .calendar(let y): return "\(child.name)s år \(y)"
        case .age(let n): return "\(child.name)s \(n). år"
        }
    }

    /// Perioden, afgrænset til det der er sket (ikke ud i fremtiden).
    func period(for child: Child) -> ClosedRange<Date> {
        let cal = Calendar.current
        let now = Date()
        switch self {
        case .calendar(let y):
            let start = cal.date(from: DateComponents(year: y, month: 1, day: 1)) ?? now
            let end = cal.date(from: DateComponents(year: y + 1, month: 1, day: 1))?.addingTimeInterval(-1) ?? now
            return start...max(start, min(end, now))
        case .age(let n):
            let birth = cal.startOfDay(for: child.birthDate ?? now)
            let start = cal.date(byAdding: .year, value: n - 1, to: birth) ?? birth
            let end = cal.date(byAdding: .year, value: n, to: birth)?.addingTimeInterval(-1) ?? now
            return start...max(start, min(end, now))
        }
    }

    /// Det år, der er færdigt og værd at vise lige nu: kalenderåret i januar, leveåret omkring fødselsdagen.
    static func current(for child: Child, now: Date = Date()) -> YearSpec? {
        let cal = Calendar.current
        guard let birth = child.birthDate else { return nil }
        let year = cal.component(.year, from: now)
        if cal.component(.month, from: now) == 1, cal.component(.year, from: birth) < year {
            return .calendar(year - 1)
        }
        let age = cal.dateComponents([.year], from: birth, to: now).year ?? 0
        guard age >= 1, let birthday = cal.date(byAdding: .year, value: age, to: birth),
              let days = cal.dateComponents([.day], from: cal.startOfDay(for: birthday), to: cal.startOfDay(for: now)).day,
              (0...10).contains(days) else { return nil }
        return .age(age)
    }
}

struct YearInReviewView: View {
    @EnvironmentObject var state: AppState
    let child: Child
    @State var spec: YearSpec

    @State private var highlights: [Highlight] = []
    @State private var diary: [DiaryEntry] = []
    @State private var gallery: [GalleryItem] = []
    @State private var measurements: [Measurement] = []
    @State private var loading = true
    @State private var lightbox: LightboxState?
    @State private var makingMovie = false
    @State private var movieShare: ShareSheet?
    @State private var movieError: String?
    @State private var paywall: PaywallReason?
    @Namespace private var zoomNS

    private var period: ClosedRange<Date> { spec.period(for: child) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Hvilket år: alle kalenderår fra fødslen, og leveårene.
                Picker("År", selection: $spec) {
                    ForEach(options, id: \.self) { Text($0.title(for: child)).tag($0) }
                }
                .pickerStyle(.menu)
                .tint(Theme.text)

                if loading && photos.isEmpty {
                    ShimmerPlaceholder(height: 120)
                } else {
                    stats
                    if !photos.isEmpty { photoGrid }
                    if !bestTexts.isEmpty { texts }
                    movieButton
                }
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(spec.title(for: child))
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $lightbox) { LightboxView(state: $0).zoomTarget(id: $0.sourceId, in: zoomNS) }
        .sheet(item: $movieShare) { $0 }
        .sheet(item: $paywall) { PaywallView(reason: $0) }
        .saveErrorAlert($movieError)
        .task { await load() }
    }

    private var options: [YearSpec] {
        let cal = Calendar.current
        guard let birth = child.birthDate else { return [spec] }
        let first = cal.component(.year, from: birth), thisYear = cal.component(.year, from: Date())
        let years = (first...max(first, thisYear)).reversed().map { YearSpec.calendar($0) }
        let age = cal.dateComponents([.year], from: birth, to: Date()).year ?? 0
        let ages = age >= 1 ? (1...age).reversed().map { YearSpec.age($0) } : []
        return years + ages
    }

    // MARK: Udregninger
    private var inPeriod: (Date?) -> Bool { { d in d.map { period.contains($0) } ?? false } }
    private var yearHighlights: [Highlight] { highlights.filter { inPeriod($0.date ?? $0.createdAt) } }
    private var yearDiary: [DiaryEntry] { diary.filter { inPeriod($0.date ?? $0.createdAt) } }
    private var yearGallery: [GalleryItem] { gallery.filter { inPeriod($0.shownDate) } }
    private var photos: [(id: String, date: Date, data: Data, caption: String)] {
        let fromHighlights = yearHighlights.flatMap { h in
            h.photos.enumerated().map { (id: "\(h.id)_\($0.offset)", date: h.date ?? h.createdAt, data: $0.element, caption: h.text) }
        }
        let fromGallery = yearGallery.compactMap { g in g.photo.map { (id: g.id, date: g.shownDate, data: $0, caption: g.caption) } }
        let fromDiary = yearDiary.compactMap { d in d.photo.map { (id: d.id, date: d.date ?? d.createdAt, data: $0, caption: "") } }
        return (fromHighlights + fromGallery + fromDiary).sorted { $0.date < $1.date }
    }
    private var bestTexts: [(id: String, date: Date, text: String)] {
        let h = yearHighlights.filter { !$0.text.isEmpty }.map { (id: $0.id, date: $0.date ?? $0.createdAt, text: $0.text) }
        let d = yearDiary.filter { !$0.text.isEmpty }.map { (id: $0.id, date: $0.date ?? $0.createdAt, text: $0.text) }
        return Array((h + d).sorted { $0.date < $1.date }.prefix(6))
    }
    private var growth: String? {
        let m = measurements.filter { period.contains($0.date) }.sorted { $0.date < $1.date }
        guard let first = m.first, let last = m.last, first.id != last.id else { return nil }
        var parts: [String] = []
        if let a = first.heightCm, let b = last.heightCm, b > a { parts.append("\(Int((b - a).rounded())) cm højere") }
        if let a = first.weightGrams, let b = last.weightGrams, b > a {
            let kg = Double(b - a) / 1000
            parts.append(String(format: "%.1f kg tungere", kg).replacingOccurrences(of: ".", with: ","))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " og ")
    }

    // MARK: Sektioner
    private var stats: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Året i tal")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                statCard("\(photos.count)", photos.count == 1 ? "billede" : "billeder", "photo.on.rectangle", Theme.tint)
                statCard("\(yearHighlights.count)", yearHighlights.count == 1 ? "højdepunkt" : "højdepunkter", "star", Theme.rose)
                statCard("\(yearDiary.count)", yearDiary.count == 1 ? "dagbogsindlæg" : "dagbogsindlæg", "book", Theme.neutralDark)
                if let growth {
                    statCard(growth, "i løbet af året", "ruler", Theme.green)
                } else {
                    statCard("\(yearGallery.filter { $0.caption.contains("måned") || $0.caption.contains("mdr") }.count)",
                             "månedsbilleder", "calendar", Theme.green)
                }
            }
            if photos.isEmpty && yearHighlights.isEmpty && yearDiary.isEmpty {
                Text("Der er ikke lagt noget ind fra \(Fmt.period(period.lowerBound, period.upperBound)) endnu.")
                    .font(.footnote).foregroundStyle(Theme.muted)
            }
        }
    }

    private func statCard(_ value: String, _ label: String, _ symbol: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(value).font(.serifTitle(22)).foregroundStyle(Theme.text).lineLimit(2).minimumScaleFactor(0.7)
            Text(label).font(.caption).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Theme.sep))
    }

    private var photoGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Årets billeder")
            let shown = Array(photos.prefix(12))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)], spacing: 4) {
                ForEach(shown, id: \.id) { p in
                    DataImage(data: p.data)
                        .aspectRatio(1, contentMode: .fill)
                        .frame(minWidth: 0)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: Radius.small))
                        .zoomSource(id: p.id, in: zoomNS)
                        .onTapGesture {
                            lightbox = LightboxState(photos: photos.map(\.data), index: photos.firstIndex { $0.id == p.id } ?? 0,
                                                     captions: photos.map(\.caption), sourceId: p.id)
                        }
                }
            }
            if photos.count > shown.count {
                Text("og \(photos.count - shown.count) mere").font(.caption).foregroundStyle(Theme.muted)
            }
        }
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Det, I skrev")
            ForEach(bestTexts, id: \.id) { t in
                VStack(alignment: .leading, spacing: 3) {
                    Text(Fmt.long(t.date)).font(.caption2).foregroundStyle(Theme.muted)
                    Text(t.text).font(.footnote).foregroundStyle(Theme.text).lineLimit(3)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: Radius.card))
                .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Theme.sep))
            }
        }
    }

    private var movieButton: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { Task { await makeMovie() } } label: {
                HStack {
                    if makingMovie { ProgressView().controlSize(.small) }
                    Label(makingMovie ? "Laver film…" : "Lav film af året", systemImage: "film")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if !state.isPremium { Text("Premium").font(.caption2.weight(.semibold)).foregroundStyle(Theme.rose) }
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: Radius.card))
                .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Theme.sep))
            }
            .buttonStyle(.plain)
            .disabled(makingMovie || photos.count < 2)
            Text("Et lille minut med årets billeder i rækkefølge — til at dele med familien.")
                .font(.caption).foregroundStyle(Theme.muted)
        }
    }

    // MARK: Data
    private func load() async {
        defer { loading = false }
        let store = state.store, id = child.id
        async let h = store.highlights(childId: id)
        async let d = store.diary(childId: id)
        async let m = store.measurements(childId: id)
        async let g1 = store.gallery(childId: id, kind: .monthly)
        async let g2 = store.gallery(childId: id, kind: .drawings)
        async let g3 = store.gallery(childId: id, kind: .birthday)
        highlights = (try? await h) ?? []
        diary = (try? await d) ?? []
        measurements = (try? await m) ?? []
        gallery = ((try? await g1) ?? []) + ((try? await g2) ?? []) + ((try? await g3) ?? [])
    }

    private func makeMovie() async {
        guard state.isPremium else { paywall = .movie; return }
        makingMovie = true
        defer { makingMovie = false }
        // Højst 40 billeder, jævnt fordelt over året, så filmen ikke bliver for lang.
        let all = photos
        let step = max(1, Int((Double(all.count) / 40).rounded(.up)))
        let frames = stride(from: 0, to: all.count, by: step).map { i in
            MovieMaker.Frame(photo: all[i].data, caption: all[i].caption, subtitle: Fmt.long(all[i].date))
        }
        do {
            let url = try await MovieMaker.make(title: spec.title(for: child),
                                                subtitle: Fmt.period(period.lowerBound, period.upperBound), frames: frames)
            Haptics.success()
            movieShare = ShareSheet(url: url)
        } catch {
            movieError = error.localizedDescription
        }
    }
}
