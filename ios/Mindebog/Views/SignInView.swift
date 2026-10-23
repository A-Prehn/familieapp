import SwiftUI
import UIKit

// Startskærmen, første gang appen åbnes. Der er ikke noget login: appen bruger den iCloud-konto,
// telefonen allerede er logget på, og alt gemmes der. Uden iCloud kan man prøve appen, men intet gemmes.
struct SignInView: View {
    @EnvironmentObject var state: AppState
    @State private var name = ""
    @State private var working = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Spacer(minLength: 40)
                Image(systemName: "book.closed")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(Theme.neutralDark)
                Text("Vores familie")
                    .font(.serifTitle(34))
                    .foregroundStyle(Theme.text)
                Text("Saml milepæle, billeder og øjeblikke for jeres børn — og del dem med den, I har dem sammen med.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                VStack(spacing: 12) {
                    TextField("Dit navn (fx Andreas)", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.givenName)
                        .submitLabel(.go)
                        .onSubmit { start() }

                    Button(action: start) {
                        HStack {
                            if working { ProgressView().tint(Theme.appleButtonLabel) }
                            Text(state.usingCloud ? "Kom i gang" : "Prøv appen uden iCloud")
                        }
                        .foregroundStyle(Theme.appleButtonLabel)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.appleButton)
                    .disabled(working)

                    if let err = state.errorMessage {
                        Text(err).font(.footnote).foregroundStyle(Theme.rose).multilineTextAlignment(.center)
                    }

                    if state.usingCloud {
                        Text("Der er ikke noget login. Alt gemmes i din egen iCloud, som denne enhed allerede er logget på — ingen konto, ingen adgangskode.")
                            .font(.caption).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                    } else {
                        VStack(spacing: 10) {
                            Label("iCloud er ikke slået til på denne enhed", systemImage: "icloud.slash")
                                .font(.footnote.weight(.semibold)).foregroundStyle(Theme.text)
                            Text("Vores familie gemmer alt i din egen iCloud. Log ind på iCloud under Indstillinger → dit navn, og åbn appen igen. Uden iCloud kan du prøve appen, men intet gemmes, når den lukkes.")
                                .font(.caption).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                            Button("Åbn Indstillinger") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                            }
                            .font(.footnote.weight(.semibold))
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity)
                        .background(Theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Theme.sep))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                Spacer(minLength: 40)
            }
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.bg.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
    }

    private func start() {
        guard !working else { return }
        working = true
        state.errorMessage = nil
        Task {
            await state.signIn(name: name)
            working = false
        }
    }
}
