import SwiftUI
import Combine

struct HeroView: View {
    private let slides: [(tagline: String, symbol: String)] = [
        ("Et sted til minder, milepæle og øjeblikke", "book.closed"),
        ("Jeres historie — samlet ét sted", "house"),
        ("Se dem vokse — måned for måned", "leaf"),
        ("Gem øjeblikkene — del dem sammen", "camera")
    ]
    @State private var index = 0
    private let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 10) {
            Text("VORES FAMILIE")
                .font(.caption2).tracking(1.6)
                .foregroundStyle(Theme.muted)
            Text(slides[index].tagline)
                .font(.serifTitle(19))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                // Fuld bredde og en ny visning pr. slide: den gamle toner ud og den nye ind, i stedet
                // for at SwiftUI prøver at glide mellem to tekster af forskellig længde (gav skæv tekst).
                .frame(maxWidth: .infinity, minHeight: 50)
                .id(index)
                .transition(.opacity)
            Image(systemName: slides[index].symbol)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.neutralDark)
                .frame(height: 60)
                .id(index)
                .transition(.opacity)
            HStack(spacing: 8) {
                ForEach(slides.indices, id: \.self) { i in
                    Circle()
                        .fill(i == index ? Theme.neutral : Theme.sep)
                        .frame(width: 8, height: 8)
                        .onTapGesture { index = i }
                }
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .onReceive(timer) { _ in
            withAnimation { index = (index + 1) % slides.count }
        }
    }
}
