import SwiftUI
import UserNotifications

// Klokken på Hjem: de seneste notifikationer (nyt fra familien og påmindelser).
// Tryk på en, og appen åbner det, den handler om.

extension Notification.Name {
    /// Åbn det, en notifikation handler om (object: NotificationLogEntry).
    static let openNotificationTarget = Notification.Name("mindebog.openNotificationTarget")
    /// Skift faneblad på Familie (object: FamilyView.Tab.rawValue).
    static let openFamilyTab = Notification.Name("mindebog.openFamilyTab")
}

enum NotificationInbox {
    /// Påmindelser kommer med i loggen: dem, der ligger i Notifikationscenter, og dem, hvis tidspunkt
    /// er passeret, selvom de blev swipet væk på låseskærmen (de huskes i PlannedReminders).
    static func syncDelivered() async {
        for p in PlannedReminders.takeDue() {
            record(id: p.id, date: p.fire, title: p.title, body: p.body, info: p.info)
        }
        let delivered = await UNUserNotificationCenter.current().deliveredNotifications()
        for n in delivered where Reminders.isReminder(n.request.identifier) {
            record(n.request, date: n.date)
        }
    }

    static func record(_ request: UNNotificationRequest, date: Date) {
        record(id: request.identifier, date: date, title: request.content.title, body: request.content.body,
               info: PlannedReminders.strings(request.content.userInfo))
    }

    private static func record(id: String, date: Date, title: String, body: String, info: [String: String]) {
        var info = info
        // Månedsdags- og mavebilleder har barnets id i id'et: "reminder_<childId>_m3".
        let parts = id.split(separator: "_")
        if info["child"] == nil, info["promptChild"] == nil, info["interviewChild"] == nil, parts.count >= 3, parts[0] == "reminder" {
            info["child"] = parts.dropFirst().dropLast().joined(separator: "_")
        }
        NotificationLog.append(NotificationLogEntry(id: id, date: date, title: title, body: body, kind: "reminder", info: info))
    }
}

/// De påmindelser, appen har planlagt, med tidspunkt og tekst. iOS fortæller ikke appen om en
/// påmindelse, der swipes væk uden at blive åbnet — så vi husker dem selv og lægger dem i klokken,
/// når tidspunktet er passeret. Aflyste påmindelser glemmes igen (`forget`).
enum PlannedReminders {
    struct Planned: Codable {
        let id: String
        let fire: Date
        let title: String
        let body: String
        let info: [String: String]
    }

    private static let key = "mindebog.plannedReminders"

    private static func load() -> [String: Planned] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([Planned].self, from: data) else { return [:] }
        return Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
    }

    private static func save(_ map: [String: Planned]) {
        guard let data = try? JSONEncoder().encode(Array(map.values)) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func strings(_ userInfo: [AnyHashable: Any]) -> [String: String] {
        var out: [String: String] = [:]
        for (k, v) in userInfo { if let key = k as? String { out[key] = "\(v)" } }
        return out
    }

    /// Kaldes, når en påmindelse er lagt i kø hos iOS.
    static func note(_ request: UNNotificationRequest) {
        guard let trigger = request.trigger as? UNCalendarNotificationTrigger, let fire = trigger.nextTriggerDate() else { return }
        var map = load()
        map[request.identifier] = Planned(id: request.identifier, fire: fire, title: request.content.title,
                                          body: request.content.body, info: strings(request.content.userInfo))
        save(map)
    }

    /// Kaldes, når ventende påmindelser aflyses (fx ved ny planlægning eller når de slås fra).
    static func forget(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        var map = load()
        let now = Date()
        // Kun fremtidige: en påmindelse, hvis tidspunkt er passeret, er allerede vist og skal i klokken.
        for id in ids where (map[id]?.fire ?? .distantPast) > now { map[id] = nil }
        save(map)
    }

    /// Påmindelser, hvis tidspunkt er passeret — de fjernes fra listen, når de hentes.
    static func takeDue(now: Date = Date()) -> [Planned] {
        var map = load()
        let due = map.values.filter { $0.fire <= now }
        for p in due { map[p.id] = nil }
        if !due.isEmpty { save(map) }
        return due.sorted { $0.fire < $1.fire }
    }
}

