import SwiftUI
import CloudKit

// Fælles gem-håndtering for formularerne: luk kun ved succes, vis en forståelig
// fejl ved problemer (så intet forsvinder i stilhed), og bloker dobbelttryk imens.

enum SaveError {
    /// Dansk besked til brugeren ud fra fejlen.
    static func message(for error: Error) -> String {
        if let ck = error as? CKError {
            switch ck.code {
            case .networkUnavailable, .networkFailure:
                return "Ingen forbindelse til iCloud. Tjek internettet og prøv igen."
            case .notAuthenticated:
                return "Du er ikke logget ind på iCloud på denne iPhone."
            case .quotaExceeded:
                return "Din iCloud-lagerplads er fuld."
            case .serverRecordChanged:
                return "Det er lige blevet ændret på en anden enhed. Luk og åbn igen, og prøv så igen."
            case .permissionFailure:
                return "Du har ikke adgang til at ændre dette."
            case .serviceUnavailable, .requestRateLimited, .zoneBusy:
                return "iCloud er optaget lige nu. Vent et øjeblik og prøv igen."
            default:
                break
            }
        }
        return "Kunne ikke gemme: \(error.localizedDescription)"
    }
}

/// Kør en gem-handling: `saving` er true imens; ved succes lukkes arket,
/// ved fejl sættes `errorMessage`, og arket bliver stående.
@MainActor
func performSave(saving: Binding<Bool>, errorMessage: Binding<String?>,
                 dismiss: DismissAction, _ work: () async throws -> Void) async {
    guard !saving.wrappedValue else { return }
    saving.wrappedValue = true
    errorMessage.wrappedValue = nil
    SaveQueue.shared.foreground += 1          // viser "Gemmer…" i formularen
    defer { SaveQueue.shared.foreground -= 1 }
    do {
        try await work()
        Haptics.success()
        dismiss()
        NotificationCenter.default.post(name: .storeDidChange, object: nil)
    } catch {
        errorMessage.wrappedValue = SaveError.message(for: error)
    }
    saving.wrappedValue = false
}

/// "Gemmer…" midt i formularen, mens et gem kører — så man kan se, at der sker noget.
private struct SavingOverlay: View {
    @ObservedObject private var queue = SaveQueue.shared

    var body: some View {
        if queue.foreground > 0 {
            ZStack {
                Color.black.opacity(0.12).ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView().controlSize(.large)
                    Text("Gemmer…").font(.subheadline.weight(.semibold))
                    Text("Store billeder og videoer kan tage lidt tid.")
                        .font(.caption).foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                .frame(maxWidth: 260)
                .background(RoundedRectangle(cornerRadius: 18).fill(Theme.card))
                .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
            }
            .transition(.opacity)
        }
    }
}

extension View {
    /// Viser gem-fejlen som en alert.
    /// Alle formularer bruger denne, så "Gemmer…" vises automatisk overalt.
    func saveErrorAlert(_ message: Binding<String?>) -> some View {
        overlay { SavingOverlay() }
        .alert("Kunne ikke gemme", isPresented: Binding(
            get: { message.wrappedValue != nil },
            set: { if !$0 { message.wrappedValue = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}
