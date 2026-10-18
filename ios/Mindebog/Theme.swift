import SwiftUI
import UIKit

// Farvetema overført fra familie.prehn.net (cream, jordfarvet tekst, accenter).
// Hver farve har en lys og en mørk udgave; iOS vælger selv ud fra udseendet
// (Mere → Udseende: lyst, mørkt eller følg system). Det mørke tema er varmt,
// ikke kulsort, så det stadig føles som papir.
enum Theme {
    static let bg = dyn(light: 0xfaf8f4, dark: 0x1b1814)
    static let bgDark = dyn(light: 0xf0ede6, dark: 0x262219)
    static let card = dyn(light: 0xffffff, dark: 0x2a2620)
    static let text = dyn(light: 0x2c2820, dark: 0xeee8dd)
    static let muted = dyn(light: 0x8a8278, dark: 0xa59d90)
    static let sep = dyn(light: 0xe8e3db, dark: 0x3b352d)
    static let tint = dyn(light: 0x3b82c4, dark: 0x6aa6e6)
    static let rose = dyn(light: 0xd4547a, dark: 0xe3708f)
    static let green = dyn(light: 0x3a9b62, dark: 0x5fbf86)
    static let neutral = dyn(light: 0xa89572, dark: 0xb9a784)
    static let neutralDark = dyn(light: 0x5f5238, dark: 0xd9c9a7)

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

// Lora bruges til overskrifter på websitet; iOS har ikke Lora indbygget.
// Indtil en custom-font tilføjes, bruger vi systemets serif som pendant.
extension Font {
    static func serifTitle(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .serif)
    }
}
