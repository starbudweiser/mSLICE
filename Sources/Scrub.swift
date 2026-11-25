// mSLICE — défilement instantané de la tête de lecture.
//
// AVPlayer est fait pour lire, pas pour sauter : chaque `seek` vide son pipeline et coûte plusieurs dizaines de ms, ce qui rend le
// glissement saccadé. Ici, pendant qu'on déplace la tête de lecture, un décodeur à part (AVAssetReader → VideoToolbox, matériel)
// décode le groupe d'images (GOP) qui contient l'instant visé, depuis son image clé, et garde les images en mémoire :
//   - l'image clé s'affiche tout de suite (≈ 8 ms) ;
//   - les images suivantes arrivent au rythme du décodage (centaines d'images par seconde) ;
//   - se déplacer dans un groupe déjà décodé, en avant comme en arrière, est instantané et exact à l'image près.
// Les images sont affichées par une couche posée au-dessus du lecteur, retirée dès que AVPlayer a rejoint la position exacte.
//
// Groupes très longs (fichiers sans images clés régulières, parfois une seule au début) : garder tout le groupe coûterait des
// gigaoctets. On ne garde alors qu'une fenêtre d'images autour de la cible, plus des repères espacés (≤ ¼ de la réserve) qui
// donnent tout de suite une image proche quand on revient en arrière, le temps de redécoder depuis l'image clé.
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

    private struct Frame { let pts: Double; let buffer: CVPixelBuffer; let anchor: Bool }

    private final class GOP {
        let start: Double, end: Double           // [image clé, image clé suivante)
        var frames: [Frame] = []                  // ordre d'affichage : fenêtre continue + repères
        var lastUse: UInt64 = 0
        var bytes = 0
        /// Écart entre repères (groupes longs) ; 0 : groupe court, toutes les images sont gardées.
        var spacing = 0.0
        // Passe de décodage en cours (depuis l'image clé) : images continues de `denseFrom` à `through`.
        var denseFrom = Double.infinity
        var through = -1.0
        var complete = false                      // la passe a atteint la fin du groupe
        var decoded = 0                           // images décodées pendant la passe
        var lastSlot = -1
        init(start: Double, end: Double) { self.start = start; self.end = end }
        func newPass() { denseFrom = .infinity; through = -1; complete = false; decoded = 0; lastSlot = -1 }
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
    /// Mémoire d'images décodées gardée en réserve : 3 % de la RAM, au plus 400 Mo (≈ 290 images 1280×720). Le groupe en cours peut dépasser le temps du défilement.
    /// Cette mémoire graphique (IOSurface) n'apparaît pas dans l'empreinte du processus mais occupe bien la RAM : on la libère dès le repos.
    private let byteCap = Int(min(Double(ProcessInfo.processInfo.physicalMemory) * 0.03, 400e6))
    private static let idleSeconds = 12.0
    private var lastActivity = Date()
    private var memoryPressure: DispatchSourceMemoryPressure?

    init() {
        layer.videoGravity = .resizeAspect
        layer.isHidden = true
        // Pression mémoire du système : on rend tout de suite les images en réserve.
        let src = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: q)
        src.setEventHandler { [weak self] in self?.purge() }
        src.resume(); memoryPressure = src
    }

    /// Libère le décodeur et toutes les images en réserve (sur `q`).
    private func purge() {
        active?.reader.cancelReading(); active = nil
        gops = [:]; bytes = 0
    }

    /// Après un temps sans demande, libère la réserve : le défilement suivant repart d'une image clé (≈ 10 ms).
    private func scheduleIdlePurge() {
        q.asyncAfter(deadline: .now() + Self.idleSeconds + 0.5) { [weak self] in
            guard let self else { return }
            self.lock.lock(); let busy = self.working; let idle = Date().timeIntervalSince(self.lastActivity); self.lock.unlock()
            if !busy, idle >= Self.idleSeconds { self.purge() }
        }
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
        wanted = true; target = t; generation += 1; lastActivity = Date()
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
    var cacheBytes: Int { q.sync { bytes } }

    // MARK: Fil de décodage

    private func work() {
        while true {
            lock.lock(); let setup = pendingSetup; pendingSetup = nil; lock.unlock()
            if let s = setup { apply(s) }
            let served = serve()
            lock.lock()
            if generation == served && pendingSetup == nil { working = false; lock.unlock(); scheduleIdlePurge(); return }
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
        while !c.currentSampleSyncInfo.sampleIsFullSync.boolValue, n < 200_000 { if c.stepInDecodeOrder(byCount: -1) == 0 { break }; n += 1 }
        let ks = c.presentationTimeStamp.seconds - offset
        guard ks.isFinite else { return nil }
        var ke = cur.duration
        if let nx = c.copy() as? AVSampleCursor, nx.stepInDecodeOrder(byCount: 1) != 0 {
            var m = 0
            while m < 200_000 {
                if nx.currentSampleSyncInfo.sampleIsFullSync.boolValue { ke = nx.presentationTimeStamp.seconds - offset; break }
                if nx.stepInDecodeOrder(byCount: 1) == 0 { break }
                m += 1
            }
        }
        return (min(ks, t), max(ke, ks + cur.frameDur))
    }

    /// Groupe plus long que ceci : fenêtre autour de la cible et repères espacés, au lieu de tout garder.
    private static let longGOP = 10.0
    /// Fenêtre gardée avant la cible quand la réserve est pleine (revenir un peu en arrière reste instantané).
    private static let keepBack = 1.0

    private func cachedGOP(containing t: Double) -> GOP? {
        for g in gops.values where g.start <= t + 1e-4 && t < g.end - 1e-4 && !g.frames.isEmpty { return g }
        return nil
    }

    /// La passe en cours a-t-elle toutes les images jusqu'à `t` incluse (une image au-delà est décodée, ou le groupe est fini) ?
    private func covers(_ g: GOP, _ t: Double) -> Bool { t >= g.denseFrom - 1e-3 && (g.complete || g.through > t + 1e-3) }

    /// La passe en cours peut-elle encore fournir l'image exacte de `t` (sans repartir de l'image clé) ?
    private func reachable(_ g: GOP, _ t: Double) -> Bool {
        guard active?.gop === g, !g.complete else { return false }
        return g.denseFrom.isFinite ? t >= g.denseFrom - 1e-3 : t > g.through + 1e-3
    }

    /// Dernière image gardée à `t` ou avant : exacte dans la fenêtre continue, approchée ailleurs (repère).
    private func frame(in g: GOP, at t: Double) -> Frame? {
        guard !g.frames.isEmpty else { return nil }
        var lo = 0, hi = g.frames.count - 1
        while lo < hi { let mid = (lo + hi + 1) / 2; if g.frames[mid].pts <= t + 1e-3 { lo = mid } else { hi = mid - 1 } }
        return g.frames[lo]
    }

    /// Nouvelle passe depuis l'image clé. Les images d'une passe précédente ne sont plus continues : seuls les repères restent.
    private func startPass(_ gop: GOP, _ asset: AVURLAsset, _ track: AVAssetTrack) -> Bool {
        if let a = active { a.reader.cancelReading(); active = nil }             // l'ancien groupe reste en cache, partiel
        let before = gop.bytes
        gop.frames.removeAll { !$0.anchor }
        gop.bytes = gop.frames.reduce(0) { $0 + CVPixelBufferGetDataSize($1.buffer) }
        bytes -= before - gop.bytes
        gop.newPass()
        guard let r = makeReader(asset, track, start: gop.start + offset - 0.002, end: gop.end + offset - 0.002, size: (cur.width, cur.height)) else { return false }
        active = Active(gop: gop, reader: r.reader, output: r.output)
        return true
    }

    /// Range une image décodée : toujours dans un groupe court ; dans un groupe long, seulement près de la cible ou comme repère.
    private func ingest(_ pb: CVPixelBuffer, pts: Double, into gop: GOP, target t: Double) {
        let firstOfPass = gop.decoded == 0
        gop.decoded += 1; gop.through = max(gop.through, pts)
        var anchor = false
        if gop.spacing > 0 {
            let slot = Int((pts - gop.start) / gop.spacing)
            if slot != gop.lastSlot { gop.lastSlot = slot; anchor = true }
        }
        let dense = gop.spacing == 0 || gop.denseFrom.isFinite || pts >= t - Self.keepBack
        guard dense || anchor else { return }
        if dense && !gop.denseFrom.isFinite { gop.denseFrom = firstOfPass ? gop.start : pts }
        let f = Frame(pts: pts, buffer: pb, anchor: anchor)
        var lo = 0, hi = gop.frames.count
        while lo < hi { let mid = (lo + hi) / 2; if gop.frames[mid].pts < pts { lo = mid + 1 } else { hi = mid } }
        if lo < gop.frames.count, abs(gop.frames[lo].pts - pts) < 1e-4 { return }   // repère déjà gardé par une passe précédente
        gop.frames.insert(f, at: lo)
        let size = CVPixelBufferGetDataSize(pb); gop.bytes += size; bytes += size
        evict(keeping: gop, target: t)
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
                if gop.end - gop.start > Self.longGOP {
                    let frameBytes = Double(cur.width * cur.height) * 1.6
                    let anchors = max(8, Double(byteCap) / 4 / frameBytes)
                    gop.spacing = max(0.5, (gop.end - gop.start) / anchors)
                }
            }
        }
        useTick += 1; gop.lastUse = useTick

        if !covers(gop, t) {
            // Tout de suite, l'image gardée la plus proche avant la cible (repère, image clé ou fenêtre).
            var shown = -Double.infinity
            if let f = frame(in: gop, at: t), f.pts <= t + 1e-3 { present(f.buffer); shown = f.pts }
            if !reachable(gop, t) { guard startPass(gop, asset, track) else { return g } }
            guard let a = active else { return g }
            var lastShown = shown.isFinite ? Date() : Date.distantPast
            while true {
                lock.lock(); let ng = generation; let nt = target; lock.unlock()
                if ng != g {
                    let ntc = min(max(nt, 0), cur.duration)
                    if ntc < gop.start - 1e-4 || ntc >= gop.end { return g }        // autre groupe : on recommence au tour suivant
                    if !covers(gop, ntc) && !reachable(gop, ntc) { return g }     // revenu derrière la passe : nouvelle passe au tour suivant
                    g = ng; t = ntc
                }
                if covers(gop, t) { break }
                guard let sb = a.output.copyNextSampleBuffer() else { gop.complete = true; active = nil; break }
                guard let pb = CMSampleBufferGetImageBuffer(sb) else { continue }
                let pts = CMSampleBufferGetPresentationTimeStamp(sb).seconds - offset
                if gop.decoded == 0, abs(pts - gop.start) > cur.frameDur * 1.5 { lock.lock(); mismatchCount += 1; lock.unlock() }
                // On montre le chemin vers la cible, sans jamais revenir avant l'image déjà affichée.
                if pts > shown + 1e-4, pts <= t + 1e-3, !shown.isFinite || Date().timeIntervalSince(lastShown) > 0.03 {
                    present(pb); shown = pts; lastShown = Date()
                }
                ingest(pb, pts: pts, into: gop, target: t)
            }
        }
        if covers(gop, t), let f = frame(in: gop, at: t) {
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
                ingest(pb, pts: CMSampleBufferGetPresentationTimeStamp(sb).seconds - offset, into: gop, target: t)
            }
        }
        return g
    }

    private func evict(keeping keep: GOP, target t: Double) {
        guard bytes > byteCap else { return }
        for (k, g) in gops.sorted(by: { $0.value.lastUse < $1.value.lastUse }) where g !== keep && g !== active?.gop {
            bytes -= g.bytes; gops[k] = nil
            if bytes <= byteCap * 3 / 4 { return }
        }
        // Toujours trop : le groupe en cours est trop long pour la réserve. On retire le début de sa fenêtre ; les repères restent.
        let cut = t - Self.keepBack
        guard bytes > byteCap, keep.denseFrom.isFinite, cut > keep.denseFrom else { return }
        var freed = 0
        keep.frames.removeAll { f in
            let drop = !f.anchor && f.pts >= keep.denseFrom - 1e-4 && f.pts < cut
            if drop { freed += CVPixelBufferGetDataSize(f.buffer) }
            return drop
        }
        keep.bytes -= freed; bytes -= freed
        if cut > keep.through { keep.denseFrom = .infinity }      // la cible est loin devant : la fenêtre reprendra près d'elle
        else { keep.denseFrom = keep.frames.first(where: { $0.pts >= cut - 1e-4 })?.pts ?? cut }
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
