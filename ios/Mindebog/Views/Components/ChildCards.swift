import SwiftUI

// Børnekort og alders-tekster — bruges på både Hjem og Familie.

enum ChildAge {
    /// Kort: "4 mdr." / "2 år" / "31 dage til termin"
    static func short(_ child: Child) -> String {
        if child.onTheWay, let due = child.dueDate {
            let days = Calendar.current.dateComponents([.day], from: Date(), to: due).day ?? 0
            return days > 0 ? "\(days) dage til termin" : "Termin nået"
        }
        if let birth = child.birthDate {
            let months = Calendar.current.dateComponents([.month], from: birth, to: Date()).month ?? 0
            return months < 24 ? "\(max(0, months)) mdr." : "\(months / 12) år"
        }
        return "Ingen fødselsdato"
    }

    /// Præcis, til "i dag": "Uge 31 · 62 dage til termin" / "4 mdr. og 3 dage" / "2 år og 1 md."
    static func today(_ child: Child) -> String {
        let cal = Calendar.current
        let now = cal.startOfDay(for: Date())
        if child.onTheWay, let due = child.dueDate {
            let days = cal.dateComponents([.day], from: now, to: cal.startOfDay(for: due)).day ?? 0
            if days <= 0 { return "Termin nået" }
            let week = max(1, 40 - Int((Double(days) / 7.0).rounded(.up)) + 1)
            return "Uge \(week) · \(days) dage til termin"
        }
        guard let birth = child.birthDate else { return "Ingen fødselsdato" }
        let c = cal.dateComponents([.year, .month, .day], from: cal.startOfDay(for: birth), to: now)
        let years = c.year ?? 0, months = c.month ?? 0, days = c.day ?? 0
        if years >= 2 {
            return months == 0 ? "\(years) år" : "\(years) år og \(months) \(months == 1 ? "md." : "mdr.")"
        }
        let totalMonths = years * 12 + months
        if totalMonths == 0 { return days == 1 ? "1 dag" : "\(days) dage" }
        let m = "\(totalMonths) \(totalMonths == 1 ? "md." : "mdr.")"
        return days == 0 ? m : "\(m) og \(days) \(days == 1 ? "dag" : "dage")"
    }
}

/// Søskendefarver: hvert køn har sin farveserie, og børn af samme køn får hver sin farve
/// efter alder (ældste først) — som på websitet (William blå, Nohr grøn).
/// Rækkefølgen gemmes på enheden, så alle skærme viser samme farve for samme barn.
enum ChildPalette {
    private static let key = "mindebog.childColorIndex"

    private static func hex(_ value: UInt32) -> Color {
        Color(red: Double((value >> 16) & 0xff) / 255,
              green: Double((value >> 8) & 0xff) / 255,
              blue: Double(value & 0xff) / 255)
    }

    static let boys: [Color] = [hex(0x5b7fa6), Theme.green, hex(0x2a9d8f), hex(0x5b6bc0), hex(0x4f7a94)]
    static let girls: [Color] = [Theme.rose, hex(0xe07a5f), hex(0x9b6bb8), hex(0xa0446a), hex(0xd98c5f)]
    static let neutral: [Color] = [hex(0x7a8a5a), hex(0x8a6f5a), hex(0x5f7f8a), hex(0x8a5f7a)]

    /// Kaldes når børnene er indlæst; tildeler farveplads pr. køn efter alder.
    static func update(_ children: [Child]) {
        var map: [String: Int] = [:]
        for gender in Gender.allCases {
            let sameGender = children
                .filter { $0.gender == gender }
                .sorted { a, b in
                    let da = a.birthDate ?? a.dueDate ?? .distantFuture
                    let db = b.birthDate ?? b.dueDate ?? .distantFuture
                    return da == db ? a.name < b.name : da < db
                }
            for (index, child) in sameGender.enumerated() { map[child.id] = index }
        }
        UserDefaults.standard.set(map, forKey: key)
    }

