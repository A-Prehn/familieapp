import SwiftUI
import MapKit

/// Verdenskort over familiens rejser (#26): én nål pr. sted, samlet når samme sted er besøgt flere gange.
struct VacationMapView: View {
    let vacations: [Vacation]
    let dateText: (Vacation) -> String?
    let onOpen: (Vacation) -> Void

    @State private var selected: String?
    @State private var countries: Set<String> = []

    /// Rejser på samme sted (afrundet til ca. 1 km) samles i én nål.
    private struct Stop: Identifiable {
        let id: String
        let place: Place
        let trips: [Vacation]
        var coordinate: CLLocationCoordinate2D { .init(latitude: place.latitude, longitude: place.longitude) }
    }

    private var stops: [Stop] {
        let withPlace = vacations.filter { $0.place != nil }
        let groups = Dictionary(grouping: withPlace) { v -> String in
            let p = v.place!
            return String(format: "%.2f,%.2f", p.latitude, p.longitude)
        }
        return groups.map { key, trips in
            let sorted = trips.sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
            return Stop(id: key, place: sorted[0].place!, trips: sorted)
        }
        .sorted { $0.id < $1.id }
    }

    private var missingPlace: Int { vacations.filter { $0.place == nil }.count }

    var body: some View {
        let stops = stops
        VStack(alignment: .leading, spacing: 12) {
            Text(counter(stops.count))
                .font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)

            Map(selection: $selected) {
                ForEach(stops) { stop in
                    Marker(stop.trips.count > 1 ? "\(stop.place.name) (\(stop.trips.count))" : stop.place.name,
                           systemImage: "airplane", coordinate: stop.coordinate)
                        .tint(Theme.rose)
                        .tag(stop.id)
                }
            }
            .mapStyle(.standard(elevation: .flat))
            .frame(height: 380)
            .noTabSwipe()   // at panorere kortet må ikke skifte hovedfane (#40)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.sep))

            if let stop = stops.first(where: { $0.id == selected }) {
                VStack(spacing: 8) {
                    ForEach(stop.trips) { trip in
                        Button { onOpen(trip) } label: { tripCard(trip) }.buttonStyle(.plain)
                    }
                }
            } else if !stops.isEmpty {
                Text("Tryk på en nål for at se rejsen.")
                    .font(.footnote).foregroundStyle(Theme.muted)
            }

            if missingPlace > 0 {
                Label(missingPlace == 1 ? "1 rejse har intet sted og vises ikke på kortet. Tilføj et sted på rejsen."
                                        : "\(missingPlace) rejser har intet sted og vises ikke på kortet. Tilføj et sted på rejserne.",
                      systemImage: "mappin.slash")
                    .font(.footnote).foregroundStyle(Theme.muted)
            }
        }
        .task(id: stops.map(\.id)) { await loadCountries(stops) }
    }

    private func counter(_ places: Int) -> String {
        var text = places == 1 ? "1 sted" : "\(places) steder"
        if !countries.isEmpty { text += countries.count == 1 ? " · 1 land" : " · \(countries.count) lande" }
        return text
    }

    private func tripCard(_ trip: Vacation) -> some View {
        HStack(spacing: 12) {
            if let data = trip.photos.coverPhoto, let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFill()
                    .frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: "beach.umbrella").frame(width: 56, height: 56)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.bg))
                    .foregroundStyle(Theme.muted)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(trip.title).font(.serifTitle(16)).foregroundStyle(Theme.text)
                if let d = dateText(trip) { Text(d).font(.caption).foregroundStyle(Theme.muted) }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.muted)
        }
        .padding(10)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.sep))
    }

    // MARK: Lande (opslag på enheden via Apple, gemt mellem visninger)

    private static var countryCache: [String: String] = [:]

    private func loadCountries(_ stops: [Stop]) async {
        let geocoder = CLGeocoder()
        var found = Set<String>()
        for stop in stops {
            if let c = Self.countryCache[stop.id] { found.insert(c); continue }
            let loc = CLLocation(latitude: stop.place.latitude, longitude: stop.place.longitude)
            if let c = try? await geocoder.reverseGeocodeLocation(loc).first?.isoCountryCode {
                Self.countryCache[stop.id] = c
                found.insert(c)
            }
            if Task.isCancelled { return }
        }
        countries = found
    }
}
