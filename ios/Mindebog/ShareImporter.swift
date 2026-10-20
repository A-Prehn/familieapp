import Foundation

// Henter det, der er delt fra Fotos ("Del → Vores familie"), ind i iCloud som højdepunkter.
// Kører, når appen åbnes eller kommer frem. Hver pakke gemmes i baggrunden (SaveQueue med
// "Gemmer…"-banneret) og fjernes fra indbakken, når den er gemt for alle valgte børn.
@MainActor
enum ShareImporter {
    /// Pakker, der allerede er i gang i denne kørsel — så de ikke gemmes to gange.
    private static var inFlight: Set<String> = []

    static func importPending(store: Store) {
        for package in ShareInbox.pending() {
            let key = package.folder.lastPathComponent
            guard !inFlight.contains(key) else { continue }
            inFlight.insert(key)
            let meta = package.meta
            let photos = package.photos
            guard !photos.isEmpty, !meta.childIds.isEmpty else { ShareInbox.remove(package); continue }
            let label = photos.count == 1 ? "Billede fra Fotos" : "\(photos.count) billeder fra Fotos"
            SaveQueue.shared.enqueue(label: label) {
                for childId in meta.childIds {
                    _ = try await store.addHighlight(childId: childId, date: meta.date ?? meta.created, text: meta.text,
                                                     photos: photos, cover: 0, place: nil)
                }
                ShareInbox.remove(package)
                await MainActor.run { _ = inFlight.remove(key) }
            }
        }
    }
}
