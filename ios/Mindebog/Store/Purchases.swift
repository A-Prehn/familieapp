import Foundation
import StoreKit

// Betaling med StoreKit 2 — ingen server. Apple signerer købene, og appen læser dem lokalt.
//
// To måder at få Premium:
//  • Månedligt abonnement (19 kr/md):  net.prehn.mindebog.premium.monthly
//  • Engangskøb for altid (199 kr):    net.prehn.mindebog.premium.lifetime
//
// Købet hører til køberens Apple-ID. For at partneren og bedsteforældrene i den delte familie
// også får gavn af det, skriver køberens telefon en dato ("premium til og med") på familien
// i iCloud. Appen har Premium, hvis enten ens eget køb ELLER familiens dato er gyldig.
@MainActor
final class Purchases: ObservableObject {
    static let shared = Purchases()

    static let monthlyID = "net.prehn.mindebog.premium.monthly"
    static let lifetimeID = "net.prehn.mindebog.premium.lifetime"
    /// "For altid" gemmes som en dato langt ude i fremtiden.
    static let forever = Date(timeIntervalSince1970: 32_503_680_000)   // år 3000

    @Published private(set) var monthly: Product?
    @Published private(set) var lifetime: Product?
    /// Ens eget køb: nil = intet, ellers udløbsdato (forever ved engangskøb).
    @Published private(set) var ownUntil: Date?
    @Published private(set) var loadingProducts = false

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

    func loadProducts() async {
        guard monthly == nil || lifetime == nil else { return }
        loadingProducts = true
        defer { loadingProducts = false }
        if let products = try? await Product.products(for: [Self.monthlyID, Self.lifetimeID]) {
            monthly = products.first { $0.id == Self.monthlyID }
            lifetime = products.first { $0.id == Self.lifetimeID }
        }
    }

    /// Læser de gyldige køb fra Apple (lokalt, signeret).
    func refreshEntitlements() async {
        var until: Date?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let t) = result, t.revocationDate == nil else { continue }
            switch t.productID {
            case Self.lifetimeID: until = Self.forever
            case Self.monthlyID:
                if let exp = t.expirationDate, exp > (until ?? .distantPast) { until = exp }
            default: break
            }
        }
        ownUntil = until
    }

    enum Outcome { case success, cancelled, pending, failed(String) }

    func buy(_ product: Product) async -> Outcome {
        do {
            switch try await product.purchase() {
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
