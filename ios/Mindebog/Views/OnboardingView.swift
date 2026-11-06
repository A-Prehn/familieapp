import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var state: AppState
    @State private var mode = 0   // 0 = opret, 1 = deltag
    @State private var name = ""
    @State private var code = ""
    @State private var hasChildren = true

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
                        .submitLabel(.go)
                        .onSubmit { Task { await state.createFamily(name: name, hasChildren: hasChildren) } }
                    // Familier uden børn (#28) får ingen Børn-fane; kan ændres under Mere.
                    Toggle("Vi har børn (eller et på vej)", isOn: $hasChildren)
                        .font(.subheadline)
                        .tint(Theme.rose)
                    // Viser, at iCloud arbejder, og tager ikke imod flere tryk imens (#59).
                    Button {
                        Task { await state.createFamily(name: name, hasChildren: hasChildren) }
                    } label: {
                        HStack(spacing: 8) {
                            if state.joiningFamily { ProgressView().tint(Theme.buttonPrimaryText) }
                            Text(state.joiningFamily ? "Opretter familien…" : "Opret familie")
                        }
                    }
                    .buttonStyle(.primaryPill)
                    .frame(maxWidth: .infinity)
                    .disabled(state.joiningFamily)
                }
                .padding(.horizontal, 24)
            } else {
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        TextField(state.usingCloud ? "Indsæt delelink" : "Invitationskode", text: $code)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(state.usingCloud ? .never : .characters)
                            .autocorrectionDisabled()
                        // Indsæt med ét tryk (#67) — iOS spørger ikke om lov, når man selv trykker.
                        PasteButton(payloadType: String.self) { strings in
                            if let text = strings.first { code = text.trimmingCharacters(in: .whitespacesAndNewlines) }
                        }
                        .labelStyle(.iconOnly)
                        .buttonBorderShape(.capsule)
                        .tint(Theme.rose)
                    }
                    if state.usingCloud {
                        Text("Har du fået en invitation? Gå tilbage til beskeden, og tryk på linket igen — så åbner appen og tilmelder dig af sig selv. Du kan også kopiere linket og indsætte det her.")
                            .font(.footnote).foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.center)
                    }
                    Button {
                        Task { await state.acceptInvite(code: code) }
                    } label: {
                        HStack(spacing: 8) {
                            if state.joiningFamily { ProgressView().tint(Theme.buttonPrimaryText) }
                            Text(state.joiningFamily ? "Åbner invitationen…" : "Deltag i familie")
                        }
                    }
                    .buttonStyle(.primaryPill)
                    .frame(maxWidth: .infinity)
                    .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty || state.joiningFamily)
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
        .background(Theme.bg.ignoresSafeArea())
    }
}
