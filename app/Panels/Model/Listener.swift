import AVFoundation
import MediaPlayer
import Observation
import UIKit

/// Listen mode: reads a book aloud page after page, with the screen locked (gym, train).
/// Plays the pre-recorded narration (make_narration.py) when a page has it, else the on-device voice.
/// Lock-screen and headphone controls work.
@Observable
final class Listener: NSObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    static let shared = Listener()

    /// One spoken chunk of a page; `panel` is the panel being read (nil for title and takeaway).
    private struct Segment {
        var text = ""
        let panel: Int?
        var audio: URL? = nil
    }

    private(set) var book: Book?
    private(set) var pageIndex = 0
    private(set) var panel: Int?
    private(set) var isPlaying = false
    /// 0...1 through the current page.
    private(set) var pageProgress = 0.0

    var page: Page? { book.flatMap { $0.pages.indices.contains(pageIndex) ? $0.pages[pageIndex] : nil } }
    var isActive: Bool { book != nil }

    @ObservationIgnored private let synth = AVSpeechSynthesizer()
    @ObservationIgnored private var segments: [Segment] = []
    @ObservationIgnored private var segmentIndex = 0
    @ObservationIgnored private var current: AVSpeechUtterance?
    @ObservationIgnored private var player: AVAudioPlayer?
    /// Bumped whenever playback restarts, so callbacks from a stopped clip are ignored.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var artwork: MPMediaItemArtwork?
    @ObservationIgnored private var contentURL: URL?

    static let speeds: [Double] = [0.8, 1, 1.2, 1.4, 1.7]

    var speed: Double {
        get { access(keyPath: \.speed); return UserDefaults.standard.object(forKey: "listen.speed") as? Double ?? 1 }
        set { withMutation(keyPath: \.speed) { UserDefaults.standard.set(newValue, forKey: "listen.speed") } }
    }

    var voiceId: String? {
        get { access(keyPath: \.voiceId); return UserDefaults.standard.string(forKey: "listen.voice") }
        set { withMutation(keyPath: \.voiceId) { UserDefaults.standard.set(newValue, forKey: "listen.voice") } }
    }

    override private init() {
        super.init()
        synth.delegate = self
        setUpRemoteCommands()
    }

    // MARK: Voices

    /// English voices, best quality first.
    static var voices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") && !$0.voiceTraits.contains(.isNoveltyVoice) }
            .sorted { a, b in
                if a.quality != b.quality { return a.quality.rawValue > b.quality.rawValue }
                if (a.language == "en-US") != (b.language == "en-US") { return a.language == "en-US" }
                return a.name < b.name
            }
    }

    private var voice: AVSpeechSynthesisVoice? {
        if let id = voiceId, let v = AVSpeechSynthesisVoice(identifier: id) { return v }
        return Self.voices.first
    }

    // MARK: Playback

    func start(_ book: Book, at index: Int, store: ContentStore) {
        contentURL = store.contentURL
        stopSpeech()
        self.book = book
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        load(page: index)
        isPlaying = true
        speakCurrent()
    }

    func toggle() { isPlaying ? pause() : resume() }

    func pause() {
        guard isActive else { return }
        player?.pause()
        if synth.isSpeaking { synth.pauseSpeaking(at: .word) }
        isPlaying = false
        updateNowPlaying()
    }

    func resume() {
        guard isActive else { return }
        isPlaying = true
        if let player, !player.isPlaying, player.currentTime > 0 {
            player.play()
        } else if synth.isPaused {
            synth.continueSpeaking()
        } else {
            speakCurrent()
        }
        updateNowPlaying()
    }

    func next() {
        guard let book, pageIndex + 1 < book.pages.count else { return }
        jump(to: pageIndex + 1)
    }

    func previous() {
        // Like a music player: back to the start of the page first, then the previous page.
        jump(to: segmentIndex > 1 || pageIndex == 0 ? pageIndex : pageIndex - 1)
    }

    func jump(to index: Int) {
        guard let book, book.pages.indices.contains(index) else { return }
        stopSpeech()
        load(page: index)
        isPlaying = true
        speakCurrent()
    }

    func stop() {
        stopSpeech()
        book = nil
        panel = nil
        isPlaying = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    /// Speed changes apply from the next sentence.
    func setSpeed(_ value: Double) {
        speed = value
        if let player {
            player.rate = Float(value)
        } else if isPlaying {
            restartSegment()
        }
    }

    func setVoice(_ id: String) {
        voiceId = id
        if isPlaying { restartSegment() }
    }

    private func restartSegment() {
        stopSpeech()
        speakCurrent()
    }

    private func stopSpeech() {
        generation += 1
        current = nil
        player?.stop()
        player = nil
        synth.stopSpeaking(at: .immediate)
    }

    /// True when the current book's pages carry recorded narration.
    var isRecorded: Bool { page?.narration?.isEmpty == false }

    private func load(page index: Int) {
        guard let book else { return }
        pageIndex = index
        let page = book.pages[index]
        if let clips = page.narration, !clips.isEmpty, let base = contentURL {
            segments = clips.map { Segment(panel: $0.panel, audio: base.appendingPathComponent($0.audio)) }
        } else {
            segments = Self.segments(for: page, in: book)
        }
        segmentIndex = 0
        panel = nil
        pageProgress = 0
        artwork = nil
        if let url = contentURL?.appendingPathComponent(book.pages[index].thumb), let image = UIImage(contentsOfFile: url.path) {
            artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        updateNowPlaying()
    }

    private func speakCurrent() {
        guard isPlaying, segments.indices.contains(segmentIndex) else { return }
        let segment = segments[segmentIndex]
        panel = segment.panel
        pageProgress = Double(segmentIndex) / Double(max(segments.count, 1))
        if let url = segment.audio, let clip = try? AVAudioPlayer(contentsOf: url) {
            generation += 1
            clip.delegate = self
            clip.enableRate = true
            clip.rate = Float(speed)
            player = clip
            clip.play()
            return
        }
        let utterance = AVSpeechUtterance(string: segment.text)
        utterance.voice = voice
        utterance.rate = Self.rate(for: speed)
        utterance.postUtteranceDelay = segmentIndex == segments.count - 1 ? 0.9 : 0.35
        current = utterance
        synth.speak(utterance)
    }

    /// Maps a 0.8×–1.7× speed onto AVSpeech's non-linear rate scale.
    static func rate(for speed: Double) -> Float {
        let normal = AVSpeechUtteranceDefaultSpeechRate
        let value = speed >= 1 ? normal + Float(speed - 1) * 0.22 : normal - Float(1 - speed) * 0.45
        return min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate, value))
    }

    private func advance() {
        segmentIndex += 1
        if segmentIndex < segments.count {
            speakCurrent()
        } else if let book, pageIndex + 1 < book.pages.count {
            load(page: pageIndex + 1)
            speakCurrent()
        } else {
            // End of the book.
            isPlaying = false
            panel = nil
            pageProgress = 1
            updateNowPlaying()
        }
    }

    // MARK: AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ finished: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            guard finished === self.player else { return }
            let token = self.generation
            self.player = nil
            // A short breath between panels, a longer one between pages.
            let pause = self.segmentIndex == self.segments.count - 1 ? 0.8 : 0.3
            DispatchQueue.main.asyncAfter(deadline: .now() + pause / max(self.speed, 0.5)) {
                guard token == self.generation, self.isPlaying else { return }
                self.advance()
            }
        }
    }

    // MARK: AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            guard utterance === self.current else { return }
            self.advance()
        }
    }

    // MARK: What gets read

    private static func segments(for page: Page, in book: Book) -> [Segment] {
        var result: [Segment] = []
        var opening = "Page \(page.number). \(page.title)."
        if !page.subtitle.isEmpty { opening += " \(sentence(page.subtitle))" }
        result.append(Segment(text: opening, panel: nil))
        if page.panels.isEmpty {
            result.append(Segment(text: page.summary.isEmpty ? "This page is a picture; open the comic to see it." : page.summary, panel: nil))
        }
        for (i, p) in page.panels.enumerated() {
            var text = sentence(p.heading)
            if !p.body.isEmpty { text += " " + speakable(p.body) }
            if let code = p.code, !code.isEmpty { text += " The page shows a code example here." }
            result.append(Segment(text: text, panel: i))
        }
        if !page.footer.isEmpty { result.append(Segment(text: "Takeaway: " + sentence(page.footer), panel: nil)) }
        return result
    }

    private static func sentence(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = t.last else { return t }
        return ".!?:".contains(last) ? t : t + "."
    }

    /// Small fixes so symbols read naturally.
    private static func speakable(_ s: String) -> String {
        s.replacingOccurrences(of: "→", with: ", then ")
            .replacingOccurrences(of: "->", with: ", then ")
            .replacingOccurrences(of: "≈", with: " about ")
            .replacingOccurrences(of: " vs. ", with: " versus ")
            .replacingOccurrences(of: " vs ", with: " versus ")
            .replacingOccurrences(of: "e.g.", with: "for example")
            .replacingOccurrences(of: "i.e.", with: "that is")
    }

    // MARK: Lock screen

    private func setUpRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in self?.resume(); return .success }
        center.pauseCommand.addTarget { [weak self] _ in self?.pause(); return .success }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in self?.toggle(); return .success }
        center.nextTrackCommand.addTarget { [weak self] _ in self?.next(); return .success }
        center.previousTrackCommand.addTarget { [weak self] _ in self?.previous(); return .success }
    }

    private func updateNowPlaying() {
        guard let book, let page else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: page.title,
            MPMediaItemPropertyArtist: book.title,
            MPMediaItemPropertyAlbumTitle: "Safety Atlas · page \(pageIndex + 1) of \(book.pages.count)",
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
