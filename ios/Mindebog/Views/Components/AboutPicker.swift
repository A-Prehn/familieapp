import SwiftUI

// "Handler om": vælg børn og voksne i familien (ejer, medejer og dem med kiggeadgang).
// Bruges på minder, begivenheder og rejser. Ingen valgt = hele familien.
struct AboutPicker: View {
    let children: [Child]
    let members: [AppUser]
    @Binding var childIds: [String]
    @Binding var personIds: [String]

    var body: some View {
        if !children.isEmpty || !members.isEmpty {
            Section {
                ForEach(children) { child in
                    Button { toggle(child.id, in: $childIds) } label: {
                        row(name: child.name, selected: childIds.contains(child.id)) {
                            ChildAvatar(child: child, size: 28)
                        }
                    }
                }
                ForEach(members) { member in
                    Button { toggle(member.id, in: $personIds) } label: {
                        row(name: member.name, selected: personIds.contains(member.id)) {
                            Circle().fill(Theme.bgDark)
                                .frame(width: 28, height: 28)
                                .overlay(Text(Self.initials(member.name)).font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Theme.neutralDark))
                        }
                    }
                }
            } header: {
                Text("Handler om (valgfrit)")
            } footer: {
                Text("Vælg ingen, hvis det gælder hele familien.")
            }
        }
    }

    private func row<Avatar: View>(name: String, selected: Bool, @ViewBuilder avatar: () -> Avatar) -> some View {
        HStack {
            avatar()
            Text(name).foregroundStyle(Theme.text)
            Spacer()
            if selected { Image(systemName: "checkmark").foregroundStyle(Theme.tint) }
        }
    }

    private func toggle(_ id: String, in list: Binding<[String]>) {
        if let i = list.wrappedValue.firstIndex(of: id) { list.wrappedValue.remove(at: i) }
        else { list.wrappedValue.append(id) }
    }

    static func initials(_ name: String) -> String {
        let letters = name.split(separator: " ").compactMap(\.first).filter(\.isLetter).prefix(2).map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    /// "Nohr, Sheila" — navnene på dem, noget handler om.
    static func names(childIds: [String], personIds: [String], children: [Child], members: [AppUser]) -> String {
        let kids = childIds.compactMap { id in children.first { $0.id == id }?.name }
        let adults = personIds.compactMap { id in members.first { $0.id == id }?.name }
        return (kids + adults).joined(separator: ", ")
    }
}
