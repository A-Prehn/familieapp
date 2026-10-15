import SwiftUI

// Lodret tidslinje som på websitet (ferier/højdepunkter), tilpasset telefonbredde:
// linjen løber i venstre side, en prik pr. punkt og et årstal-mærke hver gang året skifter.
struct TimelineView<Item: Identifiable, Card: View>: View {
    let items: [Item]
    let year: (Item) -> Int?
    @ViewBuilder let card: (Item) -> Card

    private let rail: CGFloat = 28          // bredde på linje-kolonnen
    private let dotSize: CGFloat = 11

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if let y = year(item), index == 0 || year(items[index - 1]) != y {
                    yearBadge(y)
                }
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .strokeBorder(Theme.neutral, lineWidth: 2)
                        .background(Circle().fill(Theme.bg))
                        .frame(width: dotSize, height: dotSize)
                        .frame(width: rail)
                        .padding(.top, 22)
                    card(item)
                }
            }
        }
        .background(alignment: .topLeading) {
            // Selve linjen bag prikkerne.
            Rectangle()
                .fill(Theme.sep)
                .frame(width: 1.5)
                .padding(.leading, rail / 2 - 0.75)
                .padding(.vertical, 6)
        }
    }

    private func yearBadge(_ year: Int) -> some View {
        Text(String(year))
            .font(.system(size: 12, design: .serif))
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Capsule().fill(Theme.bg))
            .overlay(Capsule().stroke(Theme.sep))
            .padding(.top, 4)
    }
}
