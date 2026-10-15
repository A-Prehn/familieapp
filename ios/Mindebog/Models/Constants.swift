import Foundation

// Faste data overført fra familie.prehn.net. Generiske — intet familiespecifikt.

/// Hvilken slags værdi en milepæl har — styrer feltet i redigér-boksen og visningen.
/// Værdien gemmes altid som tekst: dato "yyyy-MM-dd", tid "HH:mm", vægt i gram, længde i cm.
enum MilestoneKind: Hashable {
    case date
    case time
    case weight          // gram
    case length          // cm
    case choice([String])
    case text
}

struct MilestoneDef: Identifiable, Hashable {
    let key: String
    let label: String
    let icon: String        // emoji, som på websitet
    let kind: MilestoneKind
    var id: String { key }
    var isDate: Bool { kind == .date }

    init(key: String, label: String, icon: String, isDate: Bool) {
        self.init(key: key, label: label, icon: icon, kind: isDate ? .date : .text)
    }

    init(key: String, label: String, icon: String, kind: MilestoneKind) {
        self.key = key; self.label = label; self.icon = icon; self.kind = kind
    }
}

enum Constants {
    static let milestones: [MilestoneDef] = [
        MilestoneDef(key: "due_date", label: "Terminsdato", icon: "📅", isDate: true),
        MilestoneDef(key: "birth_date", label: "Fødselsdag", icon: "🌱", isDate: true),
        MilestoneDef(key: "birth_time", label: "Tidspunkt", icon: "⏰", kind: .time),
        MilestoneDef(key: "birth_weight", label: "Fødselsvægt", icon: "⚖️", kind: .weight),
        MilestoneDef(key: "birth_length", label: "Fødselslængde", icon: "📏", kind: .length),
        MilestoneDef(key: "eye_color", label: "Øjenfarve", icon: "👁️",
                     kind: .choice(["Blå", "Grå", "Grøn", "Hassel", "Brun", "Mørkebrun", "Skifter stadig"])),
        MilestoneDef(key: "hair_color", label: "Hårfarve", icon: "✨",
                     kind: .choice(["Intet hår endnu", "Lyst", "Mellemblond", "Lysebrunt", "Brunt", "Mørkt", "Sort", "Rødt"])),
        MilestoneDef(key: "first_car_ride", label: "Første biltur hjem", icon: "🚗", isDate: true),
        MilestoneDef(key: "first_doctor", label: "Første lægebesøg", icon: "🩺", isDate: true),
        MilestoneDef(key: "first_vaccine", label: "Første vaccination", icon: "💉", isDate: true),
        MilestoneDef(key: "meets_grandparents", label: "Møder bedsteforældre", icon: "👨‍👩‍👧", isDate: true),
        MilestoneDef(key: "meets_pets", label: "Møder familiens dyr", icon: "🐶", isDate: true),
        MilestoneDef(key: "recognizes_parents", label: "Genkender forældre", icon: "👀", isDate: true),
        MilestoneDef(key: "first_smile", label: "Første smil", icon: "😊", isDate: true),
        MilestoneDef(key: "first_laugh", label: "Første grin", icon: "😄", isDate: true),
        MilestoneDef(key: "sleeps_through", label: "Sover igennem", icon: "🌙", isDate: true),
        MilestoneDef(key: "turns_over", label: "Vender sig selv", icon: "🤸", isDate: true),
        MilestoneDef(key: "first_sick", label: "Første sygdom", icon: "🤒", isDate: true),
        MilestoneDef(key: "sits_alone", label: "Sidder selv", icon: "🪑", isDate: true),
        MilestoneDef(key: "first_food", label: "Første mad", icon: "🥄", isDate: true),
        MilestoneDef(key: "eats_spoon", label: "Spiser med ske", icon: "🥄", isDate: true),
        MilestoneDef(key: "first_tooth", label: "Første tand", icon: "🦷", isDate: true),
        MilestoneDef(key: "crawls", label: "Kravler", icon: "🧎", isDate: true),
        MilestoneDef(key: "drinks_cup", label: "Drikker fra kop", icon: "🥤", isDate: true),
        MilestoneDef(key: "claps", label: "Klapper i hænderne", icon: "👏", isDate: true),
        MilestoneDef(key: "waves", label: "Vinker farvel", icon: "👋", isDate: true),
        MilestoneDef(key: "stands_support", label: "Står med støtte", icon: "🧍", isDate: true),
        MilestoneDef(key: "says_mom_dad", label: "Siger mor/far", icon: "📣", isDate: true),
        MilestoneDef(key: "first_word", label: "Første ord", icon: "💬", isDate: false),
        MilestoneDef(key: "first_steps", label: "Første skridt", icon: "👣", isDate: true),
        MilestoneDef(key: "walks", label: "Går selv", icon: "🚶", isDate: true),
        MilestoneDef(key: "nursing_ended", label: "Amning/flaske slut", icon: "🍼", isDate: true),
        MilestoneDef(key: "sleep_position", label: "Yndlingssovestilling", icon: "😴", isDate: false),
        MilestoneDef(key: "fav_toy", label: "Yndlingsbamse", icon: "🧸", isDate: false),
        MilestoneDef(key: "fav_song", label: "Yndlingssang", icon: "🎵", isDate: false),
        MilestoneDef(key: "first_christmas", label: "Første jul", icon: "🎄", isDate: true),
        MilestoneDef(key: "first_flight", label: "Første flyvetur", icon: "✈️", isDate: true),
        MilestoneDef(key: "first_beach", label: "Første strand", icon: "🏖️", isDate: true),
        MilestoneDef(key: "first_swim", label: "Første bad i hav/pool", icon: "🏊", isDate: true),
        MilestoneDef(key: "first_baptism", label: "Navnedag/dåb", icon: "👶", isDate: true),
        MilestoneDef(key: "first_birthday", label: "Første fødselsdag", icon: "🎂", isDate: true)
    ]

