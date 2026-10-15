import UIKit
import CloudKit

extension Notification.Name {
    static let cloudKitShareAccepted = Notification.Name("mindebog.cloudKitShareAccepted")
}

// Nødvendig for at modtage CloudKit-delelinks (iOS kalder scene-delegaten).
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene,
                     userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        let container = CKContainer(identifier: cloudKitShareMetadata.containerIdentifier)
        let zoneName = cloudKitShareMetadata.share.recordID.zoneID.zoneName
        Task {
            _ = try? await container.accept(cloudKitShareMetadata)
            await MainActor.run {
                NotificationCenter.default.post(name: .cloudKitShareAccepted, object: zoneName)
            }
        }
    }
}
