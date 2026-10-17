import SwiftUI
import VisionKit

/// Kamerascanner til børnetegninger: iOS finder selv papirets kanter, retter perspektivet
/// og beskærer. Flere sider kan scannes i træk; hver side bliver ét billede.
struct DocumentScanner: UIViewControllerRepresentable {
    var onFinish: ([Data]) -> Void

    static var isAvailable: Bool { VNDocumentCameraViewController.isSupported }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: ([Data]) -> Void
        init(onFinish: @escaping ([Data]) -> Void) { self.onFinish = onFinish }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            var out: [Data] = []
            for i in 0..<scan.pageCount {
                if let jpeg = scan.imageOfPage(at: i).jpegData(compressionQuality: 0.9) {
                    out.append(ImageTools.resized(jpeg) ?? jpeg)
                }
            }
            if !out.isEmpty { Haptics.light() }
            controller.dismiss(animated: true) { self.onFinish(out) }
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            controller.dismiss(animated: true) { self.onFinish([]) }
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            controller.dismiss(animated: true) { self.onFinish([]) }
        }
    }
}
