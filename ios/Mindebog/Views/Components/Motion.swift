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

/// Et svagt papirkorn over baggrundsfarven, så fladerne føles som sider i en bog.
struct PaperBackground: View {
    var body: some View {
        ZStack {
            Theme.bg
            Image(uiImage: Self.grain)
                .resizable(resizingMode: .tile)
                .opacity(0.5)
                .blendMode(.multiply)
                .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }

    /// 96×96 px korn, lavet én gang: tilfældige, meget lyse prikker med lav gennemsigtighed.
    private static let grain: UIImage = {
        let size = 96
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        var seed: UInt32 = 0x9E37_79B9
        for i in 0..<(size * size) {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let v = UInt8(seed >> 24)
            // Kun hver tredje prik er synlig, og kun svagt — det skal anes, ikke ses.
            let alpha: UInt8 = v % 3 == 0 ? 10 : 0
            pixels[i * 4] = 60; pixels[i * 4 + 1] = 50; pixels[i * 4 + 2] = 35; pixels[i * 4 + 3] = alpha
        }
        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData),
              let cg = CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
                               space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return UIImage() }
        return UIImage(cgImage: cg, scale: 2, orientation: .up)
    }()
}

extension View {
    func softAppear(index: Int = 0) -> some View { modifier(SoftAppear(index: index)) }
    func breathing(_ active: Bool) -> some View { modifier(Breathing(active: active)) }

    /// Varm, lys skygge under et kort, så det ligger på siden i stedet for at være tegnet på den.
    func warmShadow() -> some View {
        shadow(color: Theme.neutralDark.opacity(0.07), radius: 10, y: 4)
    }

    /// Papir som baggrund på en skærm (erstatter `.paperBackground()`).
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
                    .overlay { ShimmerPlaceholder(height: 400, cornerRadius: 12) }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(16)
    }
}
