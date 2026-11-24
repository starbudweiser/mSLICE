// mSLICE — défilement instantané de la tête de lecture.
//
// AVPlayer est fait pour lire, pas pour sauter : chaque `seek` vide son pipeline et coûte plusieurs dizaines de ms, ce qui rend le
// glissement saccadé. Ici, pendant qu'on déplace la tête de lecture, un décodeur à part (AVAssetReader → VideoToolbox, matériel)
// décode le groupe d'images (GOP) qui contient l'instant visé, depuis son image clé, et garde les images en mémoire :
//   - l'image clé s'affiche tout de suite (≈ 8 ms) ;
//   - les images suivantes arrivent au rythme du décodage (centaines d'images par seconde) ;
//   - se déplacer dans un groupe déjà décodé, en avant comme en arrière, est instantané et exact à l'image près.
// Les images sont affichées par une couche posée au-dessus du lecteur, retirée dès que AVPlayer a rejoint la position exacte.
import AVFoundation
import AppKit
import CoreMedia
import VideoToolbox

final class Scrubber: @unchecked Sendable {
    /// Couche d'affichage posée au-dessus de la vidéo du lecteur (masquée hors défilement).
    let layer = AVSampleBufferDisplayLayer()
    /// Vrai quand un fichier vidéo décodable est prêt (lu et écrit sur le fil principal).
    private(set) var ready = false

    // MARK: Types

    private struct Frame { let pts: Double; let buffer: CVPixelBuffer }

    private final class GOP {
        let start: Double, end: Double           // [image clé, image clé suivante)
        var frames: [Frame] = []                  // ordre d'affichage
        var complete = false
        var lastUse: UInt64 = 0
        var bytes = 0
        init(start: Double, end: Double) { self.start = start; self.end = end }
        var through: Double { frames.last?.pts ?? -1 }
    }

    private struct Active { let gop: GOP; let reader: AVAssetReader; let output: AVAssetReaderTrackOutput }

    private struct Setup {
        var asset: AVURLAsset? = nil
        var track: AVAssetTrack? = nil
        var duration = 0.0
        var frameDur = 1.0 / 25
        var width = 1280, height = 720
    }

    // MARK: État

    private let q = DispatchQueue(label: "fr.stephan.mslice.scrub", qos: .userInteractive)
    private let lock = NSLock()
    // protégés par `lock`
    private var target = 0.0
    private var generation = 0
    private var working = false
    private var wanted = false                    // la couche doit-elle être visible ?
    private var pendingSetup: Setup?
    private var lastExactRecord: (target: Double, pts: Double)?
    private var lastBuffer: CVPixelBuffer?
    private var mismatchCount = 0
    private var presentTotal = 0
    // confinés à `q`
    private var cur = Setup()
    private var offset = 0.0                      // temps du média − temps de la présentation (liste d'édition)
    private var gops: [Int: GOP] = [:]
    private var active: Active?
    private var useTick: UInt64 = 0
    private var bytes = 0
    private var tick: Int64 = 0
    private let byteCap = Int(min(Double(ProcessInfo.processInfo.physicalMemory) * 0.04, 1.6e9))

    init() {
        layer.videoGravity = .resizeAspect
        layer.isHidden = true
    }

    // MARK: Interface (fil principal)

    /// Prépare un fichier ; appelée à chaque chargement. Sans vidéo, ou si l'image est pivotée, le défilement reste à AVPlayer.
    @MainActor func prepare(url: URL, hasVideo: Bool) async {
        ready = false
        hide()
        var s = Setup()
        if hasVideo {
            let a = AVURLAsset(url: url)
            if let tr = try? await a.loadTracks(withMediaType: .video).first,
               let size = try? await tr.load(.naturalSize), let tf = try? await tr.load(.preferredTransform),
               let dur = try? await a.load(.duration).seconds, dur.isFinite, dur > 0,
               size.width > 0, size.height > 0, tf.isIdentity {
                let fps = (try? await tr.load(.nominalFrameRate)) ?? 0
                s.asset = a; s.track = tr; s.duration = dur; s.frameDur = fps > 1 ? 1 / Double(fps) : 1 / 30
                let w = min(1280, Int(size.width)) & ~1
                s.width = max(w, 2); s.height = max(Int((Double(w) * Double(size.height / size.width)).rounded()) & ~1, 2)
            }
        }
        install(s)
        ready = s.track != nil
    }

