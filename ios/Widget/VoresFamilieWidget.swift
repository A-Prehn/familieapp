import WidgetKit
import SwiftUI

// Widgets til hjemmeskærmen. Data kommer fra appen via App Group'en (WidgetSnapshot),
// så widgetten skal ikke selv logge ind i iCloud. Opdateres ved midnat og når appen åbnes.

private enum WTheme {
    static let bg = Color(red: 0.980, green: 0.973, blue: 0.957)
    static let card = Color(red: 0.941, green: 0.929, blue: 0.902)
    static let text = Color(red: 0.173, green: 0.157, blue: 0.125)
    static let muted = Color(red: 0.541, green: 0.510, blue: 0.470)
    static let rose = Color(red: 0.831, green: 0.329, blue: 0.478)
    static let accent = Color(red: 0.373, green: 0.322, blue: 0.220)
    static func serif(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

// MARK: - Tidslinje

struct FamilyEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct FamilyProvider: TimelineProvider {
    func placeholder(in context: Context) -> FamilyEntry {
        FamilyEntry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (FamilyEntry) -> Void) {
        completion(FamilyEntry(date: Date(), snapshot: WidgetSnapshot.load() ?? .preview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FamilyEntry>) -> Void) {
        let snapshot = WidgetSnapshot.load() ?? WidgetSnapshot()
        let now = Date()
        let midnight = Calendar.current.startOfDay(for: now.addingTimeInterval(86_400))
        // I dag + i morgen (så nedtællingen skifter præcis ved midnat).
        let entries = [FamilyEntry(date: now, snapshot: snapshot),
                       FamilyEntry(date: midnight, snapshot: snapshot)]
        completion(Timeline(entries: entries, policy: .after(midnight.addingTimeInterval(60))))
    }
}

extension WidgetSnapshot {
    static var preview: WidgetSnapshot {
        var s = WidgetSnapshot()
        let cal = Calendar.current
        s.birthdays = [
            .init(name: "Mormor", emoji: "👵", date: cal.date(byAdding: .day, value: 5, to: cal.date(byAdding: .year, value: -66, to: Date())!)!),
            .init(name: "William", emoji: "👦", date: cal.date(byAdding: .day, value: 40, to: cal.date(byAdding: .year, value: -12, to: Date())!)!),
        ]
        s.due = [.init(name: "Lillebror", dueDate: cal.date(byAdding: .day, value: 88, to: Date())!)]
        return s
    }
}

// MARK: - Hjælpere

private func daysUntil(_ date: Date, from now: Date) -> Int {
    let cal = Calendar.current
    return cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: date)).day ?? 0
}

private struct UpcomingBirthday: Identifiable {
    let id = UUID()
    let name: String
    let emoji: String
    let days: Int
    let turning: Int
}

private func upcoming(_ snapshot: WidgetSnapshot, now: Date) -> [UpcomingBirthday] {
    let cal = Calendar.current
    let today = cal.startOfDay(for: now)
    return snapshot.birthdays.map { b in
        var comps = cal.dateComponents([.month, .day], from: b.date)
        comps.year = cal.component(.year, from: today)
        var next = cal.date(from: comps) ?? today
        if next < today { next = cal.date(byAdding: .year, value: 1, to: next) ?? next }
        let turning = cal.component(.year, from: next) - cal.component(.year, from: b.date)
        return UpcomingBirthday(name: b.name, emoji: b.emoji, days: daysUntil(next, from: today), turning: turning)
    }
    .sorted { $0.days < $1.days }
}

// MARK: - Fødselsdage

struct BirthdaysView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: FamilyEntry

