// mSLICE — pics audio (forme d'onde) et vignettes de la timeline, calculés par ffmpeg en tâche de fond.
import AppKit
import Foundation

/// Pics audio par tranches de 10 ms (valeur absolue maximale, 0…1), remplis progressivement.
final class PeakStore {
    static let bucket = 0.01
    private let lock = NSLock()
    private var values: [Float] = []
    private(set) var maxSeen: Float = 0.02
    var onChange: (() -> Void)?

    var duration: Double { lock.lock(); defer { lock.unlock() }; return Double(values.count) * PeakStore.bucket }
    func append(_ v: [Float]) {
        lock.lock(); values.append(contentsOf: v); if let m = v.max(), m > maxSeen { maxSeen = m }; lock.unlock()
    }
    /// Pic maximal entre deux instants (en secondes) ; 0 si la zone n'est pas encore calculée.
    func peak(_ t0: Double, _ t1: Double) -> Float {
        lock.lock(); defer { lock.unlock() }
        let a = max(0, Int(t0 / PeakStore.bucket)), b = min(values.count - 1, Int(t1 / PeakStore.bucket))
        guard a <= b else { return 0 }
        var m: Float = 0
        for i in a ... b where values[i] > m { m = values[i] }
        return m
    }
    var isEmpty: Bool { lock.lock(); defer { lock.unlock() }; return values.isEmpty }
}

enum PeakLoader {
    /// Décode la première piste audio en mono 4 kHz et en tire les pics. Appelle `onChange` régulièrement pour redessiner.
    static func load(_ info: MediaInfo, into store: PeakStore, cancel: CancelToken) async {
        guard let ffmpeg = Tools.ffmpeg, info.audio != nil else { return }
        await Task.detached(priority: .utility) {
            let p = Process(); p.executableURL = ffmpeg
            p.arguments = ["-nostdin", "-v", "error", "-i", info.url.path, "-vn", "-map", "0:a:0", "-ac", "1", "-ar", "4000", "-f", "s16le", "-"]
            let out = Pipe(); p.standardOutput = out; p.standardError = FileHandle.nullDevice; p.standardInput = FileHandle.nullDevice
            do { try p.run() } catch { return }
            cancel.attach(p)
            let h = out.fileHandleForReading
            var carry = Data(), peak: Int32 = 0, n = 0
            var batch: [Float] = [], lastNotify = Date()
            while true {
                let d = h.readData(ofLength: 1 << 16)
                if d.isEmpty { break }
                carry.append(d)
                let usable = carry.count & ~1
                carry.withUnsafeBytes { raw in
                    let s = raw.bindMemory(to: Int16.self)
                    for i in 0 ..< usable / 2 {
                        let a = Int32(abs(Int32(s[i])))
                        if a > peak { peak = a }
                        n += 1
                        if n == 40 { batch.append(Float(peak) / 32768); peak = 0; n = 0 }
                    }
                }
                carry = carry.suffix(carry.count - usable)
                if Date().timeIntervalSince(lastNotify) > 0.25 || batch.count > 4000 {
                    store.append(batch); batch.removeAll(keepingCapacity: true); lastNotify = Date()
                    DispatchQueue.main.async { store.onChange?() }
                }
            }
            if n > 0 { batch.append(Float(peak) / 32768) }
            store.append(batch)
            p.waitUntilExit()
            DispatchQueue.main.async { store.onChange?() }
        }.value
    }
}

/// Vignettes réparties à intervalles réguliers sur la durée.
/// Fichier à images clés espacées (caméra, H.264 / HEVC) : un seul ffmpeg qui ne décode que les images clés (quelques secondes pour 30 min).
/// Moins d'images clés que de vignettes (parfois une seule, au début) : le même ffmpeg décode toutes les images (≈ 4 s pour 3 min en 1440p60).
/// Fichier tout en images clés (ProRes…) : recherches rapides en parallèle. Le résultat est gardé sur disque : la réouverture est instantanée.
final class Filmstrip {
    static let w = 96, h = 54
    static var frameBytes: Int { w * h * 3 }
    let count: Int
    let duration: Double
    private let lock = NSLock()
    private var images: [CGImage?]
    var onChange: (() -> Void)?

    init(duration: Double) {
        self.duration = duration
        count = min(96, max(8, Int(duration / 2)))
        images = Array(repeating: nil, count: count)
    }
    func image(_ i: Int) -> CGImage? { lock.lock(); defer { lock.unlock() }; return images.indices.contains(i) ? images[i] : nil }
    fileprivate func set(_ i: Int, _ img: CGImage) { lock.lock(); if images.indices.contains(i) { images[i] = img }; lock.unlock() }
    private var complete: Bool { lock.lock(); defer { lock.unlock() }; return !images.contains { $0 == nil } }
    private func notify() { DispatchQueue.main.async { self.onChange?() } }

