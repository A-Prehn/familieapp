import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var state: AppState
    @State private var mode = 0   // 0 = opret, 1 = deltag
    @State private var name = ""
    @State private var code = ""

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "person.3")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(Theme.neutralDark)
            Text("Din familie")
                .font(.serifTitle(30))
            Text("Opret en ny familie, eller deltag i en der allerede er delt med dig.")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Picker("", selection: $mode) {
                Text("Opret ny").tag(0)
                Text("Deltag").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)

            if mode == 0 {
                VStack(spacing: 12) {
                    TextField("Familiens navn", text: $name)
                        .textFieldStyle(.roundedBorder)
                    Button("Opret familie") {
                        Task { await state.createFamily(name: name) }
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 24)
            } else {
                VStack(spacing: 12) {
                    TextField(state.usingCloud ? "Indsæt delelink" : "Invitationskode", text: $code)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(state.usingCloud ? .never : .characters)
                        .autocorrectionDisabled()
                    if state.usingCloud {
                        Text("Har du fået et link fra din partner? Tryk på det, eller indsæt det her.")
                            .font(.footnote).foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.center)
                    }
                    Button("Deltag i familie") {
                        Task { await state.acceptInvite(code: code) }
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal, 24)
            }

            if let err = state.errorMessage {
                Text(err).font(.footnote).foregroundStyle(Theme.rose)
            }
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .paperBackground()
    }
}