    var body: some View {
        let list = upcoming(entry.snapshot, now: entry.date)
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label("Næste fødselsdag", systemImage: "gift").font(.caption2.weight(.semibold))
                if let b = list.first {
                    Text(b.days == 0 ? "\(b.name) i dag!" : "\(b.name) om \(b.days) \(b.days == 1 ? "dag" : "dage")")
                        .font(.headline).lineLimit(1)
                    Text("fylder \(b.turning)").font(.caption2)
                } else {
                    Text("Ingen fødselsdage endnu").font(.caption)
                }
            }
            .containerBackground(for: .widget) { Color.clear }
        case .accessoryInline:
            if let b = list.first {
                Label(b.days == 0 ? "\(b.name) har fødselsdag i dag" : "\(b.name) om \(b.days) dage", systemImage: "gift")
            } else {
                Label("Fødselsdage", systemImage: "gift")
            }
        default:
            homeScreen(list)
        }
    }

    private func homeScreen(_ list: [UpcomingBirthday]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Fødselsdage", systemImage: "gift")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(WTheme.muted)
            if list.isEmpty {
                Text("Tilføj fødselsdage i appen under Familie.")
                    .font(.caption).foregroundStyle(WTheme.muted)
                Spacer(minLength: 0)
            } else if family == .systemSmall, let first = list.first {
                Spacer(minLength: 0)
                if first.days == 0 {
                    Image(systemName: "gift.fill").font(.system(size: 34)).foregroundStyle(WTheme.rose)
                } else {
                    Text("\(first.days)").font(WTheme.serif(40)).foregroundStyle(WTheme.text)
                }
                Text(first.days == 0 ? "I dag!" : (first.days == 1 ? "dag til" : "dage til"))
                    .font(.caption).foregroundStyle(WTheme.muted)
                Text(first.name)
                    .font(.subheadline.weight(.medium)).foregroundStyle(WTheme.text).lineLimit(1)
                Text("fylder \(first.turning)").font(.caption2).foregroundStyle(WTheme.muted)
            } else {
                let count = family == .systemLarge ? 8 : 3
                ForEach(list.prefix(count)) { b in
                    HStack(spacing: 10) {
                        Group {
                            if b.days == 0 {
                                Image(systemName: "gift.fill").foregroundStyle(WTheme.rose)
                            } else {
                                Text("\(b.days)").font(WTheme.serif(16)).minimumScaleFactor(0.6).lineLimit(1)
                            }
                        }
                        .frame(width: 40, height: 30)
                            .background {
                                // I gennemsigtig/tonet stil tegner iOS alt i én farve, så en fyldt
                                // kasse ville skjule tallet. Der bruges en kant i stedet.
                                if renderingMode == .fullColor {
                                    RoundedRectangle(cornerRadius: 8).fill(WTheme.card)
                                } else {
                                    RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.5), lineWidth: 1)
                                }
                            }
                        VStack(alignment: .leading, spacing: 0) {
                            Text(b.name).font(.subheadline.weight(.medium)).lineLimit(1)
                            Text(b.days == 0 ? "I dag · fylder \(b.turning)"
                                 : "\(b.days == 1 ? "1 dag" : "\(b.days) dage") · fylder \(b.turning)")
                                .font(.caption2).foregroundStyle(WTheme.muted)
                        }
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(WTheme.text)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(WTheme.bg, for: .widget)
    }
}

struct BirthdaysWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "birthdays", provider: FamilyProvider()) { BirthdaysView(entry: $0) }
            .configurationDisplayName("Fødselsdage")
            .description("Nedtælling til de næste fødselsdage i familien — også på låseskærmen.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Termin

struct DueView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FamilyEntry

    var body: some View {
        let due = entry.snapshot.due.min(by: { $0.dueDate < $1.dueDate })
        let days = due.map { max(0, daysUntil($0.dueDate, from: entry.date)) }
        switch family {
        case .accessoryCircular:
            // Låseskærm, lille cirkel: dage til termin.
            ZStack {
                AccessoryWidgetBackground()
                if let days {
                    VStack(spacing: -2) {
                        Text("\(days)").font(.system(size: 22, weight: .semibold, design: .serif))
                        Text("dage").font(.system(size: 9))
                    }
                } else {
                    Image(systemName: "heart")
                }
            }
            .containerBackground(for: .widget) { Color.clear }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label("Termin", systemImage: "heart").font(.caption2.weight(.semibold))
                if let due, let days {
                    Text(days == 1 ? "1 dag til termin" : "\(days) dage til termin").font(.headline)
                    Text("\(due.name) · uge \(max(1, 40 - Int((Double(days) / 7).rounded(.up)) + 1))").font(.caption2)
                } else {
                    Text("Intet barn på vej").font(.caption)
                }
            }
            .containerBackground(for: .widget) { Color.clear }
        case .accessoryInline:
            if let due, let days {
                Label("\(days) dage til termin · \(due.name)", systemImage: "heart")
            } else {
                Label("Vores familie", systemImage: "heart")
            }
        default:
            homeScreen
        }
    }

    private var homeScreen: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Termin", systemImage: "heart")
                .font(.caption2.weight(.semibold)).foregroundStyle(WTheme.muted)
            Spacer(minLength: 0)
            if let due = entry.snapshot.due.min(by: { $0.dueDate < $1.dueDate }) {
                let days = max(0, daysUntil(due.dueDate, from: entry.date))
                let week = max(1, 40 - Int((Double(days) / 7).rounded(.up)) + 1)
                Text("\(days)").font(WTheme.serif(40)).foregroundStyle(WTheme.accent)
                Text(days == 1 ? "dag til termin" : "dage til termin").font(.caption).foregroundStyle(WTheme.muted)
                Text("\(due.name) · uge \(week)").font(.caption.weight(.medium)).foregroundStyle(WTheme.text).lineLimit(1)
            } else {
                Text("Intet barn på vej lige nu.").font(.caption).foregroundStyle(WTheme.muted)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(WTheme.bg, for: .widget)
    }
}

