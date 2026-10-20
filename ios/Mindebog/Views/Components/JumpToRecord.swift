import SwiftUI

// Fra en notifikation eller "Seneste i familien" skal listen ikke bare åbnes — den skal scrolle
// hen til netop det opslag. Rækkerne har `.id(record-id)`, og listens ScrollView får
// `.jumpsToPendingRecord()`: den prøver i et par sekunder (mens data hentes) at scrolle til
// det ønskede id og glemmer det så. Ønsket ligger i et delt objekt, så en liste, der allerede
// er på skærmen (fx Familie-fanen), også reagerer.
@MainActor
final class JumpRequest: ObservableObject {
    static let shared = JumpRequest()
    @Published var recordId: String?
}

private struct JumpToPendingRecord: ViewModifier {
    @ObservedObject private var jump = JumpRequest.shared

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content.task(id: jump.recordId) {
                guard let id = jump.recordId else { return }
                for _ in 0..<12 {
                    withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(id, anchor: .center) }
                    try? await Task.sleep(for: .milliseconds(250))
                    if jump.recordId != id { return }   // en anden navigation har overtaget
                }
                jump.recordId = nil
            }
        }
    }
}

extension View {
    func jumpsToPendingRecord() -> some View { modifier(JumpToPendingRecord()) }
}
