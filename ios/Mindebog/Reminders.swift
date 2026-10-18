import Foundation
import UserNotifications

// Månedlig påmindelse — lokale notifikationer på telefonen (ingen iCloud/server):
//  • Født barn under 3 år: hver "månedsdag" kl. 10 ("Theo er 3 måneder i dag 📸").
//  • Barn på vej: hver ny graviditetsuge kl. 10 ("Uge 24 i dag – tag ugens mavebillede").
// Planlægges igen hver gang børnene indlæses, så ændrede datoer og nye børn kommer med.
enum Reminders {
    static let enabledKey = "mindebog.monthlyReminder"
    private static let prefix = "reminder_"
    private static let hour = 10

    /// Hvor ofte man mindes om mavebilledet, mens barnet er på vej.
    enum BellyInterval: Int, CaseIterable, Identifiable {
        case weekly = 1, biweekly = 2, monthly = 4   // antal uger
        var id: Int { rawValue }
        var label: String {
            switch self {
            case .weekly: return "Hver uge"
            case .biweekly: return "Hver 14. dag"
            case .monthly: return "Hver måned"
            }
        }
    }
    private static let bellyIntervalKey = "mindebog.bellyReminderWeeks"

    /// Mavebilledet kan slås fra for sig — fx for den forælder, der ikke tager mavebillederne.
    private static let bellyEnabledKey = "mindebog.bellyReminderOn"
    static var bellyEnabled: Bool {
        get { UserDefaults.standard.object(forKey: bellyEnabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: bellyEnabledKey) }
    }

