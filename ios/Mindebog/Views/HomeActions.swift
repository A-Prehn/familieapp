import SwiftUI

/// Hurtigknapperne på Hjem. Man vælger selv op til fire og deres rækkefølge (gemt på telefonen).
enum HomeAction: String, CaseIterable, Identifiable {
    case highlight, diary, monthly, belly, drawing, voice    // for et barn
    case event, vacation, birthday, tradition               // for hele familien

    var id: String { rawValue }

    static let storageKey = "mindebog.homeActions"
    static let defaults: [HomeAction] = [.highlight, .diary, .event]
    static let maxCount = 4

    /// Læser valget; ukendte værdier ignoreres, og et tomt valg giver standarden.
    static func load(_ raw: String) -> [HomeAction] {
        let list = raw.split(separator: ",").compactMap { HomeAction(rawValue: String($0)) }
        return list.isEmpty ? defaults : Array(list.prefix(maxCount))
    }
    static func save(_ list: [HomeAction]) -> String { list.map(\.rawValue).joined(separator: ",") }

    var title: String {
        switch self {
        case .highlight: return "Højdepunkt"
        case .diary: return "Dagbog"
        case .monthly: return "Månedsbillede"
        case .belly: return "Mavebillede"
        case .drawing: return "Tegning"
        case .voice: return "Optag stemme"
        case .event: return "Begivenhed"
        case .vacation: return "Ferie"
        case .birthday: return "Fødselsdag"
        case .tradition: return "Tradition"
        }
    }

    var symbol: String {
        switch self {
        case .highlight: return "star"
        case .diary: return "book"
        case .monthly: return "photo.on.rectangle"
        case .belly: return "leaf"
        case .drawing: return "paintpalette"
        case .voice: return "mic"
        case .event: return "calendar.badge.plus"
        case .vacation: return "beach.umbrella"
        case .birthday: return "gift"
        case .tradition: return "sparkles"
        }
    }

    var color: Color {
        switch self {
        case .highlight, .voice: return Theme.rose
        case .diary, .tradition: return Theme.neutralDark
        case .monthly, .event, .drawing: return Theme.tint
        case .belly, .vacation, .birthday: return Theme.green
        }
    }

    /// Kræver et barn (og evt. valg af barn), eller hører det til hele familien?
    var isForChild: Bool {
        switch self {
        case .highlight, .diary, .monthly, .belly, .drawing, .voice: return true
        default: return false
        }
    }

    /// Kan samme indlæg gemmes for flere børn på én gang?
    var allowsSeveral: Bool { self == .highlight || self == .diary || self == .monthly }

    /// Hvilke børn der giver mening: mavebillede kun for børn på vej, resten kun for fødte.
    func fits(_ child: Child) -> Bool {
        switch self {
        case .belly: return child.onTheWay
        case .monthly, .drawing, .voice: return !child.onTheWay
        default: return true
        }
    }
}

/// Vælg op til fire hurtigknapper til Hjem — tryk for at tilføje/fjerne, træk for at ændre rækkefølgen.
struct HomeActionsEditor: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(HomeAction.storageKey) private var raw = ""
    @State private var chosen: [HomeAction] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(chosen) { action in
                        Label(action.title, systemImage: action.symbol).foregroundStyle(Theme.text)
                    }
                    .onMove { chosen.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { chosen.remove(atOffsets: $0) }
                } header: {
                    Text("På Hjem (\(chosen.count) af \(HomeAction.maxCount))")
                } footer: {
                    Text("Træk for at ændre rækkefølgen. Stryg til venstre for at fjerne.")
                }

                Section("Tilføj") {
                    ForEach(HomeAction.allCases.filter { !chosen.contains($0) }) { action in
                        Button {
                            if chosen.count < HomeAction.maxCount { chosen.append(action) }
                        } label: {
                            HStack {
                                Label(action.title, systemImage: action.symbol).foregroundStyle(Theme.text)
                                Spacer()
                                Image(systemName: "plus.circle.fill").foregroundStyle(Theme.tint)
                            }
                        }
                        .disabled(chosen.count >= HomeAction.maxCount)
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Hurtigknapper")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annullér") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gem") { raw = HomeAction.save(chosen); dismiss() }
                        .disabled(chosen.isEmpty)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Gendan standard") { chosen = HomeAction.defaults }
                }
            }
            .onAppear { chosen = HomeAction.load(raw) }
        }
    }
}
