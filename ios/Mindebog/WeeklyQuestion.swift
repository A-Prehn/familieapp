import Foundation
import UserNotifications

// Ugens spørgsmål: en påmindelse hver lørdag kl. 10 med et spørgsmål, der passer til
// barnets alder — "Hvad fik Nohr til at grine i denne uge?". Tryk åbner dagbogen med
// spørgsmålet som overskrift, så man bare skal skrive svaret. Planlægges sammen med
// de andre påmindelser (Reminders.schedule), fire uger frem pr. barn.
enum WeeklyQuestion {
    private static let enabledKey = "mindebog.weeklyQuestion"
    static let weeksAhead = 4

    /// Slået til som standard, når påmindelser er slået til.
    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// Spørgsmålene for et barn på en bestemt uge. Samme barn og uge giver altid samme
    /// spørgsmål, så listen i Notifikationscenter ikke skifter, hver gang den planlægges igen.
    static func question(for child: Child, week: Int) -> String {
        let list = questions(for: child)
        // Stabil "hash" (Swifts hashValue skifter ved hver appstart).
        let seed = child.id.unicodeScalars.reduce(0) { ($0 + Int($1.value)) % 1_000_003 } % max(list.count, 1)
        return list[(seed + week) % list.count].replacingOccurrences(of: "{navn}", with: child.name)
    }

    private static func questions(for child: Child) -> [String] {
        if child.onTheWay { return pregnancy }
        guard let birth = child.birthDate else { return pregnancy }
        let months = Calendar.current.dateComponents([.month], from: birth, to: Date()).month ?? 0
        switch months {
        case ..<12: return baby
        case 12..<36: return toddler
        case 36..<72: return preschool
        case 72..<144: return school
        default: return teen
        }
    }

    static let pregnancy = [
        "Hvordan har maven det i denne uge?",
        "Hvad glæder I jer mest til lige nu?",
        "Hvad har I fået af gode råd i denne uge — og hvad tænker I om dem?",
        "Hvilke navne har I talt om?",
        "Hvad har {navn} lavet af spark og bevægelser i denne uge?",
        "Hvad har I gjort klar derhjemme i denne uge?",
        "Hvad drømmer I om, at {navn} kommer til at elske?",
        "Hvad har overrasket jer mest ved graviditeten indtil nu?",
    ]
    static let baby = [
        "Hvad har {navn} lært i denne uge?",
        "Hvad fik {navn} til at grine i denne uge?",
        "Hvordan har nætterne været?",
        "Hvad er {navn}s yndlingsleg lige nu?",
        "Hvilken lyd eller pludren har I hørt mest i denne uge?",
        "Hvem har {navn} mødt i denne uge?",
        "Hvad har været det sværeste i denne uge — og det bedste?",
        "Hvad spiser {navn} gerne lige nu?",
        "Hvad gør {navn} rolig, når det hele er for meget?",
    ]
    static let toddler = [
        "Hvilket nyt ord har {navn} sagt i denne uge?",
        "Hvad fik {navn} til at grine i denne uge?",
        "Hvad vil {navn} helst lege lige nu?",
        "Hvad har {navn} været stædig omkring i denne uge?",
        "Hvilken bog eller sang vil {navn} høre igen og igen?",
        "Hvad har {navn} prøvet for første gang i denne uge?",
        "Hvad sagde {navn}, der fik jer til at smile?",
        "Hvad er {navn} bange for lige nu — og hvad hjælper?",
        "Hvem vil {navn} helst være sammen med?",
    ]
    static let preschool = [
        "Hvad har {navn} været mest optaget af i denne uge?",
        "Hvilket spørgsmål stillede {navn}, som I ikke kunne svare på?",
        "Hvad vil {navn} være, når {navn} bliver stor — lige nu?",
        "Hvad sagde {navn}, der fik jer til at grine?",
        "Hvad har {navn} tegnet eller bygget i denne uge?",
        "Hvem er {navn}s bedste ven lige nu?",
        "Hvad har {navn} lært i denne uge?",
        "Hvad har I lavet sammen, som {navn} ikke ville stoppe med?",
        "Hvad er {navn}s yndlingsmad lige nu?",
    ]
    static let school = [
        "Hvad var det bedste i skolen i denne uge?",
        "Hvad er {navn} god til, som {navn} ikke selv ved endnu?",
        "Hvad har {navn} været stolt af i denne uge?",
        "Hvad griner {navn} ad lige nu?",
        "Hvad har I talt om ved aftensmaden i denne uge?",
        "Hvad vil {navn} helst lave i weekenden?",
        "Hvilken bog, serie eller spil fylder lige nu?",
        "Hvad var svært i denne uge — og hvordan gik det?",
        "Hvad sagde {navn}, som I vil huske?",
    ]
    static let teen = [
        "Hvad har {navn} været optaget af i denne uge?",
        "Hvad har I grinet af sammen i denne uge?",
        "Hvad fylder for {navn} lige nu?",
        "Hvad har {navn} lært jer i denne uge?",
        "Hvad har I været uenige om — og hvordan endte det?",
        "Hvad drømmer {navn} om lige nu?",
        "Hvad har I gjort sammen i denne uge?",
        "Hvad er {navn} god til, som I vil huske?",
    ]

    /// Ferier giver kun mening for et barn, der er født og fyldt et år.
    static func hasHolidays(_ child: Child, at date: Date = Date()) -> Bool {
        guard !child.onTheWay, let birth = child.birthDate,
              let oneYear = Calendar.current.date(byAdding: .year, value: 1, to: birth) else { return false }
        return date >= oneYear
    }

    /// Lørdage kl. 10 de næste uger, med spørgsmålet i teksten og som "deep link" til dagbogen.
    static func requests(for child: Child, prefix: String) -> [UNNotificationRequest] {
        guard isEnabled else { return [] }
        let cal = Calendar.current
        let now = Date()
        var out: [UNNotificationRequest] = []
        // Første lørdag fra i dag.
        var day = cal.startOfDay(for: now)
        while cal.component(.weekday, from: day) != 7 { day = cal.date(byAdding: .day, value: 1, to: day) ?? day }
        for n in 0..<weeksAhead {
            guard let date = cal.date(byAdding: .day, value: n * 7, to: day),
                  let fire = cal.date(bySettingHour: 10, minute: 0, second: 0, of: date), fire > now else { continue }
            let week = cal.component(.weekOfYear, from: fire) + cal.component(.year, from: fire) * 53
            // Lørdagen efter en skoleferie: spørg til ferien i stedet for ugens almindelige spørgsmål —
            // kun for børn, der er født og mindst et år (ikke "efterårsferien for Baby Blob", #49).
            let holiday = hasHolidays(child, at: fire) ? SchoolHolidays.justEnded(before: fire) : nil
            let q = holiday.map { "Hvad var det bedste ved \($0.name) for \(child.name)?" }
                ?? question(for: child, week: week)
            let content = UNMutableNotificationContent()
            content.title = "Ugens spørgsmål om \(child.name) ✏️"
            content.body = q
            content.sound = .default
            content.userInfo = ["promptChild": child.id, "promptText": q]
            let parts = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            out.append(UNNotificationRequest(identifier: "\(prefix)wq_\(child.id)_\(week)", content: content,
                                             trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
        }
        return out
    }
}
