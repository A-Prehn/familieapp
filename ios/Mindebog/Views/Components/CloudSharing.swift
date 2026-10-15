import UIKit
import CloudKit

// Apples eget delingsark for iCloud-deling (som i Noter/Fotos): invitér via Beskeder/mail,
// se og fjern deltagere, vælg "kun inviterede" eller "alle med linket", stop deling.
@MainActor
enum CloudSharing {
    static func present(share: CKShare, container: CKContainer, onChange: @escaping () -> Void) {
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowPrivate, .allowPublic, .allowReadWrite]
        let delegate = Delegate(onChange: onChange)
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
        let onChange: () -> Void
        init(onChange: @escaping () -> Void) { self.onChange = onChange }

        func itemTitle(for csc: UICloudSharingController) -> String? { "Vores familie" }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            onChange()
        }
        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) { onChange() }
        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) { onChange() }
    }
}