    private func install(_ s: Setup) {
        lock.lock(); pendingSetup = s; generation += 1; lastExactRecord = nil; mismatchCount = 0; presentTotal = 0
        let start = !working; if start { working = true }
        lock.unlock()
        if start { q.async { [self] in work() } }
    }

    /// Affiche l'image de l'instant `t` (en secondes) ; rend la main tout de suite.
    @MainActor func show(_ t: Double) {
        guard ready else { return }
        lock.lock(); let wasWanted = wanted; lock.unlock()
        if !wasWanted { layer.flushAndRemoveImage() }                // image périmée retirée avant de rendre la couche visible
        lock.lock()
        wanted = true; target = t; generation += 1
        let start = !working; if start { working = true }
        lock.unlock()
        if start { q.async { [self] in work() } }
    }

    /// Retire la couche (AVPlayer affiche de nouveau la vidéo).
    @MainActor func hide() {
        lock.lock(); wanted = false; lock.unlock()      // plus aucune image n'entre après ce verrou
        layer.isHidden = true
        layer.flushAndRemoveImage()
    }

    // MARK: Essais

    /// Image affichable d'un tampon décodé (essais).
    static func cgImage(_ pb: CVPixelBuffer) -> CGImage? {
        var img: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pb, options: nil, imageOut: &img)
        return img
    }

    var lastExact: (target: Double, pts: Double)? { lock.lock(); defer { lock.unlock() }; return lastExactRecord }
    var lastPixelBuffer: CVPixelBuffer? { lock.lock(); defer { lock.unlock() }; return lastBuffer }
    var presentCount: Int { lock.lock(); defer { lock.unlock() }; return presentTotal }
    var mismatches: Int { lock.lock(); defer { lock.unlock() }; return mismatchCount }
    var cacheSummary: String { q.sync { "\(gops.count) groupes, \(bytes / 1_048_576) Mo" } }

    // MARK: Fil de décodage

    private func work() {
        while true {
            lock.lock(); let setup = pendingSetup; pendingSetup = nil; lock.unlock()
            if let s = setup { apply(s) }
            let served = serve()
            lock.lock()
            if generation == served && pendingSetup == nil { working = false; lock.unlock(); return }
            lock.unlock()
        }
    }

    private func apply(_ s: Setup) {
        active?.reader.cancelReading(); active = nil
        gops = [:]; bytes = 0; cur = s; offset = 0
        guard let asset = s.asset, let track = s.track else { return }
        // Décalage éventuel entre le temps du média (curseurs) et celui de la présentation (images du lecteur), dû aux listes d'édition.
        if let c = track.makeSampleCursor(presentationTimeStamp: .zero) {
            _ = c.stepInDecodeOrder(byCount: -100_000)
            let media0 = c.presentationTimeStamp.seconds
            if media0.isFinite, let a = makeReader(asset, track, start: 0, end: 1, size: (s.width, s.height)) {
                if let sb = a.output.copyNextSampleBuffer() {
                    let p0 = CMSampleBufferGetPresentationTimeStamp(sb).seconds
                    if p0.isFinite { offset = media0 - p0 }
                }
                a.reader.cancelReading()
            }
        }
    }

    private func makeReader(_ asset: AVURLAsset, _ track: AVAssetTrack, start: Double, end: Double, size: (Int, Int)) -> (reader: AVAssetReader, output: AVAssetReaderTrackOutput)? {
        guard let r = try? AVAssetReader(asset: asset) else { return nil }
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferWidthKey as String: size.0, kCVPixelBufferHeightKey as String: size.1,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        ])
        out.alwaysCopiesSampleData = false
        guard r.canAdd(out) else { return nil }
        r.add(out)
        r.timeRange = CMTimeRange(start: CMTime(seconds: max(start, 0), preferredTimescale: 6000), end: CMTime(seconds: end, preferredTimescale: 6000))
        guard r.startReading() else { return nil }
        return (r, out)
    }

    /// Image clé qui précède `t` et image clé suivante (temps de présentation), d'après la table des images de synchronisation.
    private func syncRange(_ track: AVAssetTrack, _ t: Double) -> (Double, Double)? {
        guard let c = track.makeSampleCursor(presentationTimeStamp: CMTime(seconds: t + offset, preferredTimescale: 6000)) else { return nil }
        var n = 0
        while !c.currentSampleSyncInfo.sampleIsFullSync.boolValue, n < 20_000 { if c.stepInDecodeOrder(byCount: -1) == 0 { break }; n += 1 }
        let ks = c.presentationTimeStamp.seconds - offset
        guard ks.isFinite else { return nil }
        var ke = cur.duration
        if let nx = c.copy() as? AVSampleCursor, nx.stepInDecodeOrder(byCount: 1) != 0 {
            var m = 0
            while m < 20_000 {
                if nx.currentSampleSyncInfo.sampleIsFullSync.boolValue { ke = nx.presentationTimeStamp.seconds - offset; break }
                if nx.stepInDecodeOrder(byCount: 1) == 0 { break }
                m += 1
            }
        }
        return (min(ks, t), max(ke, ks + cur.frameDur))
    }

    private func cachedGOP(containing t: Double) -> GOP? {
        for g in gops.values where g.start <= t + 1e-4 && t < g.end - 1e-4 && !g.frames.isEmpty { return g }
        return nil
    }

    /// Le groupe a-t-il toutes les images jusqu'à `t` incluse (une image au-delà est décodée, ou le groupe est fini) ?
    private func covers(_ g: GOP, _ t: Double) -> Bool { g.complete || g.through > t + 1e-3 }

    private func frame(in g: GOP, at t: Double) -> Frame? {
        guard !g.frames.isEmpty else { return nil }
        var lo = 0, hi = g.frames.count - 1
        while lo < hi { let mid = (lo + hi + 1) / 2; if g.frames[mid].pts <= t + 1e-3 { lo = mid } else { hi = mid - 1 } }
        return g.frames[lo]
    }

    /// Traite la cible courante ; renvoie la génération de demande atteinte.
    private func serve() -> Int {
        lock.lock(); var t = target; var g = generation; lock.unlock()
        guard let asset = cur.asset, let track = cur.track else { return g }
        t = min(max(t, 0), cur.duration)

        let gop: GOP
        if let c = cachedGOP(containing: t) { gop = c }
        else {
            guard let (ks, ke) = syncRange(track, t) else { return g }
            let key = Int((ks * 1000).rounded())
            if let old = gops[key] { gop = old }
            else {
                // Images toutes clés (ProRes, MJPEG…) : on décode par paquets d'au moins une seconde.
                gop = GOP(start: ks, end: max(ke, ks + 1.0)); gops[key] = gop
            }
        }
        useTick += 1; gop.lastUse = useTick

        if !covers(gop, t) {
            if active?.gop !== gop {
                if let a = active { a.reader.cancelReading(); active = nil }      // l'ancien groupe reste en cache, partiel
                bytes -= gop.bytes; gop.bytes = 0; gop.frames = []; gop.complete = false
                guard let r = makeReader(asset, track, start: gop.start + offset - 0.002, end: gop.end + offset - 0.002, size: (cur.width, cur.height)) else { return g }
                active = Active(gop: gop, reader: r.reader, output: r.output)
            }
            guard let a = active else { return g }
            var lastShown = Date.distantPast
            var first = gop.frames.isEmpty
            while true {
                lock.lock(); let ng = generation; let nt = target; lock.unlock()
                if ng != g {
                    let ntc = min(max(nt, 0), cur.duration)
                    if ntc < gop.start - 1e-4 || ntc >= gop.end { return g }        // autre groupe : on recommence au tour suivant
                    g = ng; t = ntc
                }
                if covers(gop, t) { break }
                guard let sb = a.output.copyNextSampleBuffer() else { gop.complete = true; active = nil; break }
                guard let pb = CMSampleBufferGetImageBuffer(sb) else { continue }
                let pts = CMSampleBufferGetPresentationTimeStamp(sb).seconds - offset
                if first {
                    first = false
                    if abs(pts - gop.start) > cur.frameDur * 1.5 { lock.lock(); mismatchCount += 1; lock.unlock() }
                    present(pb)                                                    // retour immédiat : l'image clé
                    lastShown = Date()
                } else if pts <= t + 1e-3, Date().timeIntervalSince(lastShown) > 0.03 {
                    present(pb); lastShown = Date()                                // on rattrape la cible en montrant le chemin
                }
                let size = CVPixelBufferGetDataSize(pb)
                gop.frames.append(Frame(pts: pts, buffer: pb)); gop.bytes += size; bytes += size
                evict(keeping: gop)
            }
        }
        if let f = frame(in: gop, at: t) {
            present(f.buffer)
            lock.lock(); lastExactRecord = (t, f.pts); lock.unlock()
        }
        // Décodage d'avance : les 2 s suivantes du groupe, pour que la prochaine image (avancer, ralentir) soit déjà en mémoire.
        // Interrompu à la prochaine demande, donc sans effet sur la réactivité.
        if let a = active, a.gop === gop, !gop.complete {
            while gop.through < t + 2.0 {
                lock.lock(); let ng = generation; lock.unlock()
                if ng != g { break }
                guard let sb = a.output.copyNextSampleBuffer() else { gop.complete = true; active = nil; break }
                guard let pb = CMSampleBufferGetImageBuffer(sb) else { continue }
                let size = CVPixelBufferGetDataSize(pb)
                gop.frames.append(Frame(pts: CMSampleBufferGetPresentationTimeStamp(sb).seconds - offset, buffer: pb)); gop.bytes += size; bytes += size
                evict(keeping: gop)
            }
        }
        return g
    }

    private func evict(keeping keep: GOP) {
        guard bytes > byteCap else { return }
        for (k, g) in gops.sorted(by: { $0.value.lastUse < $1.value.lastUse }) where g !== keep && g !== active?.gop {
            bytes -= g.bytes; gops[k] = nil
            if bytes <= byteCap * 3 / 4 { break }
        }
    }

    private func present(_ pb: CVPixelBuffer) {
        var fmt: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pb, formatDescriptionOut: &fmt) == noErr, let fd = fmt else { return }
        tick += 1
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMTime(value: tick, timescale: 1000), decodeTimeStamp: .invalid)
        var sbOut: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pb, formatDescription: fd, sampleTiming: &timing, sampleBufferOut: &sbOut) == noErr, let sb = sbOut else { return }
        if let arr = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: true) as? [NSMutableDictionary], let d = arr.first {
            d.setObject(true, forKey: kCMSampleAttachmentKey_DisplayImmediately as NSString)
        }
        lock.lock()
        guard wanted else { lock.unlock(); return }
        if layer.status == .failed { layer.flush() }
        layer.enqueue(sb)
        lastBuffer = pb; presentTotal += 1
        lock.unlock()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lock.lock(); let w = self.wanted; self.lock.unlock()
            if w && self.layer.isHidden { CATransaction.begin(); CATransaction.setDisableActions(true); self.layer.isHidden = false; CATransaction.commit() }
        }
    }
}
