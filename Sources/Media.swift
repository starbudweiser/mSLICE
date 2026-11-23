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
final class Filmstrip {
    static let w = 96, h = 54
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
    fileprivate func set(_ i: Int, _ img: CGImage) { lock.lock(); images[i] = img; lock.unlock() }

    /// Une image par vignette, par recherche rapide (image clé la plus proche) ; quatre ffmpeg en parallèle.
    func load(_ info: MediaInfo, cancel: CancelToken) async {
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
                    guard let d = Run.data(ffmpeg, args), d.count >= Filmstrip.w * Filmstrip.h * 3,
                          let provider = CGDataProvider(data: d as CFData),
                          let img = CGImage(width: Filmstrip.w, height: Filmstrip.h, bitsPerComponent: 8, bitsPerPixel: 24, bytesPerRow: Filmstrip.w * 3, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: 0), provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return }
                    self.set(i, img)
                    DispatchQueue.main.async { self.onChange?() }
                }
            }
            for _ in 0 ..< 4 { spawn() }
            while await group.next() != nil { spawn() }
        }
    }
}
