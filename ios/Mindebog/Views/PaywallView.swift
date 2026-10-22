import SwiftUI
import StoreKit

/// Hvorfor paywallen vises — bruges til overskriften, så den passer til det, man prøvede.
enum PaywallReason: String, Identifiable {
    case general, child, sharing, video, book, movie, family
    var id: String { rawValue }
    var headline: String {
        switch self {
        case .general: return "Få hele familien med"
        case .child: return "Plads til flere børn"
        case .sharing: return "Del med familien"
        case .video: return "Gem videoerne"
        case .book: return "Lav mindebogen"
        case .movie: return "Lav filmen"
        case .family: return "Flere familier"
        }
    }
    var detail: String {
        switch self {
        case .general: return "Premium låser alt op — for hele familien."
        case .child: return "Gratis-versionen har plads til to børn. Med Premium kan I føre bog om alle jeres børn."
        case .sharing: return "Din partner er gratis. Med Premium kan I også invitere bedsteforældre, resten af familien og en forælder uden for familien. De skal ikke selv betale."
        case .video: return "Gem videoer på højdepunkter, i videobreve og i det årlige interview."
        case .book: return "Lav en flot PDF-mindebog med alt indholdet — klar til at printe."
        case .movie: return "Lav en film af billedserien med bløde overgange — klar til at dele med familien."
        case .family: return "Med Premium kan du oprette flere familier — fx en til hver gren af familien — og skifte mellem dem."
        }
    }
}

/// Betalingsskærm: 179 kr om året (fremhævet), 19 kr om måneden eller 499 kr for altid.
struct PaywallView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    var reason: PaywallReason = .general

    @ObservedObject private var purchases = Purchases.shared
    @State private var busy = false
    @State private var message: String?

    private static let features: [(String, String)] = [
        ("person.2", "Ubegrænset antal børn"),
        ("person.badge.plus", "Del med bedsteforældre, familie og en forælder uden for familien — de betaler ikke selv"),
        ("video", "Video på højdepunkter, videobreve og interview"),
        ("book.closed", "PDF-mindebog, klar til at printe"),
        ("film", "Film af billedserierne — måned for måned og maven"),
        ("rectangle.stack.badge.plus", "Flere familier — og skift mellem dem"),
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
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Købsmulighederne kunne ikke hentes fra App Store lige nu. Tjek forbindelsen, og prøv igen.")
                                .font(.footnote).foregroundStyle(Theme.rose)
                            Button { Task { await purchases.loadProducts() } } label: {
                                Label("Prøv igen", systemImage: "arrow.clockwise")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                                    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.sep))
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        // Året er det fremhævede valg; måneden nedenunder; engangskøbet nederst og dæmpet.
                        VStack(spacing: 10) {
                            if let yearly = purchases.yearly {
                                optionButton(title: "Pr. år", price: "\(yearly.displayPrice)/år",
                                             note: Self.yearlyNote(yearly: yearly, monthly: purchases.monthly), primary: true) {
                                    Task { await buy(yearly) }
                                }
                            }
                            if let monthly = purchases.monthly {
                                optionButton(title: "Pr. måned", price: "\(monthly.displayPrice)/md",
                                             note: "Kan opsiges når som helst.", primary: purchases.yearly == nil) {
                                    Task { await buy(monthly) }
                                }
                            }
                            if let lifetime = purchases.lifetime {
                                optionButton(title: "For altid", price: lifetime.displayPrice,
                                             note: "Betal én gang, aldrig mere.", primary: false, subtle: true) {
                                    Task { await buy(lifetime) }
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
                        Text("Abonnementer fornyes automatisk hver måned eller hvert år, indtil de opsiges. Opsig under Indstillinger → [dit navn] → Abonnementer senest 24 timer før fornyelse. Betalingen trækkes via din Apple-konto.")
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
            .background(Theme.bg.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Ikke nu") { dismiss() } }
            }
            .overlay { if busy { Color.black.opacity(0.05).ignoresSafeArea(); ProgressView() } }
            .task { await purchases.loadProducts() }
        }
    }

    /// "Svarer til 15 kr./md · spar 21 %" — regnet ud fra de rigtige priser, så den passer i alle lande.
    private static func yearlyNote(yearly: Product, monthly: Product?) -> String {
        let perMonth = yearly.price / 12
        var text = "Svarer til \(yearly.priceFormatStyle.format(perMonth))/md."
        if let monthly, monthly.price > 0 {
            let saving = Int(((1 - perMonth / monthly.price) * 100).rounded())
            if saving > 0 { text += " Spar \(saving) %." }
        }
        return text
    }

    private func optionButton(title: String, price: String, note: String, primary: Bool, subtle: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(subtle ? .subheadline.weight(.semibold) : .headline)
                    Text(note).font(.caption).opacity(0.85)
                }
                Spacer()
                Text(price).font(subtle ? .subheadline.weight(.semibold) : .headline)
            }
            .padding(subtle ? 12 : 16)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 14).fill(primary ? Theme.rose : (subtle ? Theme.bg : Theme.card)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(primary ? Theme.rose : Theme.sep))
            .foregroundStyle(primary ? Color.white : (subtle ? Theme.muted : Theme.text))
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
    /// Privatlivspolitikken — offentlig side på apps.prehn.net (samme adresse står i App Store Connect).
    static let privacy = URL(string: "https://apps.prehn.net/vores-familie/privatliv/")!
}
