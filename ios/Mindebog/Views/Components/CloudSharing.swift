import UIKit
import CloudKit

// Apples eget delingsark for iCloud-deling (som i Noter/Fotos): invitér via Beskeder/mail,
// se og fjern deltagere, vælg "kun inviterede" eller "alle med linket", stop deling.
@MainActor
enum CloudSharing {
    /// Hvad nye inviterede får: kan redigere (partner) eller kun se (bedsteforældre).
    enum Invite { case edit, view, all }

    static func present(share: CKShare, container: CKContainer, invite: Invite = .all,
                        title: String = "Vores familie", onChange: @escaping () -> Void) {
        let controller = UICloudSharingController(share: share, container: container)
        // Kun den valgte tilladelse er mulig — så kan man ikke komme til at give forkert adgang.
        switch invite {
        case .edit: controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        case .view: controller.availablePermissions = [.allowPrivate, .allowReadOnly]
        case .all: controller.availablePermissions = [.allowPrivate, .allowPublic, .allowReadWrite, .allowReadOnly]
        }
        let delegate = Delegate(title: title, onChange: onChange)
        controller.delegate = delegate
        // Delegaten er weak i UIKit — hold den i live så længe arket vises.
        objc_setAssociatedObject(controller, &Delegate.key, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        topViewController()?.present(controller, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    private final class Delegate: NSObject, UICloudSharingControllerDelegate {
        static var key = 0
        let title: String
        let onChange: () -> Void
        init(title: String, onChange: @escaping () -> Void) { self.title = title; self.onChange = onChange }

        func itemTitle(for csc: UICloudSharingController) -> String? { title }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            onChange()
        }
        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) { onChange() }
        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) { onChange() }
    }
}