struct DueWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "due", provider: FamilyProvider()) { DueView(entry: $0) }
            .configurationDisplayName("Termin")
            .description("Dage til termin for barnet på vej — også på låseskærmen.")
            .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - I dag (låseskærm + lille widget)

/// "Theo er 6 måneder i dag", "Uge 31 i dag" eller næste mærkedag.
struct TodayView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FamilyEntry

    struct Line { let title: String; let detail: String; let today: Bool }

    private var line: Line? {
        let cal = Calendar.current
        let now = cal.startOfDay(for: entry.date)
        var next: (date: Date, line: Line)?
        for c in entry.snapshot.children {
            if let birth = c.birthDate {
                // Månedsdag: samme dag i måneden som fødslen (sidste dag, hvis måneden er kortere).
                let months = cal.dateComponents([.month], from: birth, to: now).month ?? 0
                for n in [months, months + 1] where n > 0 {
                    guard let d = cal.date(byAdding: .month, value: n, to: birth) else { continue }
                    let day = cal.startOfDay(for: d)
                    let age: String
                    if n % 12 == 0 { age = n == 12 ? "1 år" : "\(n / 12) år" }
                    else if n > 12 { age = "\(n / 12) år og \(n % 12) mdr." }
                    else { age = n == 1 ? "1 måned" : "\(n) måneder" }
                    if day == now { return Line(title: "\(c.name) er \(age) i dag", detail: "Tag månedens billede 📸", today: true) }
                    if day > now, next == nil || day < next!.date {
                        let days = daysUntil(day, from: now)
                        next = (day, Line(title: "\(c.name) bliver \(age)", detail: days == 1 ? "i morgen" : "om \(days) dage", today: false))
                    }
                }
            } else if let due = c.dueDate, due > now, let start = cal.date(byAdding: .day, value: -280, to: due) {
                let days = cal.dateComponents([.day], from: cal.startOfDay(for: start), to: now).day ?? 0
                let week = days / 7 + 1
                if days % 7 == 0 { return Line(title: "Uge \(week) i dag", detail: "\(c.name) · \(daysUntil(due, from: now)) dage til termin", today: true) }
                let nextWeek = cal.date(byAdding: .day, value: (week) * 7, to: start) ?? now
                if next == nil || nextWeek < next!.date {
                    next = (nextWeek, Line(title: "Uge \(week) · \(c.name)", detail: "\(daysUntil(due, from: now)) dage til termin", today: false))
                }
            }
        }
        return next?.line
    }

    var body: some View {
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                if let line {
                    Label(line.today ? "I dag" : "Snart", systemImage: line.today ? "sparkles" : "calendar")
                        .font(.caption2.weight(.semibold))
                    Text(line.title).font(.headline).lineLimit(1)
                    Text(line.detail).font(.caption2).lineLimit(1)
                } else {
                    Label("Vores familie", systemImage: "heart").font(.caption2.weight(.semibold))
                    Text(DailyQuotes.today(entry.date)).font(.caption2).lineLimit(2)
                }
            }
            .containerBackground(for: .widget) { Color.clear }
        case .accessoryInline:
            if let line { Label(line.title, systemImage: line.today ? "sparkles" : "calendar") }
            else { Label("Vores familie", systemImage: "heart") }
        default:
            VStack(alignment: .leading, spacing: 6) {
                Label(line?.today == true ? "I dag" : "Snart", systemImage: line?.today == true ? "sparkles" : "calendar")
                    .font(.caption2.weight(.semibold)).foregroundStyle(WTheme.muted)
                Spacer(minLength: 0)
                if let line {
                    Text(line.title).font(WTheme.serif(17)).foregroundStyle(WTheme.text).minimumScaleFactor(0.8)
                    Text(line.detail).font(.caption).foregroundStyle(line.today ? WTheme.rose : WTheme.muted)
                } else {
                    Text(DailyQuotes.today(entry.date))
                        .font(WTheme.serif(13, .regular).italic()).foregroundStyle(WTheme.accent).lineLimit(4)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .containerBackground(WTheme.bg, for: .widget)
        }
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "today", provider: FamilyProvider()) { TodayView(entry: $0) }
            .configurationDisplayName("I dag")
            .description("\"Theo er 6 måneder i dag\" — månedsdage og graviditetsuger, også på låseskærmen.")
            .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - På denne dag