struct NotificationsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [NotificationLogEntry] = []
    @State private var lastSeen = NotificationLog.lastSeen

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView("Ingen notifikationer endnu", systemImage: "bell",
                                           description: Text("Her samles beskeder om nyt i familien og jeres påmindelser."))
                } else {
                    List {
                        Group {
                            ForEach(entries) { e in
                                Button {
                                    dismiss()
                                    // Lidt forsinket, så arket er lukket, før appen navigerer.
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                        NotificationCenter.default.post(name: .openNotificationTarget, object: e)
                                    }
                                } label: { row(e) }
                            }
                            .onDelete { idx in
                                entries.remove(atOffsets: idx)
                                NotificationLog.save(entries)
                            }
                        }
                        .listRowBackground(Theme.card)
                    }
                    .themedList()
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Notifikationer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Luk") { dismiss() } }
                if !entries.isEmpty {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Ryd") { NotificationLog.clear(); entries = [] }
                    }
                }
            }
        }
        .task {
            await NotificationInbox.syncDelivered()
            entries = NotificationLog.load()
            NotificationLog.lastSeen = Date()
        }
    }

    private func row(_ e: NotificationLogEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: Self.symbol(e.kind))
                .font(.system(size: 16))
                .foregroundStyle(e.kind == "reminder" ? Theme.neutralDark : Theme.rose)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Theme.bgDark))
            VStack(alignment: .leading, spacing: 3) {
                Text(e.body.isEmpty ? e.title : e.body)
                    .font(.subheadline.weight(e.date > lastSeen ? .semibold : .regular))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.leading)
                Text(Self.when(e.date)).font(.caption).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
            if e.date > lastSeen { Circle().fill(Theme.rose).frame(width: 8, height: 8).padding(.top, 6) }
        }
        .padding(.vertical, 4)
    }

    static func symbol(_ kind: String) -> String {
        switch kind {
        case "Highlight": "star"
        case "Diary": "book"
        case "GalleryItem": "photo.on.rectangle"
        case "Milestone": "flag"
        case "Interview": "bubble.left.and.text.bubble.right"
        case "Letter": "envelope"
        case "Memory": "heart.text.square"
        case "Event": "calendar"
        case "Vacation": "airplane.departure"
        case "Birthday": "gift"
        case "Tradition": "sparkles"
        case "Recipe": "fork.knife"
        case "Comment": "bubble.left"
        case "reminder": "bell"
        default: "sparkle"
        }
    }

    static func when(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "da_DK")
        f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: Date())
    }
}

/// Klokken med antal ulæste — til værktøjslinjen på Hjem.
struct NotificationBell: View {
    @State private var unread = NotificationLog.unreadCount
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            Image(systemName: unread > 0 ? "bell.badge" : "bell")
                .symbolRenderingMode(unread > 0 ? .palette : .monochrome)
                .foregroundStyle(unread > 0 ? Theme.rose : Theme.text, Theme.text)
        }
        .accessibilityLabel(unread > 0 ? "Notifikationer, \(unread) nye" : "Notifikationer")
        .sheet(isPresented: $open, onDismiss: { unread = NotificationLog.unreadCount }) { NotificationsView() }
        .task { await NotificationInbox.syncDelivered(); unread = NotificationLog.unreadCount }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await NotificationInbox.syncDelivered(); unread = NotificationLog.unreadCount }
        }
        .onReceive(NotificationCenter.default.publisher(for: .storeDidChange)) { _ in unread = NotificationLog.unreadCount }
    }
}

/// Faneblad på Familie, der skal vises — gemt, hvis Familie-skærmen ikke findes endnu.
enum FamilyTabLink {
    static var pending: String?
}
