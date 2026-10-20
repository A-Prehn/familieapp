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
    /// Påmindelser, der er vist (ligger i Notifikationscenter), kommer med i loggen.
    static func syncDelivered() async {
        let delivered = await UNUserNotificationCenter.current().deliveredNotifications()
        for n in delivered where Reminders.isReminder(n.request.identifier) {
            record(n.request, date: n.date)
        }
    }

    static func record(_ request: UNNotificationRequest, date: Date) {
        var info: [String: String] = [:]
        for (k, v) in request.content.userInfo {
            if let key = k as? String { info[key] = "\(v)" }
        }
        // Månedsdags- og mavebilleder har barnets id i id'et: "reminder_<childId>_m3".
        let parts = request.identifier.split(separator: "_")
        if info["child"] == nil, info["promptChild"] == nil, info["interviewChild"] == nil, parts.count >= 3, parts[0] == "reminder" {
            info["child"] = parts.dropFirst().dropLast().joined(separator: "_")
        }
        NotificationLog.append(NotificationLogEntry(
            id: request.identifier, date: date,
            title: request.content.title, body: request.content.body,
            kind: "reminder", info: info))
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
