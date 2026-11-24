// Essai des modèles d'identité : extrait des recadrages de visages (alignés 112, 224 larges) et de personnes depuis une vidéo.
// Usage : extract <video> <dossier-sortie> [pas en s = 1.0]
import AVFoundation
import CoreImage
import Vision
import AppKit

setvbuf(stdout, nil, _IOLBF, 0)
let args = CommandLine.arguments
guard args.count >= 3 else { print("usage: extract <video> <out> [step]"); exit(2) }
let video = URL(fileURLWithPath: args[1])
let out = URL(fileURLWithPath: args[2], isDirectory: true)
let step = args.count > 3 ? Double(args[3]) ?? 1.0 : 1.0
let fm = FileManager.default
for d in ["align112", "face224", "person224"] { try? fm.createDirectory(at: out.appendingPathComponent(d), withIntermediateDirectories: true) }

let asset = AVURLAsset(url: video)
let sem = DispatchSemaphore(value: 0)
var track: AVAssetTrack?
Task { track = try? await asset.loadTracks(withMediaType: .video).first; sem.signal() }
sem.wait()
guard let track else { print("pas de piste vidéo"); exit(1) }
let reader = try! AVAssetReader(asset: asset)
let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
reader.add(output)
reader.startReading()

let ci = CIContext(options: [.useSoftwareRenderer: false])
let space = CGColorSpace(name: CGColorSpace.sRGB)!

// Gabarit ArcFace 112×112 (origine en haut à gauche) : œil gauche (image), œil droit, nez, coin gauche et droit de la bouche.
let tmpl: [(Double, Double)] = [(38.2946, 51.6963), (73.5318, 51.5014), (56.0252, 71.7366), (41.5493, 92.3655), (70.7299, 92.2041)]

func jpeg(_ img: CIImage, _ url: URL) {
    try? ci.writeJPEGRepresentation(of: img, to: url, colorSpace: space, options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.95])
}

/// Transformation de similitude (échelle, rotation, translation) par moindres carrés (Umeyama) de src vers dst.
func similarity(_ src: [(Double, Double)], _ dst: [(Double, Double)]) -> CGAffineTransform {
    let n = Double(src.count)
    let sm = (src.map { $0.0 }.reduce(0, +) / n, src.map { $0.1 }.reduce(0, +) / n)
    let dm = (dst.map { $0.0 }.reduce(0, +) / n, dst.map { $0.1 }.reduce(0, +) / n)
    var a = 0.0, b = 0.0, den = 0.0
    for i in 0 ..< src.count {
        let sx = src[i].0 - sm.0, sy = src[i].1 - sm.1, dx = dst[i].0 - dm.0, dy = dst[i].1 - dm.1
        a += sx * dx + sy * dy
        b += sx * dy - sy * dx
        den += sx * sx + sy * sy
    }
    let c = a / den, s = b / den   // x' = c·x − s·y, y' = s·x + c·y
    let tx = dm.0 - (c * sm.0 - s * sm.1), ty = dm.1 - (s * sm.0 + c * sm.1)
    return CGAffineTransform(a: c, b: s, c: -s, d: c, tx: tx, ty: ty)
}

var nextT = 0.0
var count = 0, faces = 0, frames = 0
var meta = [String]()
let t0 = Date()
let human = VNDetectHumanRectanglesRequest(); human.upperBodyOnly = false

