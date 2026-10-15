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

struct ChildCard: View {
    let child: Child
    var body: some View {
        VStack(spacing: 10) {
            Circle()
                .fill(Theme.bgDark)
                .frame(width: 56, height: 56)
                .overlay(Image(systemName: "figure.child").foregroundStyle(Theme.neutralDark))
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
