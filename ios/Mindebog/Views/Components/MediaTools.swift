import SwiftUI
import PhotosUI
import AVFoundation
import AVKit
import CoreTransferable
import UniformTypeIdentifiers

// Video og lydnoter til højdepunkter.
//  • Video vælges i Fotos, komprimeres til medium kvalitet (sparer iCloud-plads), maks 3 min.
//  • Lydnoter optages direkte i appen (m4a), maks 5 min.
// Filerne hentes først fra iCloud, når man trykker afspil.

enum MediaLimits {
    static let maxVideoSeconds: Double = 180
    static let maxAudioSeconds: Double = 300
}

/// Ændring af et medie ved gem: behold, fjern eller sæt ny fil.
enum MediaChange {
    case keep
    case remove
    case set(URL, Double)    // fil + varighed i sekunder
}

enum MediaFiles {
    /// Egen mappe til medier (optagelser, komprimerede videoer, hentede filer).
    static let dir: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Media", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func newURL(_ ext: String) -> URL { dir.appendingPathComponent(UUID().uuidString + "." + ext) }

    static func duration(of url: URL) async -> Double {
        let asset = AVURLAsset(url: url)
        let time = (try? await asset.load(.duration)) ?? .zero
        return time.seconds.isFinite ? time.seconds : 0
    }

    /// "0:42", "2:05"
    static func format(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// Komprimerer en video til MP4 i medium kvalitet (API der virker fra iOS 17).
    static func compressVideo(_ source: URL) async throws -> URL {
        let asset = AVURLAsset(url: source)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let out = newURL("mp4")
        export.outputURL = out
        export.outputFileType = .mp4
        export.shouldOptimizeForNetworkUse = true
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            export.exportAsynchronously { continuation.resume() }
        }
        guard export.status == .completed else {
            throw export.error ?? CocoaError(.fileWriteUnknown)
        }
        return out
    }
}

/// Video fra Fotos som fil (PhotosPicker → kopi i vores mappe).
struct PickedMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let copy = MediaFiles.newURL(received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedMovie(url: copy)
        }
    }
}

// MARK: - Lydoptagelse

@MainActor
final class AudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isRecording = false
    @Published var elapsed: Double = 0
    @Published var permissionDenied = false
    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private(set) var url: URL?

    func start() async {
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else { permissionDenied = true; return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            let url = MediaFiles.newURL("m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            recorder.record(forDuration: MediaLimits.maxAudioSeconds)
            self.recorder = recorder
            self.url = url
            isRecording = true
            elapsed = 0
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.elapsed = self?.recorder?.currentTime ?? 0 }
            }
        } catch {
            isRecording = false
        }
    }

    /// Stopper og returnerer (fil, varighed).
    func stop() -> (URL, Double)? {
        let duration = recorder?.currentTime ?? elapsed
        recorder?.stop()
        timer?.invalidate()
        isRecording = false
        guard let url, duration > 0.5 else { return nil }
        return (url, duration)
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            self.isRecording = false
            self.timer?.invalidate()
        }
    }
}

// MARK: - Afspilning

@MainActor
final class AudioPlayback: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    private var player: AVAudioPlayer?

    func stop() {
        player?.stop()
        isPlaying = false
    }

    func toggle(url: URL) {
        if isPlaying { stop(); return }
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        player = try? AVAudioPlayer(contentsOf: url)
        player?.delegate = self
        isPlaying = player?.play() ?? false
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.isPlaying = false }
    }
}

/// Fuldskærms-videoafspiller.
struct VideoPlayerScreen: View, Identifiable {
    let url: URL
    var id: URL { url }
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            VideoPlayer(player: AVPlayer(url: url))
                .ignoresSafeArea()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.5))
                    .padding(16)
            }
            .accessibilityLabel("Luk")
        }
    }
}

// MARK: - Formular-felt

/// "Video og lyd" i formularen: vælg video, optag lydnote, fjern.
struct MediaField: View {
    @Binding var video: MediaChange
    @Binding var audio: MediaChange
    /// Varighed af eksisterende medier (ved redigering), så vi kan vise dem.
    var existingVideo: Double?
    var existingAudio: Double?
    /// Skjul den ene del, fx kun video til et videobrev eller kun lyd til en tradition.
    var showVideo = true
    var showAudio = true
    var videoLabel = "Vælg video"
    var audioLabel = "Optag lydnote"

