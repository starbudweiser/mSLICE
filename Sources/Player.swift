// mSLICE — lecture (AVPlayer) : fichier d'origine si macOS le lit, sinon un proxy fabriqué par ffmpeg (remux sans perte, sinon basse définition).
import AVFoundation
import AppKit
import CryptoKit
import SwiftUI

@MainActor
final class PlayerModel: ObservableObject {
    @Published var time: Double = 0
    @Published var isPlaying = false
    @Published var rate: Float = 0
    @Published var preparing: String?        // « Préparation de l'aperçu… »
    let player = AVPlayer()
    /// Défilement instantané (voir Scrub.swift) : prend en charge l'affichage pendant qu'on déplace la tête de lecture.
    let scrubber = Scrubber()
    private var scrubEpoch = 0
    private(set) var duration: Double = 0
    private(set) var frameDuration: Double = 0.04
    private var observer: Any?
    private var chasing = false
    private var pending: (Double, Bool)?
    private var endObserver: NSObjectProtocol?
    private var loadToken = UUID()
    private var baseURL: URL?                 // ce que le lecteur joue (original ou proxy), pour recomposer l'item avec la piste « voix seules »
    @Published private(set) var voiceOnly = false

    init() {
        player.automaticallyWaitsToMinimizeStalling = false
        player.actionAtItemEnd = .pause
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self, self.player.rate != 0, t.isValid else { return }
                self.time = min(max(t.seconds, 0), self.duration)
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.isPlaying = false; self?.rate = 0 }
        }
    }

    // MARK: Chargement

    func load(_ info: MediaInfo) async {
        pause()
        let token = UUID(); loadToken = token
        duration = info.duration
        frameDuration = 1 / max(info.video?.fps ?? 25, 1)
        time = 0
        preparing = nil
        player.replaceCurrentItem(with: nil)
        scrubber.hide()
        let url = await Proxies.playableURL(info) { [weak self] in Task { @MainActor in self?.preparing = L.t("preview.preparing") } }
        guard token == loadToken else { return }
        preparing = nil
        baseURL = url; voiceOnly = false
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        await scrubber.prepare(url: url, hasVideo: !info.isAudioOnly)
    }

    /// Joue la piste « voix seules » (image de l'original, son de `CleanVoice`) ou revient au son d'origine ; la position et la lecture sont conservées.
    func setVoiceOnly(_ on: Bool, info: MediaInfo) async {
        guard let url = baseURL, on != voiceOnly else { return }
        let token = loadToken
        var item = AVPlayerItem(url: url), applied = false
        if on, CleanVoice.exists(info), let comp = await Self.composition(video: url, voice: CleanVoice.url(info), hasVideo: !info.isAudioOnly) { item = AVPlayerItem(asset: comp); applied = true }
        guard token == loadToken, baseURL == url else { return }
        let t = player.currentTime(), wasPlaying = isPlaying, r = rate
        player.replaceCurrentItem(with: item)
        voiceOnly = applied
        await player.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero)
        if wasPlaying, token == loadToken { play(rate: r) }
    }

    private static func composition(video: URL, voice: URL, hasVideo: Bool) async -> AVMutableComposition? {
        let comp = AVMutableComposition()
        let vAsset = AVURLAsset(url: video), cAsset = AVURLAsset(url: voice)
        do {
            let vDur = try await vAsset.load(.duration)
            if hasVideo, let vt = try await vAsset.loadTracks(withMediaType: .video).first,
               let ct = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
                try ct.insertTimeRange(CMTimeRange(start: .zero, duration: vDur), of: vt, at: .zero)
                ct.preferredTransform = try await vt.load(.preferredTransform)
            }
            guard let at = try await cAsset.loadTracks(withMediaType: .audio).first,
                  let cat = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { return nil }
            let aDur = try await cAsset.load(.duration)
            try cat.insertTimeRange(CMTimeRange(start: .zero, duration: min(vDur, aDur)), of: at, at: .zero)
            return comp
        } catch { return nil }
    }

    // MARK: Commandes

    /// Se place sur un instant, à l'image près ; les demandes rapprochées (glissement) sont regroupées.
    /// À l'arrêt, le décodeur de défilement affiche l'image tout de suite (exacte, depuis sa mémoire) ; AVPlayer rejoint ensuite la position
    /// exacte et la couche du décodeur s'efface. `precise: false` (glissement sur la timeline) : AVPlayer n'est pas sollicité du tout.
    func seek(_ t: Double, precise: Bool = true) {
        let c = min(max(t, 0), duration)
        time = c
        if scrubber.ready, !isPlaying {
            scrubEpoch += 1
            scrubber.show(c)
            if !precise { return }
        }
        pending = (c, precise || (pending?.1 ?? false))
        if !chasing { chase() }
    }

    private func chase() {
        guard let (t, precise) = pending else {
            chasing = false
            // AVPlayer a rejoint la position : on retire la couche du décodeur, sauf si un nouveau défilement a commencé entre-temps.
            let e = scrubEpoch
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
                MainActor.assumeIsolated { if let self, self.scrubEpoch == e, !self.chasing { self.scrubber.hide() } }
            }
            return
        }
        chasing = true; pending = nil
        let tol: CMTime = precise ? .zero : .positiveInfinity
        player.seek(to: CMTime(seconds: t, preferredTimescale: 600), toleranceBefore: tol, toleranceAfter: tol) { [weak self] _ in
            Task { @MainActor in self?.chase() }
        }
    }

    func play(rate r: Float = 1) {
        if r > 0, time >= duration - 0.01 { seek(0) }
        scrubEpoch += 1; scrubber.hide()
        player.rate = r; rate = r; isPlaying = r != 0
    }
    func pause() { player.pause(); rate = 0; isPlaying = false; time = player.currentTime().seconds.isFinite ? min(max(player.currentTime().seconds, 0), duration) : time }
    func togglePlay() { isPlaying ? pause() : play() }
    func step(frames: Int) { pause(); seek(time + Double(frames) * frameDuration) }

    /// J / K / L : marche arrière, pause, marche avant (vitesses 1, 2, 4, 8 ×).
    func jkl(_ key: String) {
        let speeds: [Float] = [1, 2, 4, 8]
        switch key {
        case "k": pause()
        case "l":
            if rate > 0, let i = speeds.firstIndex(of: rate), i + 1 < speeds.count { play(rate: speeds[i + 1]) } else { play(rate: 1) }
        case "j":
            if rate < 0, let i = speeds.firstIndex(of: -rate), i + 1 < speeds.count { play(rate: -speeds[i + 1]) } else { play(rate: -1) }
        default: break
        }
    }
}

/// Surface vidéo (AVPlayerLayer) sur fond noir.
/// Contient la vidéo du lecteur et, par-dessus, la couche du décodeur de défilement.
final class PlayerHostView: NSView {
    let video = AVPlayerLayer()
    var overlay: CALayer? { didSet { oldValue?.removeFromSuperlayer(); if let o = overlay { layer?.addSublayer(o); needsLayout = true } } }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer = CALayer(); layer?.backgroundColor = NSColor.black.cgColor
        video.videoGravity = .resizeAspect; video.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(video)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        video.frame = bounds; overlay?.frame = bounds
        CATransaction.commit()
    }
}

struct PlayerSurface: NSViewRepresentable {
    let player: AVPlayer
    let overlay: CALayer
    func makeNSView(context: Context) -> PlayerHostView {
        let v = PlayerHostView(); v.video.player = player; v.overlay = overlay; return v
    }
    func updateNSView(_ v: PlayerHostView, context: Context) {
        if v.video.player !== player { v.video.player = player }
        if v.overlay !== overlay { v.overlay = overlay }
    }
}