    struct AboutSection: Identifiable {
        let title: String
        let questions: [String]
        var id: String { title }
    }

    static let aboutMe: [AboutSection] = [
        AboutSection(title: "Om graviditeten", questions: [
            "Hvornår fandt vi ud af at du var på vej?",
            "Hvad var vores første reaktion?",
            "Hvad håbede vi at du ville blive?",
            "Hvad kaldte vi dig mens du var i maven?"]),
        AboutSection(title: "Din personlighed", questions: [
            "Hvad får dig til at grine?",
            "Hvad er du allermest nysgerrig på?",
            "Er du mest genert eller frembrusende?",
            "Hvad er du stolt af?",
            "Hvad er du bange for?",
            "Hvad trøster dig når du er ked af det?",
            "Hvad gør du når du er træt?",
            "Er du et morgenmenneske eller en natteravn?"]),
        AboutSection(title: "Dine favoritter", questions: [
            "Hvad er din yndlingsfarve?",
            "Hvad er din yndlingsmad?",
            "Hvad er dit yndlingsdyr?",
            "Hvad er dit yndlingsstuffe / bamse?",
            "Hvad er din yndlingsfilm / -serie?",
            "Hvad er dit yndlingsord?",
            "Hvad er din yndlingsleg udenfor?"]),
        AboutSection(title: "Dine vaner og rutiner", questions: [
            "Hvordan vil du helst falde i søvn?",
            "Hvad kan du ikke sove uden?",
            "Hvad er det første du gør om morgenen?",
            "Hvad siger du altid inden du sover?",
            "Hvad er din bedste undskyldning for ikke at ville sove?"]),
        AboutSection(title: "Dit forhold til os", questions: [
            "Hvad kalder du os?",
            "Hvad gør du når du vil have opmærksomhed?",
            "Hvad er dit yndlingskram?",
            "Hvad siger du når du er glad for os?",
            "Hvad gør vi der irriterer dig allermest?",
            "Hvad gør vi der gør dig allermest glad?"]),
        AboutSection(title: "Dit forhold til verden", questions: [
            "Hvad vil du gerne være når du bliver stor?",
            "Hvad tror du der bor under sengen?",
            "Hvad mener du er uretfærdigt?",
            "Hvad synes du er det bedste ved at være barn?",
            "Hvad er det sværeste?",
            "Hvad ville du gøre hvis du bestemte alting?"]),
        AboutSection(title: "Sjove citater", questions: [
            "Hvad er det morsomste du har sagt?",
            "Hvad har du gjort som vi aldrig glemmer?",
            "Hvad har du sagt der overraskede os?",
            "Hvad har du forklaret os på din helt egen måde?"])
    ]
}

// Visning/parsing af milepæls-værdier. Tåler ældre fritekst ("3450 g", "3,4 kg", "52cm", "14.32").
enum MilestoneValue {
    static func display(_ value: String, kind: MilestoneKind) -> String {
        switch kind {
        case .date:
            return Fmt.parseIso(value).map(Fmt.long) ?? value
        case .time:
            return parseTime(value).map { String(format: "kl. %02d:%02d", $0.hour, $0.minute) } ?? value
        case .weight:
            guard let grams = grams(value) else { return value }
            let f = NumberFormatter()
            f.locale = Locale(identifier: "da_DK"); f.numberStyle = .decimal
            return "\(f.string(from: NSNumber(value: grams)) ?? String(grams)) g"
        case .length:
            guard let cm = centimeters(value) else { return value }
            return cm.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(cm)) cm"
                : String(format: "%.1f cm", cm).replacingOccurrences(of: ".", with: ",")
        case .choice, .text:
            return value
        }
    }

    /// "14:32", "14.32", "kl. 14:32" → (14, 32)
    static func parseTime(_ value: String) -> (hour: Int, minute: Int)? {
        let digits = value.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard digits.count >= 2, (0..<24).contains(digits[0]), (0..<60).contains(digits[1]) else { return nil }
        return (digits[0], digits[1])
    }

    /// "3450", "3450 g", "3.450 g", "3,4 kg" → 3450
    static func grams(_ value: String) -> Int? {
        let lower = value.lowercased()
        if lower.contains("kg") {
            let n = Double(lower.replacingOccurrences(of: "kg", with: "")
                .replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
            return n.map { Int(($0 * 1000).rounded()) }
        }
        let digits = value.filter(\.isNumber)
        return Int(digits)
    }

    /// "52", "52 cm", "51,5" → 52.0 / 51.5
    static func centimeters(_ value: String) -> Double? {
        let cleaned = value.lowercased().replacingOccurrences(of: "cm", with: "")
            .replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        return Double(cleaned)
    }
}

// Dato-hjælpere (dansk).
enum Fmt {
    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let longFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "da_DK")
        f.dateStyle = .long
        return f
    }()

    static func iso(_ date: Date) -> String { isoFormatter.string(from: date) }
    static func parseIso(_ string: String) -> Date? { isoFormatter.date(from: string) }
    static func long(_ date: Date) -> String { longFormatter.string(from: date) }

    /// Næste forekomst af en årlig dato (fødselsdag) fra og med i dag.
    static func nextOccurrence(of date: Date, from today: Date = Date()) -> Date {
        let cal = Calendar.current
        let start = cal.startOfDay(for: today)
        var comps = cal.dateComponents([.month, .day], from: date)
        comps.year = cal.component(.year, from: start)
        var next = cal.date(from: comps) ?? start
        if next < start {
            comps.year = (comps.year ?? 0) + 1
            next = cal.date(from: comps) ?? next
        }
        return next
    }
}
