import SwiftUI
import StoreKit

/// Hvorfor paywallen vises — bruges til overskriften, så den passer til det, man prøvede.
enum PaywallReason: String, Identifiable {
    case general, child, sharing, video, book
    var id: String { rawValue }
    var headline: String {
        switch self {
        case .general: return "Få hele familien med"
        case .child: return "Plads til flere børn"
        case .sharing: return "Del med familien"
        case .video: return "Gem videoerne"
        case .book: return "Lav mindebogen"
        }
    }
    var detail: String {
        switch self {
        case .general: return "Premium låser alt op — for hele familien."
        case .child: return "Gratis-versionen har plads til ét barn. Med Premium kan I føre bog om alle jeres børn."
        case .sharing: return "Invitér partneren, bedsteforældre og resten af familien. De skal ikke selv betale."
        case .video: return "Gem videoer på højdepunkter, i videobreve og i det årlige interview."
        case .book: return "Lav en flot PDF-mindebog med alt indholdet — klar til at printe."
        }
    }
}

/// Betalingsskærm: 19 kr om måneden eller 199 kr for altid.
struct PaywallView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    var reason: PaywallReason = .general

    @ObservedObject private var purchases = Purchases.shared
    @State private var busy = false
    @State private var message: String?

    private static let features: [(String, String)] = [
        ("person.2", "Ubegrænset antal børn"),
        ("person.badge.plus", "Del med partner, bedsteforældre og familie — de betaler ikke selv"),
        ("video", "Video på højdepunkter, videobreve og interview"),
        ("book.closed", "PDF-mindebog, klar til at printe"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "heart.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Theme.rose)
                        Text(reason.headline).font(.serifTitle(28)).foregroundStyle(Theme.text)
                        Text(reason.detail).font(.subheadline).foregroundStyle(Theme.muted)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Self.features, id: \.1) { icon, text in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: icon).frame(width: 22).foregroundStyle(Theme.neutralDark)
                                Text(text).font(.subheadline).foregroundStyle(Theme.text)
                            }
                        }
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "checkmark.shield").frame(width: 22).foregroundStyle(Theme.green)
                            Text("Alt bliver i jeres egen iCloud. Ingen reklamer, og I kan altid eksportere alt — også uden Premium.")
                                .font(.subheadline).foregroundStyle(Theme.muted)
                        }
                    }
                    .padding(16)
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.sep))

                    if purchases.loadingProducts && purchases.lifetime == nil {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    } else if purchases.lifetime == nil && purchases.monthly == nil {
                        Text("Købsmulighederne kunne ikke hentes fra App Store lige nu. Tjek forbindelsen, og prøv igen.")
                            .font(.footnote).foregroundStyle(Theme.rose)
                    } else {
                        VStack(spacing: 10) {
                            if let lifetime = purchases.lifetime {
                                optionButton(title: "For altid", price: lifetime.displayPrice,
                                             note: "Betal én gang. Mest populær.", primary: true) {
                                    Task { await buy(lifetime) }
                                }
                            }
                            if let monthly = purchases.monthly {
                                optionButton(title: "Pr. måned", price: "\(monthly.displayPrice)/md",
                                             note: "Kan opsiges når som helst.", primary: false) {
                                    Task { await buy(monthly) }
                                }
                            }
                        }
                    }

                    if let message {
                        Text(message).font(.footnote).foregroundStyle(Theme.rose)
                    }

                    VStack(spacing: 10) {
                        Button("Gendan køb") { Task { await restore() } }
                            .font(.footnote.weight(.semibold))
                            .disabled(busy)
                        Text("Abonnementet fornyes automatisk hver måned, indtil det opsiges. Opsig under Indstillinger → [dit navn] → Abonnementer senest 24 timer før fornyelse. Betalingen trækkes via din Apple-konto.")
                            .font(.caption2).foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.center)
                        HStack(spacing: 16) {
                            Link("Vilkår (EULA)", destination: AppLinks.terms)
                            Link("Privatlivspolitik", destination: AppLinks.privacy)
                        }
                        .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(24)
            }
            .paperBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Ikke nu") { dismiss() } }
            }
            .overlay { if busy { Color.black.opacity(0.05).ignoresSafeArea(); ProgressView() } }
            .task { await purchases.loadProducts() }
        }
    }

    private func optionButton(title: String, price: String, note: String, primary: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(note).font(.caption).opacity(0.85)
                }
                Spacer()
                Text(price).font(.headline)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 14).fill(primary ? Theme.rose : Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(primary ? Theme.rose : Theme.sep))
            .foregroundStyle(primary ? Color.white : Theme.text)
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    private func buy(_ product: Product) async {
        busy = true
        message = nil
        defer { busy = false }
        switch await purchases.buy(product) {
        case .success:
            await state.refreshPremium()
            dismiss()
        case .pending:
            message = "Købet venter på godkendelse (fx \"Spørg først\" i Familiedeling)."
        case .cancelled:
            break
        case .failed(let error):
            message = "Købet gik ikke igennem: \(error)"
        }
    }

    private func restore() async {
        busy = true
        message = nil
        defer { busy = false }
        if await purchases.restore() {
            await state.refreshPremium()
            dismiss()
        } else {
            await state.refreshPremium()
            if state.isPremium { dismiss() } else { message = "Der blev ikke fundet nogen køb på denne Apple-konto." }
        }
    }
}

enum AppLinks {
    /// Apples standard-licensaftale for apps (gælder, når man ikke har sin egen).
    static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    /// Privatlivspolitikken (public/privacy.html) — skal ligge på en offentlig adresse før App Store.
    static let privacy = URL(string: "https://github.com/A-Prehn/familieapp/blob/develop/public/privacy.html")!
}
