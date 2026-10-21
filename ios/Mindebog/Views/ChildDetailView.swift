import SwiftUI

struct ChildDetailView: View {
    @EnvironmentObject var state: AppState
    @State private var child: Child
    @State private var editing = false
    @State private var makingBook = false
    @State private var bookShare: ShareSheet?
    @State private var bookError: String?
    @State private var paywall: PaywallReason?
    @State private var canShareChild = false
    @State private var showAccess = false

    init(child: Child) {
        _child = State(initialValue: child)
    }

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header

                NavigationLink { HighlightsView(child: child) } label: {
                    tile("Højdepunkter", "star", Theme.rose, wide: true)
                }
                .buttonStyle(.plain)

                LazyVGrid(columns: columns, spacing: 10) {
                    NavigationLink { DiaryView(child: child) } label: {
                        // Blød bindestreg: lange sammensatte ord deles pænt ("Svangerskabs-/dagbog").
                        tile(child.onTheWay ? "Svangerskabs\u{00AD}dagbog" : "Dagbog", "book", Theme.neutralDark)
                    }
                    NavigationLink { GalleryView(child: child, kind: .belly) } label: {
                        // Billeder af maven der vokser — bladet signalerer vækst.
                        tile("Maven måned for måned", "leaf", Theme.green)
                    }
                    NavigationLink { GalleryView(child: child, kind: .monthly) } label: {
                        tile("Måned for måned", "photo.on.rectangle", Theme.tint)
                    }
                    NavigationLink { AboutMeView(child: child) } label: {
                        tile("Om dig", "message", Theme.rose)
                    }
                    NavigationLink { MilestonesView(child: child) } label: {
                        tile("Milepæle", "flag", Theme.green)
                    }
                    NavigationLink { LettersView(child: child) } label: {
                        tile("Breve til dig", "envelope", Theme.neutralDark)
                    }
                    // Vækst, vaccinationer, interview, stemme og tegninger giver først mening, når barnet er født.
                    if !child.onTheWay {
                        NavigationLink { GrowthView(child: child) } label: {
                            tile("Vækst", "chart.line.uptrend.xyaxis", Theme.tint)
                        }
                        NavigationLink { VaccinesView(child: child) } label: {
                            tile("Vaccinationer", "syringe", Theme.green)
                        }
                        NavigationLink { InterviewView(child: child) } label: {
                            tile("Det årlige interview", "bubble.left.and.text.bubble.right", Theme.rose)
                        }
                        NavigationLink { VoiceArchiveView(child: child) } label: {
                            tile("Stemmearkiv", "waveform", Theme.neutralDark)
                        }
                        NavigationLink { GalleryView(child: child, kind: .drawings) } label: {
                            tile("Tegninger", "paintpalette", Theme.tint)
                        }
                        NavigationLink { BirthdayPhotosView(child: child) } label: {
                            tile("Fødselsdage", "gift", Theme.rose)
                        }
                        if child.birthDate != nil {
                            NavigationLink { YearInReviewView(child: child, spec: YearSpec.current(for: child) ?? .calendar(Calendar.current.component(.year, from: Date()))) } label: {
                                tile("Året der gik", "sparkles.rectangle.stack", Theme.green)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(child.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if state.canEdit {
                        Button { editing = true } label: { Label("Redigér", systemImage: "pencil") }
                    }
                    Menu {
                        Button { Task { await makeBook(forPrint: false) } } label: {
                            Label("Til skærm og hjemmeprint", systemImage: "doc.richtext")
                        }
                        Button { Task { await makeBook(forPrint: true) } } label: {
                            Label("Til trykkeri (indbundet bog)", systemImage: "book")
                        }
                    } label: {
                        Label("Lav mindebog (PDF)", systemImage: "book.closed")
                    }
                    if canShareChild {
                        Button { showAccess = true } label: {
                            Label(child.ownZone == nil ? "Forælder uden for familien" : "Delt med forælder uden for familien",
                                  systemImage: "person.2.badge.key")
                        }
                    }
                } label: {
                    if makingBook { ProgressView() } else { Image(systemName: "ellipsis.circle") }
                }
                .disabled(makingBook)
            }
        }
        .sheet(item: $bookShare) { $0 }
        .sheet(item: $paywall) { PaywallView(reason: $0) }
        .saveErrorAlert($bookError)
        .sheet(isPresented: $editing) {
            NewChildView(editing: child) { updated in child = updated }
        }
        .sheet(isPresented: $showAccess, onDismiss: { Task { await refreshChild() } }) {
            NavigationStack { ChildAccessView(child: child) }
        }
        .task {
            // Kun familiens ejer kan dele et barn (zonen ligger i ejerens iCloud).
            if !child.isSharedOnly, let cloud = state.store as? CloudKitStore {
                canShareChild = await cloud.isShareOwner(familyId: child.familyId)
            }
        }
    }

    private func refreshChild() async {
        if let fresh = (try? await state.store.children(familyId: child.familyId))?.first(where: { $0.id == child.id }) {
            child = fresh
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            HStack(spacing: 16) {
                ChildAvatar(child: child, size: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text(child.name).font(.serifTitle(22))
                    Text(subtitle).font(.subheadline).foregroundStyle(Theme.muted)
                }
                Spacer()
            }
            if child.onTheWay, let due = child.dueDate {
                let days = max(0, Calendar.current.dateComponents([.day], from: Date(), to: due).day ?? 0)
                HStack(spacing: 20) {
                    Text("\(days)").font(.system(size: 44, weight: .medium, design: .serif))
                        .foregroundStyle(Theme.neutralDark)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("dage til termin").font(.footnote).foregroundStyle(Theme.neutral)
                        Text("Termin: \(Fmt.long(due))").font(.footnote).foregroundStyle(Theme.neutralDark)
                    }
                    Spacer()
                }
                .padding(16)
                .background(Theme.bgDark)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(16)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.sep))
    }

    /// Bygger mindebogen som PDF og åbner del-arket (Gem i Filer, Mail, Udskriv …).
    private func makeBook(forPrint: Bool) async {
        guard state.isPremium else { paywall = .book; return }
        makingBook = true
        defer { makingBook = false }
        let familyName = (try? await state.store.families(for: state.user?.id ?? ""))?
            .first { $0.id == state.familyId }?.name ?? "Vores familie"
        do {
            let url = try await BookExporter.make(child: child, store: state.store, familyName: familyName, forPrint: forPrint)
            bookShare = ShareSheet(url: url)
        } catch {
            bookError = "Kunne ikke lave mindebogen: \(error.localizedDescription)"
        }
    }

    private var subtitle: String {
        if child.onTheWay { return "På vej" }
        guard let birth = child.birthDate else { return "" }
        let months = Calendar.current.dateComponents([.month], from: birth, to: Date()).month ?? 0
        return months < 24 ? "\(max(0, months)) mdr." : "\(months / 12) år"
    }

    private func tile(_ title: String, _ symbol: String, _ color: Color, wide: Bool = false) -> some View {
        HStack(spacing: 12) {
            Circle().fill(color.opacity(0.15)).frame(width: 38, height: 38)
                .overlay(Image(systemName: symbol).font(.system(size: 17)).foregroundStyle(color))
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.leading)
            if wide { Spacer() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.sep))
    }
}