    static func color(for child: Child) -> Color {
        let map = UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:]
        let index = map[child.id] ?? 0
        let series: [Color]
        switch child.gender {
        case .boy: series = boys
        case .girl: series = girls
        case .unspecified: series = neutral
        }
        return series[index % series.count]
    }
}

/// Avatar som på websitet: barnets billede hvis sat, ellers initialer i serif —
/// og et hjerte for et barn på vej. Cirklens farve følger kønnet.
struct ChildAvatar: View {
    let child: Child
    var size: CGFloat = 56

    var body: some View {
        ZStack {
            if let photo = child.photo {
                DataImage(data: photo)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                Circle().strokeBorder(tint.opacity(0.35), lineWidth: 1)
            } else {
                Circle().fill(tint.opacity(0.18))
                Circle().strokeBorder(tint.opacity(0.25), lineWidth: 1)
                if child.onTheWay {
                    Image(systemName: "heart")
                        .font(.system(size: size * 0.38, weight: .light))
                        .foregroundStyle(textTint)
                } else {
                    Text(initials)
                        .font(.serifTitle(size * 0.34))
                        .foregroundStyle(textTint)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("\(child.name), \(ChildAge.short(child))")
    }

    // Som på websitet: på vej = varm gul, ellers søskendefarven for kønnet.
    private var tint: Color {
        child.onTheWay ? Theme.neutral : ChildPalette.color(for: child)
    }

    private var textTint: Color {
        child.onTheWay ? Theme.neutralDark : ChildPalette.color(for: child)
    }

    /// "William" → "WI", "Baby Blob" → "BB" (første bogstav i de to første ord).
    private var initials: String {
        let words = child.name.split(separator: " ").filter { !$0.isEmpty }
        let letters: String
        if words.count >= 2 {
            letters = String(words[0].prefix(1)) + String(words[1].prefix(1))
        } else {
            letters = String(child.name.trimmingCharacters(in: .whitespaces).prefix(2))
        }
        return letters.uppercased()
    }
}

struct ChildCard: View {
    let child: Child
    var body: some View {
        VStack(spacing: 10) {
            ChildAvatar(child: child, size: 56)
            Text(child.displayName).font(.serifTitle(16)).foregroundStyle(Theme.text)
            Text(ChildAge.short(child)).font(.caption).foregroundStyle(Theme.muted)
            // Tydeligt, at kortet kan åbnes: højdepunkter, milepæle, billeder m.m. ligger herinde.
            HStack(spacing: 4) {
                Text("Åbn mindebog").font(.caption.weight(.semibold))
                Image(systemName: "chevron.right").font(.caption2.weight(.bold))
            }
            .foregroundStyle(Theme.tint)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(Theme.tint.opacity(0.1)))
        }
        .frame(maxWidth: .infinity).padding(.vertical, 18)
        .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Theme.sep))

        .accessibilityHint("Åbner \(child.name)s mindebog")
    }
}

struct AddChildCard: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "plus").font(.system(size: 28, weight: .light))
            Text("Tilføj barn").font(.serifTitle(16))
        }
        .foregroundStyle(Theme.tint)
        .frame(maxWidth: .infinity).padding(.vertical, 20)
        .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Theme.sep, style: StrokeStyle(lineWidth: 1, dash: [4])))
    }
}

/// Øverst i en formular: "Gemmes for Ida, Theo og Lillebror" (kun ved flere børn).
struct ForChildrenNote: View {
    let names: [String]
    var body: some View {
        if names.count > 1 {
            Section {
                Label("Gemmes for \(Self.list(names))", systemImage: "person.2")
                    .font(.footnote)
                    .foregroundStyle(Theme.neutralDark)
            }
        }
    }

    static func list(_ names: [String]) -> String {
        guard names.count > 1, let last = names.last else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " og " + last
    }
}

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.caption2).tracking(1.4)
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
