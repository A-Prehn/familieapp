import SwiftUI
import AVKit
import AVFoundation

/// Afspiller interview-svar ét efter ét: spørgsmålet vises stort, og svaret afspilles —
/// video, lyd eller tekst. Går selv videre til næste svar, når det forrige er færdigt.
/// Bruges både til "alle svar for én alder" og "ét spørgsmål gennem årene".
struct InterviewPlaybackView: View, Identifiable {
    let id = UUID()
    let child: Child
    let title: String
    let answers: [InterviewAnswer]
    /// "question": vis spørgsmålet som overskrift (én alder). "age": vis alderen (gennem årene).
    var headline: Headline = .question

    enum Headline { case question, age }

    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var player: AVPlayer?
    @State private var isAudio = false
    @State private var loading = false
    @State private var paused = false
    @State private var endObserver: Any?
    @State private var textTimer: Task<Void, Never>?

    private var current: InterviewAnswer? { answers.indices.contains(index) ? answers[index] : nil }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 18) {
                // Top: titel, position og luk
                HStack {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.75))
                    Spacer()
                    Text("\(index + 1) / \(answers.count)").font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.6))
                    Button { close() } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 28))
                            .symbolRenderingMode(.palette).foregroundStyle(.white, .white.opacity(0.2))
                    }
                    .accessibilityLabel("Luk")
                }
                .padding(.horizontal, 20)

                if let a = current {
                    VStack(spacing: 8) {
                        Text(headline == .question ? Constants.interviewQuestion(a.question)
                                                   : (a.age == 1 ? "1 år" : "\(a.age) år"))
                            .font(.serifTitle(26))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                        Text(headline == .question ? "\(child.name), \(a.age == 1 ? "1 år" : "\(a.age) år")"
                                                   : Constants.interviewQuestion(a.question))
                            .font(.subheadline).foregroundStyle(.white.opacity(0.65))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 24)

                    // Selve svaret
                    ZStack {
                        if loading {
                            ProgressView().tint(.white)
                        } else if let player, !isAudio {
                            VideoPlayer(player: player)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        } else if isAudio {
                            Image(systemName: paused ? "waveform" : "waveform")
                                .font(.system(size: 90, weight: .light))
                                .foregroundStyle(Theme.rose)
                                .symbolEffect(.variableColor.iterative, isActive: !paused)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 16)

                    if !a.text.isEmpty {
                        Text("“\(a.text)”")
                            .font(.system(size: 20, design: .serif).italic())
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                    }
                }

                // Styring
                HStack(spacing: 44) {
                    Button { go(index - 1) } label: { Image(systemName: "backward.fill") }
                        .disabled(index == 0)
                    Button { togglePause() } label: {
                        Image(systemName: paused ? "play.circle.fill" : "pause.circle.fill").font(.system(size: 54))
                    }
                    Button { go(index + 1) } label: { Image(systemName: "forward.fill") }
                        .disabled(index >= answers.count - 1)
                }
                .font(.system(size: 26))
                .foregroundStyle(.white)
                .padding(.bottom, 12)
            }
            .padding(.top, 8)
        }
        .task { await start() }
        .onDisappear { stopCurrent() }
    }

    // MARK: Afspilning

    private func start() async {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        await load(index)
    }

    private func go(_ newIndex: Int) {
        guard answers.indices.contains(newIndex) else { return }
        Haptics.light()
        stopCurrent()
        index = newIndex
        paused = false
        Task { await load(newIndex) }
    }

    private func next() {
        if index < answers.count - 1 { go(index + 1) } else { paused = true }
    }

    private func load(_ i: Int) async {
        guard answers.indices.contains(i) else { return }
        let a = answers[i]
        if a.videoDuration != nil || a.audioDuration != nil {
            loading = true
            let media = try? await state.store.interviewMedia(childId: child.id, id: a.id)
            loading = false
            guard i == index else { return }   // brugeren har sprunget videre imens
            if let url = media?.video ?? media?.audio {
                isAudio = media?.video == nil
                let item = AVPlayerItem(url: url)
                let p = AVPlayer(playerItem: item)
                endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                                                     object: item, queue: .main) { _ in
                    Task { @MainActor in next() }
                }
                player = p
                p.play()
                return
            }
        }
        // Kun tekst (eller medie kunne ikke hentes): vis svaret i et par sekunder.
        isAudio = false
        player = nil
        let seconds = max(4, min(10, Double(a.text.count) / 15))
        textTimer = Task {
            try? await Task.sleep(for: .seconds(seconds))
            if !Task.isCancelled, !paused, i == index { next() }
        }
    }

    private func togglePause() {
        paused.toggle()
        if let player {
            paused ? player.pause() : player.play()
        } else if !paused {
            // Tekstsvar: fortsæt til næste.
            next()
        } else {
            textTimer?.cancel()
        }
    }

    private func stopCurrent() {
        player?.pause()
        player = nil
        textTimer?.cancel()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
    }

    private func close() {
        stopCurrent()
        dismiss()
    }
}
