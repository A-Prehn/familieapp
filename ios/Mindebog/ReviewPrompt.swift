import StoreKit
import UIKit

// "Bedøm appen" — Apples egen dialog, vist efter et glad øjeblik: når man har gemt et minde.
// Første gang efter 8 gemte minder (så man kender appen), derefter tidligst efter 120 dage og
// 30 nye minder. Apple viser selv dialogen højst tre gange om året og aldrig, hvis man har svaret.
@MainActor
enum ReviewPrompt {
    private static let savesKey = "mindebog.review.saves"
    private static let lastAskedKey = "mindebog.review.lastAsked"
    private static let savesAtLastAskKey = "mindebog.review.savesAtLastAsk"

    /// Kaldes, når noget er gemt i iCloud.
    static func noteSaved() {
        let d = UserDefaults.standard
        let saves = d.integer(forKey: savesKey) + 1
        d.set(saves, forKey: savesKey)

        if let last = d.object(forKey: lastAskedKey) as? Date {
            let since = saves - d.integer(forKey: savesAtLastAskKey)
            guard Date().timeIntervalSince(last) > 120 * 86_400, since >= 30 else { return }
        } else {
            guard saves >= 8 else { return }
        }
        d.set(Date(), forKey: lastAskedKey)
        d.set(saves, forKey: savesAtLastAskKey)
        // Lidt ventetid, så formularen er lukket, og man ser sit nye minde, før dialogen kommer.
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard UIApplication.shared.applicationState == .active,
                  let scene = UIApplication.shared.connectedScenes
                    .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else { return }
            AppStore.requestReview(in: scene)
        }
    }
}
