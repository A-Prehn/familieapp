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
    /// Sidste gang man selv skiftede (swipe eller prik) — så kører automatikken ikke lige oven i.
    @State private var lastTouch = Date.distantPast
    @State private var forward = true
    private let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    private func show(_ i: Int, forward: Bool) {
        self.forward = forward
        lastTouch = Date()
        withAnimation(.easeInOut(duration: 0.3)) { index = (i + slides.count) % slides.count }
    }

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
                .transition(.asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                                        removal: .opacity))
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
                        .onTapGesture { show(i, forward: i > index) }
                }
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .clipped()
        .noTabSwipe()   // et swipe her bladrer i forsiden, ikke mellem fanerne
        // Swipe til venstre = næste, til højre = forrige (prikkerne antyder det, #25).
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    if value.translation.width < 0 { show(index + 1, forward: true) } else { show(index - 1, forward: false) }
                }
        )
        .onReceive(timer) { _ in
            // Automatisk skift, medmindre man lige har bladret selv.
            guard Date().timeIntervalSince(lastTouch) > 8 else { return }
            forward = true
            withAnimation(.easeInOut(duration: 0.3)) { index = (index + 1) % slides.count }
        }
    }
}
