import UIKit
import CloudKit
import UserNotifications

extension Notification.Name {
    static let cloudKitShareAccepted = Notification.Name("mindebog.cloudKitShareAccepted")
}

/// En invitation, der blev accepteret, før appen var klar (koldstart fra et delelink).
/// AppState samler den op, når brugeren og familierne er hentet.
/// Kører appen som vært for de automatiske tests? Så rører den hverken iCloud, notifikationer eller widgets —
/// testappen er ikke signeret, og iCloud stopper den med det samme.
let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

@MainActor
enum PendingShare {
    static var zoneName: String?
}

// Nødvendig for at modtage CloudKit-delelinks (iOS kalder scene-delegaten).
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    private let notificationDelegate = NotificationDelegate()

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        if isRunningTests { return true }
        UNUserNotificationCenter.current().delegate = notificationDelegate
        Task { @MainActor in NotificationManager.refreshOnLaunch() }
        return true
    }

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    /// Appen kørte ikke: iOS starter den med invitationen i connectionOptions
    /// (så kaldes userDidAcceptCloudKitShareWith IKKE).
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata { accept(metadata) }
    }

    /// Appen kørte allerede (eller lå i baggrunden), da man trykkede på linket.
    func windowScene(_ windowScene: UIWindowScene,
                     userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        accept(cloudKitShareMetadata)
    }

    private func accept(_ metadata: CKShare.Metadata) {
        let container = CKContainer(identifier: metadata.containerIdentifier)
        let zoneName = metadata.share.recordID.zoneID.zoneName
        Task {
            // Er delingen allerede accepteret (fx partneren trykker igen), fejler accept — det er fint.
            _ = try? await container.accept(metadata)
            await MainActor.run {
                PendingShare.zoneName = zoneName
                NotificationCenter.default.post(name: .cloudKitShareAccepted, object: zoneName)
            }
        }
    }
}
