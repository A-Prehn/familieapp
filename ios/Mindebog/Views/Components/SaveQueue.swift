import SwiftUI

// Gem i baggrunden: formularen lukker med det samme, og uploaden til iCloud kører bagved.
// Et lille banner viser "Gemmer…", og går det galt, kan man prøve igen eller kassere.
// Når et gem er færdigt, får listerne besked (.storeDidChange), så det nye vises straks.
extension Notification.Name {
    static let storeDidChange = Notification.Name("mindebog.storeDidChange")
    /// Telefonen har fået net igen (fra NetworkWatch).
    static let networkBack = Notification.Name("mindebog.networkBack")
}

/// Hvor mange gem der venter i udbakken på at nå iCloud (#63).
@MainActor
final class OutboxStatus: ObservableObject {
    static let shared = OutboxStatus()
    @Published var pending = 0
}

@MainActor
final class SaveQueue: ObservableObject {
    static let shared = SaveQueue()

    struct Failed: Identifiable {
        let id = UUID()
        let label: String
        let message: String
        let work: () async throws -> Void
    }

    @Published private(set) var running = 0
    @Published private(set) var failed: [Failed] = []
    /// Gem, der kører i en åben formular (vises som "Gemmer…" i formularen).
    @Published var foreground = 0

    func enqueue(label: String, _ work: @escaping () async throws -> Void) {
        running += 1
        Task {
            do {
                try await work()
                Haptics.success()
                ReviewPrompt.noteSaved()
            } catch StoreError.queuedOffline {
                // Ligger i udbakken og sendes af sig selv, når der er net (#63) — banneret viser det.
            } catch {
                failed.append(Failed(label: label, message: SaveError.message(for: error), work: work))
            }
            running -= 1
            NotificationCenter.default.post(name: .storeDidChange, object: nil)
        }
    }

    func retry(_ item: Failed) {
        failed.removeAll { $0.id == item.id }
        enqueue(label: item.label, item.work)
    }

    func discard(_ item: Failed) {
        failed.removeAll { $0.id == item.id }
    }
}

/// Banner nederst på skærmen: "Gemmer…" mens der uploades, og fejl med "Prøv igen".
struct SaveQueueBanner: View {
    @ObservedObject private var queue = SaveQueue.shared
    @ObservedObject private var sync = SyncStatus.shared
    @ObservedObject private var outbox = OutboxStatus.shared
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 8) {
            // Gem uden net (#63): ligger sikkert på telefonen og sendes, når nettet er tilbage.
            if outbox.pending > 0 && queue.running == 0 {
                HStack(spacing: 8) {
                    Image(systemName: "icloud.and.arrow.up").font(.caption)
                    Text(outbox.pending == 1 ? "1 venter på iCloud" : "\(outbox.pending) venter på iCloud")
                        .font(.caption.weight(.medium))
                    Button("Kassér", role: .destructive) {
                        (state.store as? CloudKitStore)?.discardOutbox()
                    }
                    .font(.caption)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(Theme.card))
                .overlay(Capsule().stroke(Theme.sep))
                .foregroundStyle(Theme.text)
            }
            // Første gang en familie hentes til telefonen (#62): vis, at der sker noget.
            if sync.fetching {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(sync.fetchedRecords > 0 ? "Henter familien … \(sync.fetchedRecords)" : "Henter familien …")
                        .font(.caption.weight(.medium))
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(Theme.card))
                .overlay(Capsule().stroke(Theme.sep))
                .foregroundStyle(Theme.text)
            }
            ForEach(queue.failed) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Text("Kunne ikke gemme \(item.label)").font(.subheadline.weight(.semibold))
                    Text(item.message).font(.caption)
                    HStack {
                        Button("Prøv igen") { queue.retry(item) }.font(.caption.weight(.semibold))
                        Spacer()
                        Button("Kassér", role: .destructive) { queue.discard(item) }.font(.caption)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Theme.rose))
                .foregroundStyle(Theme.text)
            }
            if queue.running > 0 {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(queue.running == 1 ? "Gemmer…" : "Gemmer \(queue.running)…").font(.caption.weight(.medium))
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(Theme.card))
                .overlay(Capsule().stroke(Theme.sep))
                .foregroundStyle(Theme.text)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .animation(.easeInOut(duration: 0.2), value: queue.running)
        .animation(.easeInOut(duration: 0.2), value: queue.failed.count)
        .animation(.easeInOut(duration: 0.2), value: sync.fetching)
        .animation(.easeInOut(duration: 0.2), value: outbox.pending)
    }
}

/// Luk arket med det samme, og gem i baggrunden. Fang alle værdier fra formularen i
/// lokale konstanter FØR kaldet — closuren kører, efter arket er lukket.
@MainActor
func performSaveInBackground(label: String, dismiss: DismissAction, _ work: @escaping () async throws -> Void) {
    dismiss()
    SaveQueue.shared.enqueue(label: label, work)
}

extension View {
    /// Indlæs igen, når et gem i baggrunden er færdigt (eller noget andet er gemt).
    func reloadOnStoreChange(_ reload: @escaping () async -> Void) -> some View {
        onReceive(NotificationCenter.default.publisher(for: .storeDidChange)) { _ in Task { await reload() } }
    }
}
