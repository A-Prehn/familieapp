import WidgetKit
import SwiftUI
import UIKit

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
        VStack(alignment: .leading, spacing: 6) {
            Label("Fødselsdage", systemImage: "gift")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(WTheme.muted)
            if list.isEmpty {
                Text("Tilføj fødselsdage i appen under Fælles.")
                    .font(.caption).foregroundStyle(WTheme.muted)
                Spacer(minLength: 0)
            } else if family == .systemSmall, let first = list.first {
                Spacer(minLength: 0)
                Text(first.days == 0 ? "🎉" : "\(first.days)")
                    .font(WTheme.serif(first.days == 0 ? 34 : 40))
                    .foregroundStyle(WTheme.text)
                Text(first.days == 0 ? "I dag!" : (first.days == 1 ? "dag til" : "dage til"))
                    .font(.caption).foregroundStyle(WTheme.muted)
                HStack(spacing: 4) { EmojiView(emoji: first.emoji, size: 15); Text(first.name) }
                    .font(.subheadline.weight(.medium)).foregroundStyle(WTheme.text).lineLimit(1)
                Text("fylder \(first.turning)").font(.caption2).foregroundStyle(WTheme.muted)
            } else {
                let count = family == .systemLarge ? 8 : 3
                ForEach(list.prefix(count)) { b in
                    HStack(spacing: 10) {
                        Text(b.days == 0 ? "🎉" : "\(b.days)")
                            .font(WTheme.serif(16))
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
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
                            HStack(spacing: 4) { EmojiView(emoji: b.emoji, size: 15); Text(b.name) }
                                .font(.subheadline.weight(.medium)).lineLimit(1)
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
            .description("Nedtælling til de næste fødselsdage i familien.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Termin

struct DueView: View {
    let entry: FamilyEntry

    var body: some View {
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
            .description("Dage til termin for barnet på vej.")
            .supportedFamilies([.systemSmall])
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

    var body: some View {
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
        OnThisDayWidget()
        QuoteWidget()
    }
}

// MARK: - Emoji i farver

/// I gennemsigtig/tonet hjemmeskærm tegner iOS al tekst i én farve, også emojis.
/// Derfor tegnes emojien som et billede, der fra iOS 18 må vises i fulde farver.
struct EmojiView: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let emoji: String
    let size: CGFloat

    var body: some View {
        if renderingMode == .fullColor {
            Text(emoji).font(.system(size: size))
        } else if #available(iOS 18.0, *), let image = Self.render(emoji, size: size) {
            Image(uiImage: image)
                .resizable()
                .widgetAccentedRenderingMode(.fullColor)
                .frame(width: size * 1.2, height: size * 1.2)
        }
        // iOS 17 i tonet stil: emojien udelades hellere end at stå som en hvid klat.
    }

    private static func render(_ emoji: String, size: CGFloat) -> UIImage? {
        guard !emoji.isEmpty else { return nil }
        let side = size * 1.2
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            let attr = NSAttributedString(string: emoji, attributes: [.font: UIFont.systemFont(ofSize: size)])
            let s = attr.size()
            attr.draw(at: CGPoint(x: (side - s.width) / 2, y: (side - s.height) / 2))
        }
    }
}
