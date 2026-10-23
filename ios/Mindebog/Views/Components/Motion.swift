import SwiftUI
import UIKit

// Rolige effekter, der passer til en mindebog: blid indtoning, papir, varme skygger og
// små bekræftelser i hånden. Alt respekterer "Reducér bevægelse" i iOS.

// MARK: - Haptik

enum Haptics {
    /// Noget blev gemt eller lykkedes.
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    /// Et lille tryk, fx når scanneren fanger en side, eller afspilleren skifter svar.
    static func light() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
}

// MARK: - Blid indtoning

/// Toner ind og glider få millimeter op, når noget vises — kort, billeder, sektioner.
/// `index` forsinker hvert næste element en anelse, så en liste "lægger sig" på siden.
private struct SoftAppear: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let index: Int
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 6)
            .onAppear {
                guard !shown else { return }
                withAnimation(.easeOut(duration: 0.35).delay(min(Double(index) * 0.04, 0.3))) { shown = true }
            }
    }
}

// MARK: - Vejrtrækning (barn på vej)

/// En langsom, rolig puls — som en vejrtrækning. Bruges på hjertet på Hjem, mens et barn er på vej.
private struct Breathing: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let active: Bool
    @State private var inhale = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(active && inhale && !reduceMotion ? 1.06 : 1)
            .opacity(active && inhale && !reduceMotion ? 1 : 0.92)
            .onAppear {
                guard active, !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { inhale = true }
            }
    }
}

// MARK: - Papir

/// Baggrunden på en skærm. (Et papirkorn blev prøvet og droppet igen: det gjorde fladerne gullige.)
struct PaperBackground: View {
    var body: some View {
        Theme.bg.ignoresSafeArea()
    }
}

extension View {
    func softAppear(index: Int = 0) -> some View { modifier(SoftAppear(index: index)) }
    func breathing(_ active: Bool) -> some View { modifier(Breathing(active: active)) }

    /// Let, neutral skygge under et kort, så det ligger på siden. Så svag, at den kun anes
    /// (en varm brun skygge gav kortene en gullig kant på den cremefarvede baggrund).
    func warmShadow() -> some View {
        shadow(color: .black.opacity(0.035), radius: 8, y: 3)
    }

    /// Papir som baggrund på en skærm (erstatter `.background(Theme.bg.ignoresSafeArea())`).
    func paperBackground() -> some View { background(PaperBackground()) }
}

// MARK: - Zoom til fuld skærm (iOS 18)

/// Billedet "løfter sig" fra sin plads i listen ud til fuld skærm og tilbage igen.
/// Kræver iOS 18; på iOS 17 vises fuld skærm som før.
extension View {
    @ViewBuilder
    func zoomSource(id: String, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    @ViewBuilder
    func zoomTarget(id: String?, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *), let id {
            navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
    }
}

// MARK: - Skimmer (mens iCloud henter)

/// En blød pladsholder med et lyst skær, der glider hen over — i stedet for en tom skærm.
struct ShimmerPlaceholder: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var height: CGFloat = 120
    var cornerRadius: CGFloat = 14
    @State private var phase: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Theme.bgDark)
            .overlay {
                if !reduceMotion {
                    GeometryReader { geo in
                        LinearGradient(colors: [.clear, Theme.card.opacity(0.7), .clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: geo.size.width * 0.6)
                            .offset(x: phase * geo.size.width)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                }
            }
            .frame(height: height)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { phase = 1.2 }
            }
            .accessibilityHidden(true)
    }
}

/// Tre pladsholdere under hinanden, som en liste.
struct ShimmerList: View {
    var count = 3
    var height: CGFloat = 120
    var body: some View {
        VStack(spacing: 12) {
            ForEach(0..<count, id: \.self) { _ in ShimmerPlaceholder(height: height) }
        }
        .padding(16)
    }
}

/// Et gitter af kvadratiske pladsholdere, som en billedserie.
struct ShimmerGrid: View {
    var columns = 2
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columns), spacing: 10) {
            ForEach(0..<(columns * 3), id: \.self) { _ in
                Color.clear.aspectRatio(1, contentMode: .fit)
                    .overlay { ShimmerPlaceholder(height: 400, cornerRadius: Radius.card) }
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card))
            }
        }
        .padding(16)
    }
}

// MARK: - Kort, der kan trykkes på (#46)

/// Kortet giver en anelse efter i hånden (skala 0.98), mens man trykker. Slået fra ved "Reducér bevægelse".
struct PressableCard: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressableBody(configuration: configuration)
    }

    private struct PressableBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
                .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
        }
    }
}

extension View {
    /// Gør et kort til en knap med PressableCard-tryk (tryk = redigér).
    func pressableCard(_ action: @escaping () -> Void) -> some View {
        Button(action: action) { self }.buttonStyle(PressableCard())
    }
}