    @EnvironmentObject private var state: AppState
    @State private var videoItem: PhotosPickerItem?
    @State private var paywall: PaywallReason?
    @State private var working = false
    @State private var recording = false
    @State private var message: String?
    @StateObject private var recorder = AudioRecorder()
    @StateObject private var playback = AudioPlayback()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Video
            if showVideo {
            HStack {
                if let d = videoDuration {
                    Label("Video \(MediaFiles.format(d))", systemImage: "play.rectangle")
                    Spacer()
                    Button("Fjern", role: .destructive) { video = .remove }
                } else if state.isPremium {
                    if working {
                        Label("Forbereder video…", systemImage: "hourglass")
                    } else {
                        if VideoRecorder.isAvailable {
                            Button { recording = true } label: {
                                Label("Optag video", systemImage: "video")
                            }
                        }
                        Spacer()
                        PhotosPicker(selection: $videoItem, matching: .videos) {
                            Label(VideoRecorder.isAvailable ? "Fra Fotos" : videoLabel, systemImage: "photo.on.rectangle")
                        }
                    }
                } else {
                    // Video er Premium: knappen viser betalingsskærmen.
                    Button { paywall = .video } label: {
                        HStack {
                            Label(videoLabel, systemImage: "video.badge.plus")
                            Image(systemName: "lock.fill").font(.caption2)
                        }
                    }
                }
            }
            .buttonStyle(.borderless)
            }

            // Lydnote
            if showAudio {
            HStack {
                if recorder.isRecording {
                    Button { if let r = recorder.stop() { audio = .set(r.0, r.1) } } label: {
                        Label("Stop · \(MediaFiles.format(recorder.elapsed))", systemImage: "stop.circle.fill")
                            .foregroundStyle(Theme.rose)
                    }
                } else if let d = audioDuration {
                    if case .set(let url, _) = audio {
                        Button { playback.toggle(url: url) } label: {
                            Label(playback.isPlaying ? "Stop" : "Lydnote \(MediaFiles.format(d))",
                                  systemImage: playback.isPlaying ? "stop.fill" : "play.fill")
                        }
                    } else {
                        Label("Lydnote \(MediaFiles.format(d))", systemImage: "waveform")
                    }
                    Spacer()
                    Button("Fjern", role: .destructive) { audio = .remove }
                } else {
                    Button { Task { await recorder.start() } } label: {
                        Label(audioLabel, systemImage: "mic")
                    }
                }
            }
            .buttonStyle(.borderless)
            }

            if recorder.permissionDenied {
                Text("Giv adgang til mikrofonen i Indstillinger → Vores familie.")
                    .font(.footnote).foregroundStyle(Theme.rose)
            }
            if let message {
                Text(message).font(.footnote).foregroundStyle(Theme.rose)
            }
        }
        .sheet(item: $paywall) { PaywallView(reason: $0) }
        .fullScreenCover(isPresented: $recording) {
            VideoRecorder { url in
                recording = false
                if let url { Task { await prepareVideo(url) } }
            }
            .ignoresSafeArea()
        }
        .onChange(of: videoItem) { _, item in
            guard let item else { return }
            Task { await importVideo(item) }
        }
    }

    private var videoDuration: Double? {
        switch video {
        case .keep: return existingVideo
        case .remove: return nil
        case .set(_, let d): return d
        }
    }

    private var audioDuration: Double? {
        switch audio {
        case .keep: return existingAudio
        case .remove: return nil
        case .set(_, let d): return d
        }
    }

    private func importVideo(_ item: PhotosPickerItem) async {
        working = true
        message = nil
        defer { working = false; videoItem = nil }
        guard let movie = try? await item.loadTransferable(type: PickedMovie.self) else {
            message = "Kunne ikke hente videoen."
            return
        }
        await prepareVideo(movie.url)
    }

    /// Fælles for video fra Fotos og video optaget med kameraet: tjek længde og komprimér.
    private func prepareVideo(_ url: URL) async {
        working = true
        message = nil
        defer { working = false }
        let seconds = await MediaFiles.duration(of: url)
        guard seconds <= MediaLimits.maxVideoSeconds else {
            message = "Videoen er for lang (maks \(Int(MediaLimits.maxVideoSeconds / 60)) min). Klip den til i Fotos først."
            try? FileManager.default.removeItem(at: url)
            return
        }
        do {
            let compressed = try await MediaFiles.compressVideo(url)
            try? FileManager.default.removeItem(at: url)
            video = .set(compressed, seconds)
        } catch {
            message = "Kunne ikke forberede videoen."
        }
    }
}

// MARK: - Optag video med kameraet

/// Kameraet i videotilstand (maks 3 min). Optagelsen kopieres til vores mediemappe;
/// `nil` betyder annulleret.
struct VideoRecorder: UIViewControllerRepresentable {
    var onFinish: (URL?) -> Void

    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
            && (UIImagePickerController.availableMediaTypes(for: .camera) ?? []).contains(UTType.movie.identifier)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.movie.identifier]
        picker.cameraCaptureMode = .video
        picker.videoMaximumDuration = MediaLimits.maxVideoSeconds
        picker.videoQuality = .typeHigh          // komprimeres bagefter som videoer fra Fotos
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (URL?) -> Void
        init(onFinish: @escaping (URL?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard let source = info[.mediaURL] as? URL else { onFinish(nil); return }
            // Systemet sletter sin midlertidige fil — kopiér den, før vi svarer.
            let copy = MediaFiles.newURL(source.pathExtension.isEmpty ? "mov" : source.pathExtension)
            let ok = (try? FileManager.default.copyItem(at: source, to: copy)) != nil
            onFinish(ok ? copy : nil)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onFinish(nil) }
    }
}
