import SwiftUI
import MapKit

// Stedvælger og kortvisning for begivenheder og ferier.
// Søgning via Apple Maps (MKLocalSearch) — kræver ikke adgang til brugerens position.

/// Formular-felt: "Vælg sted" → søgeark; viser valgt sted med mulighed for at fjerne det.
struct PlaceField: View {
    @Binding var place: Place?
    @State private var searching = false

    var body: some View {
        if let place {
            VStack(alignment: .leading, spacing: 8) {
                PlaceMap(place: place, height: 140)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.name).font(.subheadline.weight(.medium))
                        if !place.address.isEmpty {
                            Text(place.address).font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                    Spacer()
                    Button("Skift") { searching = true }.font(.footnote)
                    Button(role: .destructive) { self.place = nil } label: { Image(systemName: "xmark.circle.fill") }
                        .foregroundStyle(Theme.muted)
                }
            }
            .buttonStyle(.borderless)
            .sheet(isPresented: $searching) { PlaceSearchView(place: $place) }
        } else {
            Button { searching = true } label: {
                Label("Vælg sted på kortet", systemImage: "mappin.and.ellipse")
            }
            .sheet(isPresented: $searching) { PlaceSearchView(place: $place) }
        }
    }
}

/// Lille kort med nål. Tryk åbner stedet i Apple Kort.
struct PlaceMap: View {
    let place: Place
    var height: CGFloat = 120

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
    }

    var body: some View {
        Map(initialPosition: .region(MKCoordinateRegion(center: coordinate,
                                                         latitudinalMeters: 1500, longitudinalMeters: 1500)),
            interactionModes: []) {
            Marker(place.name, coordinate: coordinate).tint(Theme.rose)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: Radius.small))
        .contentShape(Rectangle())
        .onTapGesture { openInMaps() }
    }

    private func openInMaps() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = place.name
        item.openInMaps()
    }
}

/// Kompakt linje "📍 Navn" — tryk åbner Apple Kort.
struct PlaceLabel: View {
    let place: Place
    var body: some View {
        Button {
            let coordinate = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
            let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
            item.name = place.name
            item.openInMaps()
        } label: {
            Label(place.name.isEmpty ? place.address : place.name, systemImage: "mappin.circle.fill")
                .font(.footnote)
                .foregroundStyle(Theme.tint)
                .lineLimit(1)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Søgning

@MainActor
private final class PlaceSearchModel: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var query = "" { didSet { completer.queryFragment = query } }
    @Published var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results
        Task { @MainActor in self.results = results }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.results = [] }
    }

    func resolve(_ completion: MKLocalSearchCompletion) async -> Place? {
        let request = MKLocalSearch.Request(completion: completion)
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else { return nil }
        let coordinate = item.placemark.coordinate
        let name = item.name ?? completion.title
        let address = completion.subtitle.isEmpty ? (item.placemark.title ?? "") : completion.subtitle
        return Place(name: name, address: address, latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

struct PlaceSearchView: View {
    @Binding var place: Place?
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = PlaceSearchModel()
    @State private var resolving = false

    var body: some View {
        NavigationStack {
            List {
                Group {
                if model.query.isEmpty {
                    Text("Søg efter et sted, fx \"Skagen\" eller navnet på kirken.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                }
                ForEach(model.results, id: \.self) { result in
                    Button {
                        Task {
                            resolving = true
                            if let found = await model.resolve(result) {
                                place = found
                                dismiss()
                            }
                            resolving = false
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.title).foregroundStyle(Theme.text)
                            if !result.subtitle.isEmpty {
                                Text(result.subtitle).font(.caption).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                    .disabled(resolving)
                }
                }.listRowBackground(Theme.card)
            }
            .themedList()
            .searchable(text: $model.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Søg sted")
            .navigationTitle("Vælg sted")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annullér") { dismiss() } }
            }
            .overlay { if resolving { ProgressView() } }
        }
    }
}