while let sb = output.copyNextSampleBuffer() {
    let pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb))
    if pts < nextT { continue }
    nextT = pts + step
    guard let pb = CMSampleBufferGetImageBuffer(sb) else { continue }
    frames += 1
    let W = Double(CVPixelBufferGetWidth(pb)), H = Double(CVPixelBufferGetHeight(pb))
    let img = CIImage(cvPixelBuffer: pb)
    let fr = VNDetectFaceLandmarksRequest()
    let h = VNImageRequestHandler(cvPixelBuffer: pb, options: [:])
    try? h.perform([fr, human])
    let persons = (human.results ?? []).map { $0.boundingBox }
    for (k, f) in (fr.results ?? []).sorted(by: { $0.boundingBox.minX < $1.boundingBox.minX }).enumerated() {
        let bb = f.boundingBox
        let bw = bb.width * W, bh = bb.height * H
        guard bw >= 32, let lm = f.landmarks, let le = lm.leftEye, let re = lm.rightEye, let nose = lm.nose, let lips = lm.outerLips else { continue }
        let sz = CGSize(width: W, height: H)
        func ptsOf(_ r: VNFaceLandmarkRegion2D) -> [(Double, Double)] { r.pointsInImage(imageSize: sz).map { (Double($0.x), Double($0.y)) } }
        func mean(_ p: [(Double, Double)]) -> (Double, Double) { (p.map { $0.0 }.reduce(0, +) / Double(p.count), p.map { $0.1 }.reduce(0, +) / Double(p.count)) }
        var eyeL = mean(ptsOf(le)), eyeR = mean(ptsOf(re))
        if let lp = lm.leftPupil, let rp = lm.rightPupil { eyeL = mean(ptsOf(lp)); eyeR = mean(ptsOf(rp)) }
        if eyeL.0 > eyeR.0 { swap(&eyeL, &eyeR) }                       // « gauche » = côté gauche de l'image
        let np = ptsOf(nose); let noseTip = (mean(np).0, np.map { $0.1 }.min()! + 0.25 * (np.map { $0.1 }.max()! - np.map { $0.1 }.min()!))
        let lp = ptsOf(lips)
        let mL = lp.min { $0.0 < $1.0 }!, mR = lp.max { $0.0 < $1.0 }!
        // Gabarit converti en repère « origine en bas à gauche » (comme Vision et Core Image).
        let dst = tmpl.map { ($0.0, 112 - $0.1) }
        let T = similarity([eyeL, eyeR, noseTip, mL, mR], dst)
        let aligned = img.transformed(by: T).composited(over: CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: CGRect(x: 0, y: 0, width: 112, height: 112))).cropped(to: CGRect(x: 0, y: 0, width: 112, height: 112))
        count += 1; faces += 1
        let id = String(format: "f%05d", count)
        jpeg(aligned, out.appendingPathComponent("align112/\(id).jpg"))
        // Recadrage large : carré 1,5× la boîte, à 224.
        let cx = (bb.midX) * W, cy = (bb.midY) * H, side = max(bw, bh) * 1.5
        let sq = CGRect(x: cx - side / 2, y: cy - side / 2, width: side, height: side)
        let sc = 224 / side
        let wide = img.cropped(to: sq).transformed(by: CGAffineTransform(scaleX: sc, y: sc).translatedBy(x: -sq.minX, y: -sq.minY))
            .composited(over: CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: CGRect(x: 0, y: 0, width: 224, height: 224)))
            .cropped(to: CGRect(x: 0, y: 0, width: 224, height: 224))
        jpeg(wide, out.appendingPathComponent("face224/\(id).jpg"))
        // Personne : plus petite boîte de personne qui contient le centre du visage ; carré lettre-boîté sur fond gris.
        var pj = "null"
        let fc = CGPoint(x: bb.midX, y: bb.midY)
        if let p = persons.filter({ $0.contains(fc) }).min(by: { $0.width * $0.height < $1.width * $1.height }) {
            let pw = p.width * W, ph = p.height * H
            let ps = max(pw, ph) * 1.05
            let pr = CGRect(x: p.midX * W - ps / 2, y: p.midY * H - ps / 2, width: ps, height: ps)
            let psc = 224 / ps
            let bg = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: CGRect(x: 0, y: 0, width: 224, height: 224))
            let pimg = img.cropped(to: pr.intersection(CGRect(x: 0, y: 0, width: W, height: H)))
                .transformed(by: CGAffineTransform(scaleX: psc, y: psc).translatedBy(x: -pr.minX, y: -pr.minY))
                .composited(over: bg).cropped(to: CGRect(x: 0, y: 0, width: 224, height: 224))
            jpeg(pimg, out.appendingPathComponent("person224/\(id).jpg"))
            pj = "[\(p.minX),\(p.minY),\(p.width),\(p.height)]"
        }
        let yaw = f.yaw?.doubleValue ?? 0, roll = f.roll?.doubleValue ?? 0, pitch = f.pitch?.doubleValue ?? 0
        meta.append("{\"id\":\"\(id)\",\"t\":\(String(format: "%.3f", pts)),\"k\":\(k),\"box\":[\(bb.minX),\(bb.minY),\(bb.width),\(bb.height)],\"px\":\(Int(bw)),\"yaw\":\(yaw),\"roll\":\(roll),\"pitch\":\(pitch),\"person\":\(pj)}")
    }
    if frames % 200 == 0 { print("t=\(Int(pts)) s, \(frames) images, \(faces) visages, \(Int(Date().timeIntervalSince(t0))) s") }
}
try? meta.joined(separator: "\n").write(to: out.appendingPathComponent("meta.jsonl"), atomically: true, encoding: .utf8)
print("fini : \(frames) images, \(faces) visages, \(Int(Date().timeIntervalSince(t0))) s")
