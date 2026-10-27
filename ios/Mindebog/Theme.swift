import SwiftUI
import UIKit

// Farvetema: varm mauve (issue #47, design-lærred 25. okt. 2026).
// Hver farve har en lys og en mørk udgave; iOS vælger selv ud fra udseendet
// (Mere → Udseende: lyst, mørkt eller følg system). Det mørke tema er varmt,
// ikke kulsort, så det stadig føles som papir. Rosa er den eneste accent
// (hjerter, Premium, valgt fane); links følger teksten — ingen blå i paletten.
enum Theme {
    static let bg = dyn(light: 0xf7efe7, dark: 0x3e3239)
    /// Chips, felter, sekundære piller og segment-baggrund.
    static let bgDark = dyn(light: 0xe8d2c4, dark: 0x57474f)
    static let card = dyn(light: 0xfdf8f3, dark: 0x4a3c44)
    static let text = dyn(light: 0x3e3239, dark: 0xf7efe7)
    static let muted = dyn(light: 0x7d6370, dark: 0xc7a9a3)
    static let sep = dyn(light: 0xe8d2c4, dark: 0x6b5560)
    static let tint = dyn(light: 0x6b5560, dark: 0xc7a9a3)
    static let rose = dyn(light: 0xb8536f, dark: 0xe3708f)
    static let green = dyn(light: 0x4f7a5b, dark: 0x8fbf9b)
    static let neutral = dyn(light: 0xc7a9a3, dark: 0x9e8189)
    static let neutralDark = dyn(light: 0x6b5560, dark: 0xe8d2c4)
    /// Primære knapper i indholdet: fulde, mørke piller med lys tekst (omvendt i mørk tilstand).
    static let buttonPrimary = dyn(light: 0x3e3239, dark: 0xf7efe7)
    static let buttonPrimaryText = dyn(light: 0xf7efe7, dark: 0x3e3239)

    /// UIKit-udseende, der ikke kan sættes fra SwiftUI: segmenter (Liste/Kort) i paletten.
    static func applyAppearance() {
        let seg = UISegmentedControl.appearance()
        seg.backgroundColor = UIColor(bgDark)
        seg.selectedSegmentTintColor = UIColor(card)
        seg.setTitleTextAttributes([.foregroundColor: UIColor(text)], for: .selected)
        seg.setTitleTextAttributes([.foregroundColor: UIColor(muted)], for: .normal)
    }

    /// Apples "Fortsæt med Apple"-knap: sort i lyst tema, hvid i mørkt — og teksten modsat.
    static let appleButton = dyn(light: 0x000000, dark: 0xffffff)
    static let appleButtonLabel = dyn(light: 0xffffff, dark: 0x000000)

    /// Farven som UIColor, altid i den lyse udgave — til PDF-bogen, der skal se ens ud uanset tema.
    static func lightUIColor(_ color: Color) -> UIColor {
        UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
    }

    private static func dyn(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { trait in
            UIColor(hex: trait.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xff) / 255,
                  green: CGFloat((hex >> 8) & 0xff) / 255,
                  blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }
}

/// Udseende: følg systemet, altid lyst eller altid mørkt. Gemmes lokalt på telefonen.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    static let key = "mindebog.appearance"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: "Følg system"
        case .light: "Lyst"
        case .dark: "Mørkt"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

// Lora — samme serif som på hjemmesiden (SIL Open Font License, ligger i Fonts/).
// Vægte: regular, medium (overskrifter), semibold (tal) og kursiv (citater).
extension Font {
    static func serifTitle(_ size: CGFloat) -> Font { .custom("Lora-Medium", size: size) }
    static func serif(_ size: CGFloat) -> Font { .custom("Lora-Regular", size: size) }
    static func serifBold(_ size: CGFloat) -> Font { .custom("Lora-SemiBold", size: size) }
    static func serifItalic(_ size: CGFloat) -> Font { .custom("Lora-Italic", size: size) }
}

// Én skala for afrundinger, så kort, felter og knapper ser ens ud over hele appen.
enum Radius {
    /// Små ting: tags, tekstfelter, små billeder i rækker.
    static let small: CGFloat = 8
    /// Kort, knapper og billeder i kort.
    static let card: CGFloat = 14
    /// Store flader: fuldskærmskort, ark, forsidebilleder.
    static let large: CGFloat = 20
}

/// Primær knap i indholdet: fuld, mørk pille (Theme.buttonPrimary) — ikke glas, det er kun til det, der svæver.
struct PrimaryPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.buttonPrimaryText)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 22).padding(.vertical, 13)
            .background(Capsule().fill(Theme.buttonPrimary))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// Sekundær knap/chip i indholdet: lys pille (Theme.bgDark) med almindelig tekst.
struct SecondaryPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 18).padding(.vertical, 11)
            .background(Capsule().fill(Theme.bgDark))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

extension ButtonStyle where Self == PrimaryPillButtonStyle {
    static var primaryPill: PrimaryPillButtonStyle { PrimaryPillButtonStyle() }
}
extension ButtonStyle where Self == SecondaryPillButtonStyle {
    static var secondaryPill: SecondaryPillButtonStyle { SecondaryPillButtonStyle() }
}

extension View {
    /// Lister og formularer i appens farver i stedet for iOS' egne (som bliver kulsorte i mørkt tema).
    /// Rækkerne får Theme.card via `.listRowBackground` på indholdet.
    func themedList() -> some View {
        scrollContentBackground(.hidden).background(Theme.bg.ignoresSafeArea())
    }
}