    static var bellyInterval: BellyInterval {
        get { BellyInterval(rawValue: UserDefaults.standard.integer(forKey: bellyIntervalKey)) ?? .biweekly }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: bellyIntervalKey) }
    }

    /// Hvilken ugedag mavebilledet påmindes. 0 = samme ugedag som terminen (ny graviditetsuge),
    /// ellers Calendar-ugedag (1 = søndag, 2 = mandag … 7 = lørdag).
    private static let bellyWeekdayKey = "mindebog.bellyReminderWeekday"
    static var bellyWeekday: Int {
        get { UserDefaults.standard.integer(forKey: bellyWeekdayKey) }
        set { UserDefaults.standard.set(newValue, forKey: bellyWeekdayKey) }
    }
    /// Klokkeslæt for mavebilledet i minutter efter midnat (standard 10:00).
    private static let bellyTimeKey = "mindebog.bellyReminderMinutes"
    static var bellyMinutes: Int {
        get { (UserDefaults.standard.object(forKey: bellyTimeKey) as? Int) ?? hour * 60 }
        set { UserDefaults.standard.set(newValue, forKey: bellyTimeKey) }
    }
    /// Valgmuligheder i rækkefølge mandag–søndag.
    struct WeekdayOption: Identifiable { let value: Int; let label: String; var id: Int { value } }
    static let weekdayOptions: [WeekdayOption] = [
        .init(value: 0, label: "Når en ny uge starter"), .init(value: 2, label: "Mandag"),
        .init(value: 3, label: "Tirsdag"), .init(value: 4, label: "Onsdag"),
        .init(value: 5, label: "Torsdag"), .init(value: 6, label: "Fredag"),
        .init(value: 7, label: "Lørdag"), .init(value: 1, label: "Søndag")]

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    // MARK: Det årlige interview
    // På fødselsdagen kl. 10: "Nohr fylder 10 i dag — tid til det årlige interview".
    // En uge efter kommer en blid påmindelse mere, hvis interviewet for den alder ikke er påbegyndt.
    private static let interviewKey = "mindebog.interviewReminder"
    private static let interviewStartedKey = "mindebog.interviewStarted"   // ["childId_alder", …]
    static let interviewMinAge = 2

    /// Slået til som standard, når påmindelser er slået til.
    static var interviewEnabled: Bool {
        get { UserDefaults.standard.object(forKey: interviewKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: interviewKey) }
    }

    private static func interviewStarted(_ childId: String, _ age: Int) -> Bool {
        (UserDefaults.standard.stringArray(forKey: interviewStartedKey) ?? []).contains("\(childId)_\(age)")
    }

    /// Kaldes, når der findes svar for en alder — så kommer opfølgningen ikke.
    static func markInterviewStarted(childId: String, age: Int) {
        let key = "\(childId)_\(age)"
        var list = UserDefaults.standard.stringArray(forKey: interviewStartedKey) ?? []
        guard !list.contains(key) else { return }
        list.append(key)
        UserDefaults.standard.set(list, forKey: interviewStartedKey)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["\(prefix)ivf_\(key)"])
    }

    /// Fødselsdagspåmindelse og evt. opfølgning for den næste fødselsdag (og en netop overstået).
    private static func interviewRequests(for child: Child) -> [UNNotificationRequest] {
        guard interviewEnabled, let birth = child.birthDate else { return [] }
        let cal = Calendar.current
        let now = Date()
        var out: [UNNotificationRequest] = []
        let currentAge = cal.dateComponents([.year], from: birth, to: now).year ?? 0
        // Den seneste fødselsdag (for en opfølgning, der stadig ligger ude i fremtiden) og den næste.
        for age in [currentAge, currentAge + 1] where age >= interviewMinAge {
            guard let birthday = cal.date(byAdding: .year, value: age, to: birth),
                  let fire = cal.date(bySettingHour: hour, minute: 0, second: 0, of: birthday) else { continue }
            let info: [String: Any] = ["interviewChild": child.id, "interviewAge": age]
            if fire > now {
                out.append(request(id: "\(prefix)iv_\(child.id)_\(age)", fire: fire,
                                   title: "\(child.name) fylder \(age) i dag 🎂",
                                   body: "Tid til det årlige interview. Stil de samme spørgsmål som sidst, og hør hvor meget der er sket.",
                                   userInfo: info))
            }
            if !interviewStarted(child.id, age),
               let followUp = cal.date(byAdding: .day, value: 7, to: fire), followUp > now {
                out.append(request(id: "\(prefix)ivf_\(child.id)_\(age)", fire: followUp,
                                   title: "Har I nået \(child.name)s interview?",
                                   body: "Der er stadig tid til at optage svarene for \(age) år — det tager kun ti minutter.",
                                   userInfo: info))
            }
        }
        return out
    }

    /// Slår til (spørger om tilladelse) og planlægger. Returnerer false hvis brugeren afviste.
    static func enable(children: [Child]) async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        UserDefaults.standard.set(granted, forKey: enabledKey)
        if granted { await schedule(children: children) }
        return granted
    }

    static func disable() async {
        UserDefaults.standard.set(false, forKey: enabledKey)
        await removeAll()
    }

    /// Erstatter alle planlagte påmindelser med nye ud fra børnene.
    static func schedule(children: [Child]) async {
        guard isEnabled else { return }
        await removeAll()
        let center = UNUserNotificationCenter.current()
        // iOS tillader højst 64 planlagte notifikationer pr. app — fordel dem,
        // og lad der være plads til "på denne dag" (OnThisDay).
        let perChild = max(4, 48 / max(children.count, 1))
        for child in children {
            // Interviewet og ugens spørgsmål først, så de ikke bliver skubbet ud af grænsen på 64.
            let interview = interviewRequests(for: child) + WeeklyQuestion.requests(for: child, prefix: prefix)
            for request in interview + requests(for: child, limit: max(1, perChild - interview.count)) {
                try? await center.add(request)
            }
        }
    }

    private static func removeAll() async {
        let center = UNUserNotificationCenter.current()
        let ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    private static func requests(for child: Child, limit: Int) -> [UNNotificationRequest] {
        let cal = Calendar.current
        let now = Date()
        var out: [UNNotificationRequest] = []

        if let birth = child.birthDate {
            // Månedsdage de næste måneder, indtil barnet fylder 3 år.
            for n in 1...36 where out.count < limit {
                guard let day = cal.date(byAdding: .month, value: n, to: birth),
                      let fire = cal.date(bySettingHour: hour, minute: 0, second: 0, of: day),
                      fire > now else { continue }
                let age: String
                if n % 12 == 0 { age = n == 12 ? "1 år" : "\(n / 12) år" }
                else if n > 12 { age = "\(n / 12) år og \(n % 12) \(n % 12 == 1 ? "måned" : "måneder")" }
                else { age = n == 1 ? "1 måned" : "\(n) måneder" }
                out.append(request(id: "\(prefix)\(child.id)_m\(n)", fire: fire,
                                   title: "\(child.name) er \(age) i dag 📸",
                                   body: "Tag månedens billede til Måned for måned."))
            }
        } else if bellyEnabled, let due = child.dueDate, due > now {
            // Graviditetsuger: uge 1 starter 40 uger før termin. Påmind hver uge, hver 14. dag
            // eller hver måned (4 uger) — fra uge 4, så rækken af mavebilleder bliver jævn.
            guard let start = cal.date(byAdding: .day, value: -280, to: due) else { return out }
            let step = bellyInterval.rawValue
            let what: String
            switch bellyInterval {
            case .weekly: what = "ugens mavebillede"
            case .biweekly: what = "et nyt mavebillede"
            case .monthly: what = "månedens mavebillede"
            }
            let weekday = bellyWeekday
            for week in stride(from: 4, through: 41, by: step) where out.count < limit {
                guard var day = cal.date(byAdding: .day, value: (week - 1) * 7, to: start) else { continue }
                // Valgt ugedag: ryk frem til den dag inden for samme graviditetsuge (0–6 dage).
                if weekday != 0 {
                    let shift = (weekday - cal.component(.weekday, from: day) + 7) % 7
                    day = cal.date(byAdding: .day, value: shift, to: day) ?? day
                }
                let minutes = bellyMinutes
                guard let fire = cal.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day),
                      fire > now, fire < due else { continue }
                out.append(request(id: "\(prefix)\(child.id)_w\(week)", fire: fire,
                                   title: weekday == 0 ? "Uge \(week) i dag 🤰" : "Uge \(week) 🤰",
                                   body: "Tid til \(what) af \(child.name) til Maven måned for måned."))
            }
        }
        return out
    }

    private static func request(id: String, fire: Date, title: String, body: String,
                                userInfo: [String: Any] = [:]) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = userInfo
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }

    static func isReminder(_ identifier: String) -> Bool {
        identifier.hasPrefix(prefix) || identifier.hasPrefix(OnThisDay.prefix)
    }
}
