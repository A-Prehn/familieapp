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
                        .font(.system(size: size * 0.34, weight: .medium, design: .serif))
                        .foregroundStyle(textTint)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("\(child.name), \(ChildAge.short(child))")
    }

    // Som på websitet: på vej = varm gul, ellers efter køn.
    private var tint: Color {
        if child.onTheWay { return Theme.neutral }
        switch child.gender {
        case .girl: return Theme.rose
        case .boy: return Theme.tint
        case .unspecified: return Theme.green
        }
    }

    private var textTint: Color {
        if child.onTheWay { return Theme.neutralDark }
        switch child.gender {
        case .girl: return Theme.rose
        case .boy: return Theme.tint
        case .unspecified: return Theme.green
        }
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
            Text(child.name).font(.serifTitle(16)).foregroundStyle(Theme.text)
            Text(ChildAge.short(child)).font(.caption).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 20)
        .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.sep))
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
        .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.sep, style: StrokeStyle(lineWidth: 1, dash: [4])))
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
