import SwiftUI

/// "Eksportér alt" — én ZIP med hele familiens indhold, som kan gemmes i Filer,
/// sendes til computeren eller lægges i fx Google Drive/Dropbox.
struct ExportView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var export = FamilyExport()
    @State private var share: ShareSheet?

    var body: some View {
        NavigationStack {
            List {
                Group {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "archivebox")
                            .font(.system(size: 34))
                            .foregroundStyle(Theme.neutralDark)
                        Text("Hent alt ud af appen")
                            .font(.serifTitle(22))
                        Text("Alt samles i én ZIP-fil: billeder, video og lydnoter, højdepunkter, dagbog, milepæle, breve, målinger, vacciner, begivenheder, rejser og en PDF-mindebog for hvert barn.")
                            .font(.subheadline).foregroundStyle(Theme.muted)
                    }
                    .padding(.vertical, 6)
                }

                Section {
                    if export.running {
                        VStack(alignment: .leading, spacing: 8) {
                            ProgressView(value: export.progress)
                            Text(export.status).font(.footnote).foregroundStyle(Theme.muted)
                        }
                        .padding(.vertical, 4)
                    } else if let url = export.resultURL {
                        Label("Eksporten er klar", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Theme.green)
                        if let size = Self.size(of: url) {
                            Text(size).font(.footnote).foregroundStyle(Theme.muted)
                        }
                        Button { share = ShareSheet(url: url) } label: {
                            Label("Gem eller del ZIP-filen", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Button { Task { await start() } } label: {
                            Label("Eksportér alt", systemImage: "square.and.arrow.down.on.square")
                        }
                        .disabled(state.familyId == nil)
                    }
                    if let err = export.errorMessage {
                        Text(err).font(.footnote).foregroundStyle(Theme.rose)
                    }
                } footer: {
                    Text(footerText)
                }
                }.listRowBackground(Theme.card)
            }
            .themedList()
            .navigationTitle("Eksportér alt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(export.running ? "Vent…" : "Luk") { dismiss() }.disabled(export.running)
                }
            }
            .interactiveDismissDisabled(export.running)
            .sheet(item: $share) { $0 }
        }
    }

    private var footerText: String {
        if export.running {
            return "Hold appen åben, mens eksporten kører. Med mange videoer kan det tage nogle minutter."
        }
        if export.resultURL != nil {
            return "Vælg \"Arkivér i Filer\" for at gemme på telefonen eller i iCloud Drive, eller send filen til din computer. Forseglede breve ligger i en mappe for sig."
        }
        return "Alt laves på telefonen — intet sendes til os. Hold appen åben, mens eksporten kører."
    }

    private func start() async {
        let familyName = (try? await state.store.families(for: state.user?.id ?? ""))?
            .first { $0.id == state.familyId }?.name ?? "Vores familie"
        guard let familyId = state.familyId else { return }
        await export.run(store: state.store, familyId: familyId, familyName: familyName)
    }

    private static func size(of url: URL) -> String? {
        guard let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
