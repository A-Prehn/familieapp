import Foundation
import UserNotifications

// "På denne dag": en lokal notifikation kl. 9 på årsdagen for et minde —
// "På denne dag i 2024 📖 · Nohr: Første tur til stranden". Planlægges ud fra
// minde-oversigten, når Hjem indlæses; kun de næste uger, så der er plads under
// iOS' grænse på 64 planlagte notifikationer.
enum OnThisDay {
    static let prefix = "onthisday_"
    private static let enabledKey = "mindebog.onThisDayReminder"
    private static let hour = 9
    private static let daysAhead = 21
    private static let limit = 8

    /// Slået til som standard, når påmindelser er slået til.
    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// Erstatter de planlagte "på denne dag"-notifikationer med nye ud fra minderne.
    static func schedule(summaries: [MemorySummary], childNames: [String: String]) async {
        let center = UNUserNotificationCenter.current()
        let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: old)
        guard Reminders.isEnabled, isEnabled else { return }

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let thisYear = cal.component(.year, from: today)
        var upcoming: [(fire: Date, summary: MemorySummary)] = []
        for s in summaries {
            guard let date = s.date, !s.text.isEmpty, classic(s.kind) else { continue }
            let year = cal.component(.year, from: date)
            guard year < thisYear else { continue }   // kun minder fra tidligere år
            var comps = cal.dateComponents([.month, .day], from: date)
            comps.year = thisYear
            comps.hour = hour
            guard var fire = cal.date(from: comps) else { continue }
            if fire < Date() { fire = cal.date(byAdding: .year, value: 1, to: fire) ?? fire }
            guard let days = cal.dateComponents([.day], from: today, to: fire).day, days <= daysAhead else { continue }
            upcoming.append((fire, s))
        }
        // Ét minde pr. dag er nok — det nyeste år først, så "i 2024" slår "i 2019".
        var seenDays: Set<String> = []
        let chosen = upcoming.sorted { ($0.fire, $1.summary.date ?? .distantPast) < ($1.fire, $0.summary.date ?? .distantPast) }
            .filter { seenDays.insert(Fmt.iso($0.fire)).inserted }
            .prefix(limit)
        for (fire, s) in chosen {
            let year = cal.component(.year, from: s.date ?? fire)
            let who = s.childId.flatMap { childNames[$0] }
            let content = UNMutableNotificationContent()
            content.title = "På denne dag i \(year) 📖"
            content.body = (who.map { "\($0): " } ?? "") + s.text
            content.sound = .default
            let parts = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let request = UNNotificationRequest(identifier: prefix + s.id,
                                                content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
            try? await center.add(request)
        }
    }

    private static func classic(_ kind: MemorySummary.Kind) -> Bool {
        switch kind {
        case .highlight, .diary, .event, .vacation, .memory: return true
        default: return false
        }
    }
}