struct OnThisDayView: View {
    let entry: FamilyEntry

    private var today: [WidgetSnapshot.Memory] {
        let cal = Calendar.current
        let now = cal.dateComponents([.year, .month, .day], from: entry.date)
        return entry.snapshot.memories.filter { m in
            let c = cal.dateComponents([.year, .month, .day], from: m.date)
            return c.month == now.month && c.day == now.day && (c.year ?? 0) < (now.year ?? 0)
        }
        .sorted { $0.date > $1.date }
    }

    /// Det lille billede, appen har gemt i App Group'en til dette minde (hvis der er et).
    private func photo(_ m: WidgetSnapshot.Memory) -> UIImage? {
        guard let file = m.photoFile, let url = AppGroup.containerURL?.appendingPathComponent(file),
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Label("På denne dag", systemImage: "clock.arrow.circlepath")
                    .font(.caption2.weight(.semibold)).foregroundStyle(WTheme.muted)
                if let m = today.first {
                    let years = Calendar.current.component(.year, from: entry.date) - Calendar.current.component(.year, from: m.date)
                    Text(years == 1 ? "For 1 år siden" : "For \(years) år siden")
                        .font(.caption.weight(.medium)).foregroundStyle(WTheme.rose)
                    Text(m.text).font(WTheme.serif(15)).foregroundStyle(WTheme.text).lineLimit(3)
                    Text("\(m.who) · \(m.kind)").font(.caption2).foregroundStyle(WTheme.muted)
                } else {
                    Text(DailyQuotes.today(entry.date))
                        .font(WTheme.serif(14, .regular).italic()).foregroundStyle(WTheme.accent).lineLimit(4)
                }
                Spacer(minLength: 0)
            }
            // Mindets billede til højre, når appen har lagt et klar.
            if let m = today.first, let image = photo(m) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(WTheme.bg, for: .widget)
    }
}

struct OnThisDayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "onthisday", provider: FamilyProvider()) { OnThisDayView(entry: $0) }
            .configurationDisplayName("På denne dag")
            .description("Minder fra samme dato tidligere år — ellers dagens citat.")
            .supportedFamilies([.systemMedium])
    }
}

// MARK: - Dagens citat

struct QuoteView: View {
    let entry: FamilyEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "quote.opening").foregroundStyle(WTheme.rose.opacity(0.7))
            Text(DailyQuotes.today(entry.date))
                .font(WTheme.serif(15, .regular).italic())
                .foregroundStyle(WTheme.accent)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(WTheme.card, for: .widget)
    }
}

struct QuoteWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "quote", provider: FamilyProvider()) { QuoteView(entry: $0) }
            .configurationDisplayName("Dagens citat")
            .description("Et nyt lille citat om familie og kærlighed hver dag.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Bundle

@main
struct VoresFamilieWidgets: WidgetBundle {
    var body: some Widget {
        BirthdaysWidget()
        DueWidget()
        TodayWidget()
        OnThisDayWidget()
        QuoteWidget()
    }
}
