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
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        Reminders.isReminder(notification.request.identifier) ? [.banner, .sound] : []
    }
}
