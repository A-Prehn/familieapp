import Foundation

// Demo-familien til App Store-skærmbilleder (issue #20).
//
// Appen startes med argumentet "-demo" (UI-testen MindebogUITests gør det). Så bruger AppState
// hukommelseslageret i stedet for iCloud og fylder det med en fiktiv familie: Sheila og Martin
// med børnene William (9), Nohr (4) og Liv (5 måneder). Intet gemmes nogen steder — alt
// forsvinder, når appen lukkes. Billederne læses fra mappen i DEMO_PHOTOS_DIR
// (ios/Demo/photos i repoet; i simulatoren kan appen læse Mac'ens filsystem direkte).
//
// Datoerne regnes ud fra i dag, så aldre og "På denne dag" passer, uanset hvornår der køres.
enum DemoFamily {
    static var isActive: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }

    /// Sættes før AppState oprettes: Premium slået til, intet gammelt login.
    static func prepareDefaults() {
        let d = UserDefaults.standard
        for key in ["mindebog.userId", "mindebog.familyId", "mindebog.usedCloud", "mindebog.displayName"] {
            d.removeObject(forKey: key)
        }
        d.set(true, forKey: "mindebog.premium")
        d.set(true, forKey: "mindebog.canEdit")
        d.set(false, forKey: "mindebog.monthlyReminder")
    }

    // MARK: - Billeder

    private static let photoDir = ProcessInfo.processInfo.environment["DEMO_PHOTOS_DIR"] ?? ""

    private static func photo(_ name: String) -> Data? {
        guard !photoDir.isEmpty else { return nil }
        return try? Data(contentsOf: URL(fileURLWithPath: photoDir).appendingPathComponent(name + ".jpg"))
    }

    private static func photos(_ names: String...) -> [Data] { names.compactMap(photo) }
    private static func set(_ names: String...) -> PhotoSet { PhotoSet(photos: names.compactMap(photo)) }

    // MARK: - Datoer

    private static let cal = Calendar.current
    private static let today = cal.startOfDay(for: Date())
    private static func daysAgo(_ n: Int) -> Date { cal.date(byAdding: .day, value: -n, to: today)! }
    private static func monthsAgo(_ n: Int, days: Int = 0) -> Date {
        cal.date(byAdding: .day, value: -days, to: cal.date(byAdding: .month, value: -n, to: today)!)!
    }
    private static func yearsAgo(_ n: Int, days: Int = 0) -> Date {
        cal.date(byAdding: .day, value: -days, to: cal.date(byAdding: .year, value: -n, to: today)!)!
    }
    private static func at(_ date: Date, hour: Int) -> Date { cal.date(bySettingHour: hour, minute: 15, second: 0, of: date)! }

    // MARK: - Opbygning

    /// Opretter familien i lageret og returnerer ejeren og familiens id.
    static func seed(into store: Store) async throws -> (user: AppUser, familyId: String) {
        let sheila = try await store.signIn(name: "Sheila")
        let family = try await store.createFamily(userId: sheila.id, name: "Familien Lund")
        let fid = family.id
        try await store.setMemberName(familyId: fid, userId: sheila.id, name: "Sheila")
        try await store.setFamilyPremium(familyId: fid, until: Date(timeIntervalSince1970: 32_503_680_000))

        // Partneren og mormor er med i familien.
        let martin = try await store.signIn(name: "Martin")
        let mormor = try await store.signIn(name: "Mormor Inger")
        for member in [martin, mormor] {
            let code = try await store.createInvite(userId: sheila.id, familyId: fid)
            _ = try await store.acceptInvite(userId: member.id, code: code)
        }

        // Børn
        let william = try await store.createChild(familyId: fid, name: "William", gender: .boy,
                                                  birthDate: yearsAgo(9, days: 41), dueDate: nil)
        let nohr = try await store.createChild(familyId: fid, name: "Nohr", gender: .boy,
                                               birthDate: yearsAgo(4, days: 98), dueDate: nil)
        let liv = try await store.createChild(familyId: fid, name: "Liv", gender: .girl,
                                              birthDate: monthsAgo(5, days: 6), dueDate: nil)

        // Profilbilleder (uden ansigter).
        for (child, file) in [(william, "lagkage"), (nohr, "cykel"), (liv, "finger")] {
            var c = child; c.photo = photo(file); _ = try await store.updateChild(c)
        }

        // Rækkefølgen betyder noget: "Seneste i familien" viser det sidst gemte først,
        // så Nohrs cykeltur (med billede) gemmes til allersidst.
        try await seedFamily(store, fid, children: (william, nohr, liv), author: martin)
        try await seedWilliam(store, william)
        try await seedLiv(store, liv, commenter: mormor)
        try await seedNohr(store, nohr, commenters: [martin, mormor])

        return (sheila, fid)
    }

    // MARK: Nohr (4 år)

    private static func seedNohr(_ store: Store, _ child: Child, commenters: [AppUser]) async throws {
        let id = child.id
        _ = try await store.addHighlight(childId: id, date: at(daysAgo(11), hour: 10),
            text: "Efterår i gummistøvler. Hver eneste vandpyt skulle prøves af.",
            photos: photos("gummistovler"), cover: 0, place: nil)
        _ = try await store.addHighlight(childId: id, date: at(daysAgo(34), hour: 18),
            text: "Sagde \"jeg elsker dig, mor\" helt af sig selv, da han blev puttet.",
            photos: [], cover: 0, place: nil)
        // Tre år siden i dag → "På denne dag" på Hjem.
        _ = try await store.addHighlight(childId: id, date: at(yearsAgo(3), hour: 11),
            text: "De allerførste skridt! Fra sofaen og hen til mormor — og så ned på numsen med et kæmpe grin.",
            photos: photos("forste-skridt"), cover: 0, place: nil)

        // Fødslen, så de første felter på Milepæle ikke står tomme.
        try await store.setMilestone(childId: id, key: "due_date", value: Fmt.iso(yearsAgo(4, days: 104)), photos: PhotoSet())
        try await store.setMilestone(childId: id, key: "birth_time", value: "06:42", photos: PhotoSet())
        try await store.setMilestone(childId: id, key: "birth_weight", value: "3450", photos: PhotoSet())
        try await store.setMilestone(childId: id, key: "birth_length", value: "52", photos: PhotoSet())
        try await store.setMilestone(childId: id, key: "first_steps", value: Fmt.iso(yearsAgo(3)), photos: set("forste-skridt"))
        try await store.setMilestone(childId: id, key: "walks", value: Fmt.iso(yearsAgo(3, days: -21)), photos: PhotoSet())
        try await store.setMilestone(childId: id, key: "first_word", value: "\"Mor\" — og lige bagefter \"nej\"", photos: PhotoSet())
        try await store.setMilestone(childId: id, key: "first_tooth", value: Fmt.iso(yearsAgo(3, days: 200)), photos: PhotoSet())
        try await store.setMilestone(childId: id, key: "first_smile", value: Fmt.iso(yearsAgo(4, days: 56)), photos: PhotoSet())
        try await store.setMilestone(childId: id, key: "eye_color", value: "Blå", photos: PhotoSet())
        try await store.setMilestone(childId: id, key: "hair_color", value: "Lyst", photos: PhotoSet())
        try await store.setMilestone(childId: id, key: "fav_toy", value: "Bamsen Bjørn", photos: PhotoSet())
        try await store.setMilestone(childId: id, key: "fav_song", value: "Lille Peter Edderkop", photos: PhotoSet())
        try await store.setMilestone(childId: id, key: "first_beach", value: Fmt.iso(yearsAgo(3, days: 20)), photos: PhotoSet())
        try await store.setMilestone(childId: id, key: "first_birthday", value: Fmt.iso(yearsAgo(3, days: 98)), photos: PhotoSet())

        let birthday = try await store.addGalleryItem(childId: id, kind: .birthday, caption: "3", photo: photo("kage-3"))
        var b = birthday; b.date = yearsAgo(1, days: 98); try await store.updateGalleryItem(childId: id, b)
        let d1 = try await store.addGalleryItem(childId: id, kind: .drawings, caption: "Vores hus", photo: photo("tegner"))
        var d1b = d1; d1b.date = daysAgo(5); d1b.note = "Tegnet i børnehaven. Den grønne er far."; try await store.updateGalleryItem(childId: id, d1b)
        let d2 = try await store.addGalleryItem(childId: id, kind: .drawings, caption: "Regnbuen", photo: photo("regnbue"))
        var d2b = d2; d2b.date = daysAgo(60); try await store.updateGalleryItem(childId: id, d2b)

        // Det årlige interview — 3 og 4 år, så man kan høre svarene vokse.
        let answers: [(Int, String, String)] = [
            (3, "q10", "Nohr. Tre år."), (3, "q1", "Is."), (3, "q2", "En traktor."), (3, "q4", "Pølser."), (3, "q6", "Far."),
            (4, "q10", "Jeg hedder Nohr, og jeg er fire år."), (4, "q1", "At cykle rigtig hurtigt og spise is bagefter."),
            (4, "q2", "Brandmand. Eller måske en, der kører tog."), (4, "q3", "Oskar fra børnehaven. Og Bjørn."),
            (4, "q4", "Pandekager med sukker. Og mormors æblekage."), (4, "q6", "Når far laver sjov, og når Liv griner."),
            (4, "q7", "Edderkopper. Store."), (4, "q9", "En rigtig gravko."),
        ]
        for (age, key, text) in answers {
            let answer = InterviewAnswer(id: newId("iv"), age: age, question: key, text: text,
                                         date: age == 4 ? daysAgo(98) : yearsAgo(1, days: 98))
            try await store.saveInterviewAnswer(childId: id, answer, audio: .keep, video: .keep)
        }

        try await store.setAnswer(childId: id, question: "Hvad får dig til at grine?", answer: "Når far lader som om, han falder.")
        try await store.setAnswer(childId: id, question: "Hvad er din yndlingsmad?", answer: "Pandekager")
        try await store.setAnswer(childId: id, question: "Hvad kan du ikke sove uden?", answer: "Bamsen Bjørn og den lille lampe")
        try await store.setAnswer(childId: id, question: "Hvad vil du gerne være når du bliver stor?", answer: "Brandmand")

        _ = try await store.addDiary(childId: id, date: at(daysAgo(2), hour: 20),
            text: "Spurgte i dag, om månen også skal sove. Vi blev enige om, at den sover om dagen.", photo: nil)
        _ = try await store.addDiary(childId: id, date: at(daysAgo(20), hour: 19),
            text: "Første dag i den store gruppe i børnehaven. Lidt stille om morgenen, kæmpe smil ved afhentning.", photo: nil)

        try await store.addLetter(childId: id, Letter(id: newId("letter"), title: "Til dig, når du bliver 18",
            text: "Kære Nohr. I dag lærte du at cykle …", author: "Mor", writtenAt: today,
            openDate: cal.date(byAdding: .year, value: 18, to: child.birthDate!)))
        try await store.saveMeasurement(childId: id, Measurement(id: newId("m"), date: yearsAgo(4, days: 98), weightGrams: 3450, heightCm: 52, headCm: 35))
        try await store.saveMeasurement(childId: id, Measurement(id: newId("m"), date: yearsAgo(3, days: 98), weightGrams: 9800, heightCm: 76, headCm: 46))
        try await store.saveMeasurement(childId: id, Measurement(id: newId("m"), date: yearsAgo(2, days: 98), weightGrams: 12600, heightCm: 88, headCm: 48))
        try await store.saveMeasurement(childId: id, Measurement(id: newId("m"), date: daysAgo(98), weightGrams: 17200, heightCm: 104, headCm: 50))

        // Dagens højdepunkt gemmes til sidst, så det står øverst i "Seneste i familien".
        let cykel = try await store.addHighlight(childId: id, date: at(today, hour: 16),
            text: "Første tur på cyklen uden støttehjul! Han kiggede sig tilbage for at se, om far stadig holdt fast — og det gjorde han ikke.",
            photos: photos("cykel"), cover: 0, place: nil)

        // Reaktioner fra familien på dagens højdepunkt.
        for (i, member) in commenters.enumerated() {
            try await store.addComment(familyId: child.familyId, Comment(id: newId("c"), targetId: cykel.id,
                text: i == 0 ? "" : "Sikke en sej dreng! ❤️", emoji: i == 0 ? "👏" : "",
                authorId: member.id, authorName: member.name, createdAt: Date()))
        }
    }

    // MARK: William (9 år)

    private static func seedWilliam(_ store: Store, _ child: Child) async throws {
        let id = child.id
        _ = try await store.addHighlight(childId: id, date: at(daysAgo(41), hour: 15),
            text: "9 år! Ønskede sig lagkage med jordbær og fik det. Blæste alle lysene ud i ét pust.",
            photos: photos("lagkage"), cover: 0, place: nil)
        _ = try await store.addHighlight(childId: id, date: at(daysAgo(70), hour: 8),
            text: "Første skoledag i 3. klasse. Ville selv cykle hele vejen.", photos: [], cover: 0, place: nil)
        _ = try await store.addHighlight(childId: id, date: at(daysAgo(15), hour: 17),
            text: "Scorede sit første mål til fodbold. Løb en hel omgang med armene i vejret.", photos: [], cover: 0, place: nil)

        let birthday = try await store.addGalleryItem(childId: id, kind: .birthday, caption: "9", photo: photo("lagkage"))
        var b = birthday; b.date = daysAgo(41); try await store.updateGalleryItem(childId: id, b)

        try await store.setMilestone(childId: id, key: "first_word", value: "\"Bil\"", photos: PhotoSet())
        try await store.setMilestone(childId: id, key: "first_steps", value: Fmt.iso(yearsAgo(8, days: 20)), photos: PhotoSet())
        try await store.setMilestone(childId: id, key: "eye_color", value: "Grøn", photos: PhotoSet())
        try await store.setMilestone(childId: id, key: "hair_color", value: "Mellemblond", photos: PhotoSet())
        try await store.setMilestone(childId: id, key: "first_flight", value: Fmt.iso(yearsAgo(6, days: 10)), photos: PhotoSet())

        let answers: [(Int, String, String)] = [
            (8, "q10", "William, otte år."), (8, "q1", "Fodbold og Lego."), (8, "q2", "Fodboldspiller."), (8, "q8", "Sommerferien i Skagen."),
            (9, "q10", "Jeg hedder William og er lige blevet ni."), (9, "q1", "At spille fodbold med Elias og Noah."),
            (9, "q2", "Fodboldspiller — eller opfinder."), (9, "q3", "Elias."), (9, "q4", "Lasagne."),
            (9, "q6", "Når vi spiller spil hele familien."), (9, "q8", "Da jeg scorede mit første mål."),
        ]
        for (age, key, text) in answers {
            let answer = InterviewAnswer(id: newId("iv"), age: age, question: key, text: text,
                                         date: age == 9 ? daysAgo(41) : yearsAgo(1, days: 41))
            try await store.saveInterviewAnswer(childId: id, answer, audio: .keep, video: .keep)
        }
        try await store.saveMeasurement(childId: id, Measurement(id: newId("m"), date: daysAgo(41), weightGrams: 31000, heightCm: 137, headCm: nil))
    }

    // MARK: Liv (5 måneder)

    private static func seedLiv(_ store: Store, _ child: Child, commenter: AppUser) async throws {
        let id = child.id
        let born = child.birthDate!
        let welcome = try await store.addHighlight(childId: id, date: at(born, hour: 4),
            text: "Velkommen til verden, lille Liv. 3.280 g og 50 cm, født kl. 04.12 efter en lang nat.",
            photos: photos("finger"), cover: 0, place: nil)
        _ = try await store.addHighlight(childId: id, date: at(daysAgo(3), hour: 9),
            text: "Grinede højt for første gang — af Nohr, der lavede fiskemund.", photos: [], cover: 0, place: nil)

        let months: [(String, String, Int)] = [("fodder-nyfodt", "Nyfødt", 0), ("fodder-strik", "3 måneder", 3), ("babysko", "5 måneder", 5)]
        for (file, caption, m) in months {
            let item = try await store.addGalleryItem(childId: id, kind: .monthly, caption: caption, photo: photo(file))
            var i = item; i.date = cal.date(byAdding: .month, value: m, to: born); try await store.updateGalleryItem(childId: id, i)
        }

        try await store.setMilestone(childId: id, key: "birth_time", value: "04:12", photos: PhotoSet())
        try await store.setMilestone(childId: id, key: "first_smile", value: Fmt.iso(cal.date(byAdding: .day, value: 38, to: born)!), photos: PhotoSet())
        try await store.setMilestone(childId: id, key: "first_laugh", value: Fmt.iso(daysAgo(3)), photos: PhotoSet())
        try await store.setMilestone(childId: id, key: "meets_grandparents", value: Fmt.iso(cal.date(byAdding: .day, value: 1, to: born)!), photos: PhotoSet())
        try await store.setMilestone(childId: id, key: "first_car_ride", value: Fmt.iso(cal.date(byAdding: .day, value: 2, to: born)!), photos: PhotoSet())
        try await store.setMilestone(childId: id, key: "eye_color", value: "Skifter stadig", photos: PhotoSet())
        try await store.setMilestone(childId: id, key: "hair_color", value: "Intet hår endnu", photos: PhotoSet())

        try await store.saveMeasurement(childId: id, Measurement(id: newId("m"), date: born, weightGrams: 3280, heightCm: 50, headCm: 34))
        try await store.saveMeasurement(childId: id, Measurement(id: newId("m"), date: cal.date(byAdding: .month, value: 1, to: born)!, weightGrams: 4300, heightCm: 54, headCm: 37))
        try await store.saveMeasurement(childId: id, Measurement(id: newId("m"), date: cal.date(byAdding: .month, value: 3, to: born)!, weightGrams: 6100, heightCm: 61, headCm: 40))
        try await store.saveMeasurement(childId: id, Measurement(id: newId("m"), date: daysAgo(6), weightGrams: 7400, heightCm: 65, headCm: 42))

        try await store.addComment(familyId: child.familyId, Comment(id: newId("c"), targetId: welcome.id,
            text: "", emoji: "🥹", authorId: commenter.id, authorName: commenter.name, createdAt: born))
    }

    // MARK: Familie: rejse, minder, traditioner, opskrifter, fødselsdage

    private static func seedFamily(_ store: Store, _ fid: String, children: (Child, Child, Child), author: AppUser) async throws {
        let (william, nohr, liv) = children
        let summerStart = cal.date(from: DateComponents(year: cal.component(.year, from: today) - (cal.component(.month, from: today) < 8 ? 1 : 0), month: 7, day: 12))!
        _ = try await store.addVacation(familyId: fid, title: "Sommerferie i Skagen",
            start: summerStart, end: cal.date(byAdding: .day, value: 7, to: summerStart),
            details: "En uge i sommerhus ved Gl. Skagen. Grenen, is på havnen og William, der ville bade hver dag — uanset vejret.",
            photos: set("skagen-klit", "strand-born"),
            place: Place(name: "Skagen", address: "Skagen, Danmark", latitude: 57.7209, longitude: 10.5839),
            childIds: [william.id, nohr.id], personIds: [])

        _ = try await store.addEvent(familyId: fid, title: "Williams 9-års fødselsdag", date: daysAgo(41),
            details: "Lagkage med jordbær, skattejagt i haven og ni venner på besøg.",
            photos: set("lagkage"), place: nil, childIds: [william.id], personIds: [])
        _ = try await store.addEvent(familyId: fid, title: "Livs navngivning", date: cal.date(byAdding: .day, value: 48, to: liv.birthDate!),
            details: "Hjemme i haven med hele familien. Mormor holdt tale.",
            photos: PhotoSet(), place: nil, childIds: [liv.id], personIds: [])

        try await store.saveMemory(familyId: fid, FamilyMemory(id: newId("mem"), title: "Efterårstur i Gribskov", date: daysAgo(9),
            text: "Alle fem på tur. Nohr samlede kastanjer i lommerne, William fandt en pind, der 'var et sværd', og Liv sov hele vejen.",
            photos: set("skov"), childIds: [], personIds: [],
            place: Place(name: "Gribskov", address: "Gribskov, Nordsjælland", latitude: 55.98, longitude: 12.32)))

        try await store.saveTradition(familyId: fid, Tradition(id: newId("tr"), title: "Juleaften hos farmor", when: "24. december",
            details: "Risengrød kl. 12, gåtur til kirken, og så pakker i den rækkefølge, farmor bestemmer. Mandelgaven er altid et marcipangris.",
            photos: set("jul")), audio: .keep)
        try await store.saveTradition(familyId: fid, Tradition(id: newId("tr"), title: "Fødselsdagssangen", when: "Hver fødselsdag",
            details: "Vi vækker fødselaren med flag, sang og morgenmad i sengen. Far synger altid for højt med vilje.",
            photos: PhotoSet()), audio: .keep)
        try await store.saveTradition(familyId: fid, Tradition(id: newId("tr"), title: "Pandekagefredag", when: "Hver fredag",
            details: "Fredag aften er pandekager. Børnene vender selv — og det ender altid på gulvet mindst én gang.",
            photos: PhotoSet()), audio: .keep)

        try await store.saveRecipe(familyId: fid, Recipe(id: newId("r"), title: "Mormors æblekage", fromWhom: "Mormor Inger", servings: "8 stykker",
            ingredients: "6 æbler\n150 g smør\n150 g sukker\n3 æg\n200 g mel\n2 tsk bagepulver\n1 tsk kanel\nFlormelis til pynt",
            method: "Rør smør og sukker lyst. Pisk æggene i ét ad gangen. Vend mel og bagepulver i. Skær æblerne i både, og tryk dem ned i dejen. Drys med kanel. Bag ved 175° i ca. 45 minutter.",
            story: "Mormor lavede den hver søndag, når vi kom på besøg. Nu laver vi den, når æblerne falder i haven — og Nohr får lov at trykke æblerne i.",
            category: "Kager", photos: set("aeblekage")))
        try await store.saveRecipe(familyId: fid, Recipe(id: newId("r"), title: "Fars pandekager", fromWhom: "Martin", servings: "ca. 12 stk.",
            ingredients: "3 æg\n5 dl mælk\n250 g mel\n1 spsk sukker\nEt nip salt\nSmør til panden",
            method: "Pisk det hele sammen, og lad dejen hvile 20 minutter. Bag tynde pandekager i rigeligt smør.",
            story: "Fredagsopskriften. Den første pandekage er altid 'prøvepandekagen' — og den får den, der har dækket bord.",
            category: "Aftensmad", photos: set("pandekager")))

        _ = try await store.addBirthday(familyId: fid, name: "Mormor Inger", date: cal.date(from: DateComponents(year: 1956, month: 3, day: 14))!, emoji: "🎂")
        _ = try await store.addBirthday(familyId: fid, name: "Farmor Bente", date: cal.date(from: DateComponents(year: 1959, month: 11, day: 2))!, emoji: "🌸")

        _ = author   // partneren er med i familien; kommentarer er sat på børnenes højdepunkter
    }
}
