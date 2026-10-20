import Foundation

// De danske skoleferier — som anledning til minder, ikke som kalender. Fem nationale ferier,
// der ligger fast nok til at være indbygget; den eneste reelle forskel mellem kommunerne er
// vinterferien (uge 7 i det meste af landet, uge 8 i København og omegn), som vælges under Mere.
// Intet oprettes automatisk: ugens spørgsmål efter ferien og et kort på Hjem i feriens sidste dage.
enum SchoolHolidays {
    struct Holiday: Hashable {
        let name: String            // "vinterferien"
        let title: String           // "Vinterferien 2026"
        let start: Date             // første feriedag (lørdag)
        let end: Date               // sidste feriedag (søndag), kl. 23:59
        var range: ClosedRange<Date> { start...end }
    }

    private static let winterWeekKey = "mindebog.winterHolidayWeek"
    /// Vinterferiens uge: 7 (det meste af landet) eller 8 (København, Nordsjælland m.fl.).
    static var winterWeek: Int {
        get { let w = UserDefaults.standard.integer(forKey: winterWeekKey); return w == 8 ? 8 : 7 }
        set { UserDefaults.standard.set(newValue, forKey: winterWeekKey) }
    }

    private static var cal: Calendar {
        var c = Calendar(identifier: .iso8601)
        c.locale = Locale(identifier: "da_DK")
        return c
    }

    /// Ferierne i et kalenderår, i rækkefølge.
    static func holidays(in year: Int) -> [Holiday] {
        var out: [Holiday] = []
        // Vinterferie: lørdagen før uge 7/8 til søndagen i ugen.
        if let monday = cal.date(from: DateComponents(weekOfYear: winterWeek, yearForWeekOfYear: year, weekday: 2)) {
            out.append(make("vinterferien", "Vinterferien \(year)", from: monday.addingTimeInterval(-2 * 86_400), days: 9))
        }
        // Påskeferie: lørdagen før palmesøndag til 2. påskedag.
        if let easter = easterSunday(year) {
            out.append(make("påskeferien", "Påskeferien \(year)", from: easter.addingTimeInterval(-8 * 86_400), days: 10))
        }
        // Sommerferie: sidste lørdag i juni, ca. 6½ uge frem.
        if let june30 = cal.date(from: DateComponents(year: year, month: 6, day: 30)) {
            let back = (cal.component(.weekday, from: june30) - 7 + 7) % 7   // dage tilbage til lørdag
            let start = june30.addingTimeInterval(Double(-back) * 86_400)
            out.append(make("sommerferien", "Sommerferien \(year)", from: start, days: 45))
        }
        // Efterårsferie: uge 42.
        if let monday = cal.date(from: DateComponents(weekOfYear: 42, yearForWeekOfYear: year, weekday: 2)) {
            out.append(make("efterårsferien", "Efterårsferien \(year)", from: monday.addingTimeInterval(-2 * 86_400), days: 9))
        }
        // Juleferie: lørdagen på eller før d. 23. december til søndagen på eller efter d. 2. januar.
        if let dec23 = cal.date(from: DateComponents(year: year, month: 12, day: 23)),
           let jan2 = cal.date(from: DateComponents(year: year + 1, month: 1, day: 2)) {
            let back = (cal.component(.weekday, from: dec23) - 7 + 7) % 7
            let start = dec23.addingTimeInterval(Double(-back) * 86_400)
            let forward = (1 - cal.component(.weekday, from: jan2) + 7) % 7
            let endDay = jan2.addingTimeInterval(Double(forward) * 86_400)
            let days = (cal.dateComponents([.day], from: start, to: endDay).day ?? 10) + 1
            out.append(make("juleferien", "Juleferien \(year)", from: start, days: days))
        }
        return out.sorted { $0.start < $1.start }
    }

    private static func make(_ name: String, _ title: String, from start: Date, days: Int) -> Holiday {
        let s = cal.startOfDay(for: start)
        let e = cal.date(byAdding: .day, value: days, to: s)!.addingTimeInterval(-1)
        return Holiday(name: name, title: title, start: s, end: e)
    }

    /// Påskedag (gregoriansk, "Meeus/Jones/Butcher").
    static func easterSunday(_ year: Int) -> Date? {
        let a = year % 19, b = year / 100, c = year % 100
        let d = b / 4, e = b % 4, f = (b + 8) / 25, g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4, k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = ((h + l - 7 * m + 114) % 31) + 1
        return cal.date(from: DateComponents(year: year, month: month, day: day))
    }

    /// Ferierne omkring nu (sidste, dette og næste år), så årsskiftet ikke driller.
    static func around(_ now: Date = Date()) -> [Holiday] {
        let y = cal.component(.year, from: now)
        return holidays(in: y - 1) + holidays(in: y) + holidays(in: y + 1)
    }

    /// Den ferie, der er i gang og slutter inden for de næste `days` dage — til kortet på Hjem.
    static func endingSoon(_ now: Date = Date(), days: Int = 3) -> Holiday? {
        around(now).first { $0.range.contains(now) && $0.end.timeIntervalSince(now) <= Double(days) * 86_400 }
    }

    /// Den ferie, der sluttede inden for de sidste `days` dage før `date` — til ugens spørgsmål.
    static func justEnded(before date: Date, days: Int = 7) -> Holiday? {
        around(date).first { $0.end <= date && date.timeIntervalSince($0.end) <= Double(days) * 86_400 }
    }

    /// Kortet på Hjem kan afvises for netop denne ferie.
    static func isDismissed(_ h: Holiday) -> Bool { UserDefaults.standard.bool(forKey: "mindebog.holidayCard.\(h.title)") }
    static func dismiss(_ h: Holiday) { UserDefaults.standard.set(true, forKey: "mindebog.holidayCard.\(h.title)") }
}
