import SwiftUI

// "Hent billeder fra det første år": vælg op til 50 billeder fra Fotos fra barnets første år,
// og hvert bliver et højdepunkt med billedets egen dato og barnets alder som tekst.
// Fylder mindebogen på et minut — til dem, der starter med et barn, der allerede er lidt større.
struct FirstYearImportView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let child: Child

    static let maxPhotos = 50

    var body: some View {
        PhotoSuggestionsView(range: range, allowMultiple: true, maxSelection: Self.maxPhotos,
                             title: "\(child.name)s første år") { photos in
            save(photos)
        }
    }

    /// Fra fødslen til et år efter — eller til i dag, hvis barnet er yngre.
    private var range: ClosedRange<Date> {
        let cal = Calendar.current
        let birth = child.birthDate ?? Date()
        let start = cal.startOfDay(for: birth)
        let yearLater = cal.date(byAdding: .year, value: 1, to: start) ?? Date()
        return start...max(start, min(yearLater, Date()))
    }

    private func save(_ photos: [Data]) {
        guard !photos.isEmpty else { return }
        let store = state.store
        let childId = child.id
        let child = self.child
        // Ét gem i baggrunden for dem alle, så banneret bare viser "Gemmer…" én gang.
        SaveQueue.shared.enqueue(label: "\(photos.count) billeder fra det første år") {
            for data in photos {
                let date = ImageTools.captureDate(data)
                let text = date.map { ChildAge.at(child, date: $0) } ?? ""
                _ = try await store.addHighlight(childId: childId, date: date, text: text, photos: [data], cover: 0, place: nil)
            }
        }
        dismiss()
    }
}

extension ChildAge {
    /// Alderen på en given dato: "Nyfødt" / "3 mdr." / "1 år" — som tekst på importerede billeder.
    static func at(_ child: Child, date: Date) -> String {
        guard let birth = child.birthDate else { return "" }
        let cal = Calendar.current
        let c = cal.dateComponents([.month, .day], from: cal.startOfDay(for: birth), to: cal.startOfDay(for: date))
        let months = c.month ?? 0, days = c.day ?? 0
        if months <= 0 { return days <= 7 ? "Nyfødt" : "\(max(days, 0)) dage" }
        if months < 24 { return "\(months) \(months == 1 ? "md." : "mdr.")" }
        return "\(months / 12) år"
    }
}
