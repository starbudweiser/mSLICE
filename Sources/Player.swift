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

    init() {
        player.automaticallyWaitsToMinimizeStalling = false
        player.actionAtItemEnd = .pause
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 60), queue: .main) { [weak self] t in
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
        let url = await playableURL(info)
        guard token == loadToken else { return }
        preparing = nil
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        await scrubber.prepare(url: url, hasVideo: !info.isAudioOnly)
    }

    private func isPlayable(_ url: URL, needsVideo: Bool) async -> Bool {
        let a = AVURLAsset(url: url)
        guard (try? await a.load(.isPlayable)) == true else { return false }
        guard let tracks = try? await a.load(.tracks) else { return false }
        for t in tracks where (try? await t.load(.isDecodable)) == false { return false }
        if needsVideo { return tracks.contains { $0.mediaType == .video } }
        return !tracks.isEmpty
    }

    private func playableURL(_ info: MediaInfo) async -> URL {
        if await isPlayable(info.url, needsVideo: !info.isAudioOnly) { return info.url }
        guard let ffmpeg = Tools.ffmpeg else { return info.url }
        let dir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Caches/mSLICE/proxies", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let mtime = (try? info.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate?.timeIntervalSince1970) ?? 0
        let key = SHA256.hash(data: Data("\(info.url.path)|\(info.size)|\(mtime)".utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        let ext = info.isAudioOnly ? "m4a" : "mov"
        let out = dir.appendingPathComponent(key).appendingPathExtension(ext)
        if FileManager.default.fileExists(atPath: out.path), await isPlayable(out, needsVideo: !info.isAudioOnly) { return out }
        preparing = L.t("preview.preparing")
        let tmp = dir.appendingPathComponent(key + ".part").appendingPathExtension(ext)
        let src = info.url.path
        let base = ["-nostdin", "-hide_banner", "-v", "error", "-y"]
        var attempts: [[String]] = []
        if info.isAudioOnly {
            attempts = [base + ["-i", src, "-vn", "-map", "0:a:0", "-c:a", "aac_at", "-b:a", "192k", tmp.path]]
        } else {
            attempts = [
                base + ["-i", src, "-map", "0:\(info.video?.index ?? 0)", "-map", "0:a:0?", "-c", "copy", "-f", "mov", tmp.path],     // remux sans perte
                base + ["-i", src, "-map", "0:\(info.video?.index ?? 0)", "-map", "0:a:0?", "-vf", "scale='min(1280,iw)':-2", "-c:v", "h264_videotoolbox", "-b:v", "6M", "-allow_sw", "1", "-pix_fmt", "yuv420p", "-g", "12",
                        "-c:a", "aac_at", "-b:a", "160k", "-f", "mov", tmp.path],
            ]
        }
        for args in attempts {
            try? FileManager.default.removeItem(at: tmp)
            let r = await Run.exec(ffmpeg, args)
            if r.status == 0, await isPlayable(tmp, needsVideo: !info.isAudioOnly) {
                try? FileManager.default.removeItem(at: out)
                try? FileManager.default.moveItem(at: tmp, to: out)
                return out
            }
        }
        try? FileManager.default.removeItem(at: tmp)
        return info.url
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
