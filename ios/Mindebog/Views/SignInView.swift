import SwiftUI

struct SignInView: View {
    @EnvironmentObject var state: AppState
    @State private var name = ""

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "book.closed")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(Theme.neutralDark)
            Text("Vores familie")
                .font(.serifTitle(34))
                .foregroundStyle(Theme.text)
            Text("Saml milepæle, billeder og øjeblikke for jeres børn — og del dem med den I har dem sammen med.")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            VStack(spacing: 12) {
                TextField("Dit navn (prototype — erstattes af Apple-ID)", text: $name)
                    .textFieldStyle(.roundedBorder)

                Button {
                    Task { await state.signIn(name: name) }
                } label: {
                    Label("Fortsæt med Apple", systemImage: "apple.logo")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(.black)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .paperBackground()
    }
}
