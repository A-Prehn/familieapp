import Foundation
import StoreKit
import UIKit

// Betaling med StoreKit 2 — ingen server. Apple signerer købene, og appen læser dem lokalt.
//
// Tre måder at få Premium:
//  • Månedligt abonnement (19 kr/md):   net.prehn.mindebog.premium.monthly
//  • Årligt abonnement (179 kr/år):     net.prehn.mindebog.premium.yearly  (samme abonnementsgruppe)
//  • Engangskøb for altid (499 kr):     net.prehn.mindebog.premium.lifetime
//
// Købet hører til køberens Apple-ID. For at partneren og bedsteforældrene i den delte familie
// også får gavn af det, skriver køberens telefon en dato ("premium til og med") på familien
// i iCloud. Appen har Premium, hvis enten ens eget køb ELLER familiens dato er gyldig.
@MainActor
final class Purchases: ObservableObject {
    static let shared = Purchases()

    static let monthlyID = "net.prehn.mindebog.premium.monthly"
    static let yearlyID = "net.prehn.mindebog.premium.yearly"
    static let lifetimeID = "net.prehn.mindebog.premium.lifetime"
    private static let allIDs = [monthlyID, yearlyID, lifetimeID]
    /// "For altid" gemmes som en dato langt ude i fremtiden.
    static let forever = Date(timeIntervalSince1970: 32_503_680_000)   // år 3000

    @Published private(set) var monthly: Product?
    @Published private(set) var yearly: Product?
    @Published private(set) var lifetime: Product?
    /// Ens eget køb: nil = intet, ellers udløbsdato (forever ved engangskøb).
    @Published private(set) var ownUntil: Date?
    @Published private(set) var loadingProducts = false
    /// Sidste fejl ved hentning af produkterne (vises i paywallen, så man kan prøve igen).
    @Published private(set) var productError: String?

    private var updates: Task<Void, Never>?

    var ownsLifetime: Bool { ownUntil == Self.forever }
    var hasOwnPremium: Bool { (ownUntil ?? .distantPast) > Date() }

    private init() {
        // Køb, der gennemføres uden for appen (fx forlængelse eller "Spørg først"), kommer ind her.
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self?.refreshEntitlements()
                }
            }
        }
    }

    /// Henter de tre produkter fra App Store. Prøver op til tre gange med kort pause, fordi
    /// App Store (især sandkassen, som Apples testere bruger) af og til svarer tomt første gang.
    /// Årsabonnementet er nyt i 1.1 — mangler det (fx før Apple har godkendt det), vises de andre stadig.
    func loadProducts() async {
        guard monthly == nil || yearly == nil || lifetime == nil, !loadingProducts else { return }
        loadingProducts = true
        productError = nil
        defer { loadingProducts = false }
        for attempt in 0..<3 {
            if attempt > 0 { try? await Task.sleep(for: .seconds(Double(attempt) * 1.5)) }
            do {
                let products = try await Product.products(for: Self.allIDs)
                monthly = products.first { $0.id == Self.monthlyID } ?? monthly
                yearly = products.first { $0.id == Self.yearlyID } ?? yearly
                lifetime = products.first { $0.id == Self.lifetimeID } ?? lifetime
                if monthly != nil && lifetime != nil { return }
                productError = "App Store returnerede ingen produkter."
            } catch {
                productError = error.localizedDescription
            }
        }
    }

    /// Læser de gyldige køb fra Apple (lokalt, signeret).
    func refreshEntitlements() async {
        var until: Date?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let t) = result, t.revocationDate == nil else { continue }
            switch t.productID {
            case Self.lifetimeID: until = Self.forever
            case Self.monthlyID, Self.yearlyID:
                if let exp = t.expirationDate, exp > (until ?? .distantPast) { until = exp }
            default: break
            }
        }
        ownUntil = until
    }

    enum Outcome { case success, cancelled, pending, failed(String) }

    func buy(_ product: Product) async -> Outcome {
        do {
            // Køb vises altid i det aktive vindue. Uden det kan iOS (især på iPad, hvor appen kører i
            // iPhone-tilstand) ikke finde et sted at vise Apples købsark, og intet sker.
            let result: Product.PurchaseResult
            if let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }) {
                result = try await product.purchase(confirmIn: scene)
            } else {
                result = try await product.purchase()
            }
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    return .failed("Købet kunne ikke bekræftes af Apple.")
                }
                await transaction.finish()
                await refreshEntitlements()
                return .success
            case .userCancelled: return .cancelled
            case .pending: return .pending
            @unknown default: return .cancelled
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// "Gendan køb": henter køb fra App Store igen (fx på en ny telefon).
    func restore() async -> Bool {
        try? await AppStore.sync()
        await refreshEntitlements()
        return hasOwnPremium
    }
}
