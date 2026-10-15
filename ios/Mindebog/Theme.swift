import SwiftUI

// Farvetema overført fra familie.prehn.net (cream, jordfarvet tekst, accenter).
enum Theme {
    static let bg = Color(red: 0.980, green: 0.973, blue: 0.957)        // #faf8f4
    static let bgDark = Color(red: 0.941, green: 0.929, blue: 0.902)    // #f0ede6
    static let card = Color.white
    static let text = Color(red: 0.173, green: 0.157, blue: 0.125)      // #2c2820
    static let muted = Color(red: 0.541, green: 0.510, blue: 0.470)     // #8a8278
    static let sep = Color(red: 0.910, green: 0.890, blue: 0.859)       // #e8e3db
    static let tint = Color(red: 0.231, green: 0.510, blue: 0.769)      // #3b82c4
    static let rose = Color(red: 0.831, green: 0.329, blue: 0.478)      // #d4547a
    static let green = Color(red: 0.227, green: 0.608, blue: 0.384)     // #3a9b62
    static let neutral = Color(red: 0.659, green: 0.584, blue: 0.447)   // #a89572
    static let neutralDark = Color(red: 0.373, green: 0.322, blue: 0.220) // #5f5238
}

// Lora bruges til overskrifter på websitet; iOS har ikke Lora indbygget.
// Indtil en custom-font tilføjes, bruger vi systemets serif som pendant.
extension Font {
    static func serifTitle(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .serif)
    }
}
