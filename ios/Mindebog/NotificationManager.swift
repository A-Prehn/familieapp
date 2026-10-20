import UIKit
import CloudKit
import UserNotifications

// Notifikationer når der lægges noget nyt op i familien (fx af partneren).
// CloudKit sender selv push via database-abonnementer — ingen egen server/APNs-nøgle.
//  - Ejeren af familien: ændringer i egne zoner ligger i den private database.
//  - Partneren: familien er delt med dem og ligger i den delte database.
// Vi abonnerer på begge, så det virker uanset rolle.
@MainActor
enum NotificationManager {
    static let enabledKey = "mindebog.notifications"
    private static let container = CKContainer(identifier: "iCloud.net.prehn.mindebog")
    private static let privateSubID = "mindebog-private-changes"
    private static let sharedSubID = "mindebog-shared-changes"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    enum Result { case enabled, denied, failed(String) }

    /// Spørger om tilladelse, registrerer for push og opretter abonnementerne.
    static func enable() async -> Result {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else {
            UserDefaults.standard.set(false, forKey: enabledKey)
            return .denied
        }
        UIApplication.shared.registerForRemoteNotifications()
        do {
            try await save(subscription(id: privateSubID), in: container.privateCloudDatabase)
            try await save(subscription(id: sharedSubID), in: container.sharedCloudDatabase)
            UserDefaults.standard.set(true, forKey: enabledKey)
            await ChangeFeed.seedIfNeeded()
            return .enabled
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Fjerner abonnementerne — så sender CloudKit ikke flere notifikationer til denne enhed.
    static func disable() async {
        UserDefaults.standard.set(false, forKey: enabledKey)
        _ = try? await container.privateCloudDatabase.deleteSubscription(withID: privateSubID)
        _ = try? await container.sharedCloudDatabase.deleteSubscription(withID: sharedSubID)
    }

    /// Ved opstart: registrér for push igen, hvis brugeren har slået det til.
    static func refreshOnLaunch() {
        guard isEnabled else { return }
        UIApplication.shared.registerForRemoteNotifications()
        // Gem abonnementerne igen, så ændret notifikationstekst (fx nyt app-navn) slår igennem.
        Task {
            try? await save(subscription(id: privateSubID), in: container.privateCloudDatabase)
            try? await save(subscription(id: sharedSubID), in: container.sharedCloudDatabase)
        }
    }

    private static func subscription(id: String) -> CKDatabaseSubscription {
        let sub = CKDatabaseSubscription(subscriptionID: id)
        let info = CKSubscription.NotificationInfo()
        info.title = "Vores familie"
        info.alertBody = "Der er kommet noget nyt i familien 💛"
        info.soundName = "default"
        // Lader notifikations-udvidelsen omskrive teksten til "Sheila har tilføjet …".
        info.shouldSendMutableContent = true
        sub.notificationInfo = info
        return sub
    }

    private static func save(_ sub: CKSubscription, in db: CKDatabase) async throws {
        _ = try await db.modifySubscriptions(saving: [sub], deleting: [])
    }
}

// Vis ikke familie-notifikationer mens appen er åben — så får man heller ikke besked
// om det man lige selv har lagt op. Månedlige påmindelser vises dog altid.
// Skal køre på hovedtråden: UIKit tager et snapshot af appen, når et tryk er behandlet (fra
// låseskærmen), og det må kun ske derfra — ellers afbrydes appen med en assertion.
@MainActor
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        // Påmindelser vises (og gemmes til klokken på Hjem); nyt fra familien gemmes af udvidelsen.
        if Reminders.isReminder(notification.request.identifier) {
            NotificationInbox.record(notification.request, date: notification.date)
            return [.banner, .sound]
        }
        return []
    }

    /// Tryk på en interview-påmindelse: åbn interviewet for barnet med den rigtige alder.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        if let childId = info["interviewChild"] as? String, let age = info["interviewAge"] as? Int {
            // Gemmes også, hvis appen lige er startet og hovedskærmen ikke lytter endnu.
            DeepLink.pendingInterview = DeepLink.Interview(childId: childId, age: age)
            NotificationCenter.default.post(name: .openInterview, object: nil)
        } else if let childId = info["promptChild"] as? String, let text = info["promptText"] as? String {
            // Ugens spørgsmål: åbn dagbogen med spørgsmålet som overskrift.
            DeepLink.pendingPrompt = DeepLink.Prompt(childId: childId, text: text)
            NotificationCenter.default.post(name: .openDiaryPrompt, object: nil)
        } else if !Reminders.isReminder(response.notification.request.identifier) {
            // Nyt fra familien: udvidelsen har gemt, hvad det handler om — åbn netop den.
            let log = NotificationLog.load()
            let entry = (info["logEntryId"] as? String).flatMap { id in log.first { $0.id == id } } ?? log.first
            if let entry {
                DeepLink.pendingEntry = entry
                NotificationCenter.default.post(name: .openNotificationTarget, object: entry)
            }
        }
        if Reminders.isReminder(response.notification.request.identifier) {
            NotificationInbox.record(response.notification.request, date: response.notification.date)
        }
    }
}

extension Notification.Name {
    static let openInterview = Notification.Name("mindebog.openInterview")
    static let openDiaryPrompt = Notification.Name("mindebog.openDiaryPrompt")
}

@MainActor
enum DeepLink {
    struct Interview: Equatable { let childId: String; let age: Int }
    static var pendingInterview: Interview?
    struct Prompt: Equatable { let childId: String; let text: String }
    static var pendingPrompt: Prompt?
    /// Tryk på en notifikation om nyt i familien, før hovedskærmen lytter.
    static var pendingEntry: NotificationLogEntry?
}
