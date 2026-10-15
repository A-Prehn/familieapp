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
    do {
        try await work()
        dismiss()
    } catch {
        errorMessage.wrappedValue = SaveError.message(for: error)
    }
    saving.wrappedValue = false
}

extension View {
    /// Viser gem-fejlen som en alert.
    func saveErrorAlert(_ message: Binding<String?>) -> some View {
        alert("Kunne ikke gemme", isPresented: Binding(
            get: { message.wrappedValue != nil },
            set: { if !$0 { message.wrappedValue = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}