    private static func cgImage(_ d: Data) -> CGImage? {
        guard d.count >= frameBytes, let provider = CGDataProvider(data: d.prefix(frameBytes) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 24, bytesPerRow: w * 3, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: 0), provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    private func cacheURL(_ info: MediaInfo) -> URL {
        let d = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Caches/mSLICE/film", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent("\(SessionStore.key(info))-\(count).rgb")
    }

    func load(_ info: MediaInfo, keyframes: [Double], cancel: CancelToken) async {
        guard Tools.ffmpeg != nil, info.video != nil else { return }
        let cache = cacheURL(info)
        if let d = try? Data(contentsOf: cache), d.count == count * Filmstrip.frameBytes {
            for i in 0 ..< count { if let img = Filmstrip.cgImage(d.subdata(in: i * Filmstrip.frameBytes ..< (i + 1) * Filmstrip.frameBytes)) { set(i, img) } }
            notify(); return
        }
        let dense = Double(keyframes.count) / max(info.duration, 1) > 1.5          // plus d'une image clé et demie par seconde
        if dense { await seekPass(info, cancel) } else { await singlePass(info, keyOnly: keyframes.count >= count, cancel) }
        if complete, !cancel.cancelled {
            var all = Data()
            for i in 0 ..< count { if let img = image(i), let d = img.dataProvider?.data { all.append(d as Data) } }
            if all.count == count * Filmstrip.frameBytes { try? all.write(to: cache, options: .atomic) }
        }
    }

    /// Un seul ffmpeg, ramené à `count` images régulièrement espacées : seules les images clés sont décodées (`keyOnly`), ou toutes.
    private func singlePass(_ info: MediaInfo, keyOnly: Bool, _ cancel: CancelToken) async {
        guard let ffmpeg = Tools.ffmpeg, let v = info.video else { return }
        let n = count, dur = info.duration
        await Task.detached(priority: .utility) { [self] in
            let vf = "fps=fps=\(String(format: "%.8f", Double(n) / dur)),scale=\(Filmstrip.w):\(Filmstrip.h):force_original_aspect_ratio=decrease,pad=\(Filmstrip.w):\(Filmstrip.h):(ow-iw)/2:(oh-ih)/2:black"
            let p = Process(); p.executableURL = ffmpeg; p.qualityOfService = .utility
            p.arguments = ["-nostdin", "-v", "error"] + (keyOnly ? ["-skip_frame", "nokey"] : []) + ["-i", info.url.path, "-map", "0:\(v.index)", "-an", "-sn", "-vf", vf, "-frames:v", String(n), "-f", "rawvideo", "-pix_fmt", "rgb24", "-"]
            let out = Pipe(); p.standardOutput = out; p.standardError = FileHandle.nullDevice; p.standardInput = FileHandle.nullDevice
            do { try p.run() } catch { return }
            cancel.attach(p)
            let h = out.fileHandleForReading
            var buf = Data(), i = 0, last = Date()
            while i < n {
                let d = h.readData(ofLength: Filmstrip.frameBytes)
                if d.isEmpty { break }
                buf.append(d)
                while buf.count >= Filmstrip.frameBytes, i < n {
                    if let img = Filmstrip.cgImage(buf) { set(i, img) }
                    buf.removeFirst(Filmstrip.frameBytes); i += 1
                }
                if Date().timeIntervalSince(last) > 0.15 { last = Date(); notify() }
            }
            p.waitUntilExit()
            if i > 0 && i < n, let lastImg = image(i - 1) { for k in i ..< n { set(k, lastImg) } }     // fin de fichier : on répète la dernière
            notify()
        }.value
    }

    /// Fichiers tout en images clés : une recherche rapide par vignette, huit ffmpeg en parallèle.
    private func seekPass(_ info: MediaInfo, _ cancel: CancelToken) async {
        guard let ffmpeg = Tools.ffmpeg, let v = info.video else { return }
        let n = count, dur = info.duration
        await withTaskGroup(of: Void.self) { group in
            var next = 0
            func spawn() {
                guard next < n else { return }
                let i = next; next += 1
                group.addTask(priority: .utility) { [self] in
                    if cancel.cancelled { return }
                    let t = (Double(i) + 0.5) / Double(n) * dur
                    let vf = "scale=\(Filmstrip.w):\(Filmstrip.h):force_original_aspect_ratio=decrease,pad=\(Filmstrip.w):\(Filmstrip.h):(ow-iw)/2:(oh-ih)/2:black"
                    let args = ["-nostdin", "-v", "error", "-noaccurate_seek", "-ss", String(format: "%.3f", t), "-i", info.url.path, "-map", "0:\(v.index)", "-frames:v", "1", "-an", "-sn", "-vf", vf, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"]
                    guard let d = Run.data(ffmpeg, args), let img = Filmstrip.cgImage(d) else { return }
                    set(i, img); notify()
                }
            }
            for _ in 0 ..< 8 { spawn() }
            while await group.next() != nil { spawn() }
        }
    }
}
