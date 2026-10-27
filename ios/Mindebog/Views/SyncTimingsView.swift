import SwiftUI

/// Mere → "iCloud-tider (test)": hvad hvert iCloud-kald har kostet i denne kørsel (#61).
/// Kun i Debug og TestFlight. Ingen persondata — kun kaldets navn, tid og antal.
struct SyncTimingsView: View {
    @State private var summary = SyncLog.summary
    @State private var recent = SyncLog.recent
    @State private var showAll = false

    var body: some View {
        List {
            Group {
            Section {
                if summary.isEmpty {
                    Text("Ingen målinger endnu. Brug appen lidt, og kom tilbage.").font(.footnote).foregroundStyle(Theme.muted)
                }
                ForEach(summary) { s in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(s.name).font(.subheadline.weight(.medium))
                            Spacer()
                            Text(Self.ms(s.total)).font(.subheadline.monospacedDigit())
                        }
                        Text("\(s.calls) kald · gns. \(Self.ms(s.average)) · største \(Self.ms(s.max))\(s.failures > 0 ? " · \(s.failures) fejl" : "")")
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                }
            } header: {
                Text("Samlet tid pr. kald")
            } footer: {
                Text("Sorteret efter, hvor meget tid de har kostet i alt siden appen blev åbnet.")
            }

            Section {
                ForEach(showAll ? recent : Array(recent.prefix(30))) { e in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.name).font(.subheadline)
                            Text(e.at.formatted(date: .omitted, time: .standard)).font(.caption).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Text(e.count > 0 ? "\(e.count) stk" : "").font(.caption).foregroundStyle(Theme.muted)
                        Text(Self.ms(e.seconds)).font(.subheadline.monospacedDigit())
                            .foregroundStyle(e.failed ? Theme.rose : (e.seconds > 1 ? Theme.rose : Theme.text))
                    }
                }
                if !showAll && recent.count > 30 {
                    Button("Vis alle \(recent.count)") { showAll = true }
                }
            } header: {
                Text("Seneste kald")
            }

            Section {
                Button("Opdatér") { summary = SyncLog.summary; recent = SyncLog.recent }
                Button("Ryd målinger", role: .destructive) { SyncLog.clear(); summary = []; recent = [] }
                ShareLink(item: report) { Label("Del som tekst", systemImage: "square.and.arrow.up") }
            }
            }.listRowBackground(Theme.card)
        }
        .themedList()
        .navigationTitle("iCloud-tider")
        .navigationBarTitleDisplayMode(.inline)
    }

    private static func ms(_ seconds: Double) -> String {
        seconds >= 10 ? String(format: "%.1f s", seconds) : "\(Int((seconds * 1000).rounded())) ms"
    }

    /// Til at sende tallene videre (fx ind i issue #61).
    private var report: String {
        var lines = ["iCloud-tider \(Date().formatted(date: .abbreviated, time: .shortened))", ""]
        for s in summary {
            lines.append("\(s.name): \(s.calls) kald, i alt \(Self.ms(s.total)), gns. \(Self.ms(s.average)), største \(Self.ms(s.max))\(s.failures > 0 ? ", \(s.failures) fejl" : "")")
        }
        return lines.joined(separator: "\n")
    }
}
