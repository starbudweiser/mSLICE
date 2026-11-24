// Empreinte générique d'Apple (VNGenerateImageFeaturePrintRequest) sur un dossier de JPEG → matrice float32 + temps par image.
// Usage : fp <dossier> <sortie-prefixe>
import Vision
import Foundation
let a = CommandLine.arguments
let dir = URL(fileURLWithPath: a[1]); let outp = a[2]
let files = try! FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".jpg") }.sorted()
var data = Data(); var ids = [String](); var dim = 0
var total = 0.0
for f in files {
    let req = VNGenerateImageFeaturePrintRequest()
    req.imageCropAndScaleOption = .scaleFill
    let h = VNImageRequestHandler(url: dir.appendingPathComponent(f), options: [:])
    let t0 = Date()
    try? h.perform([req])
    total += Date().timeIntervalSince(t0)
    guard let o = req.results?.first else { continue }
    dim = o.elementCount
    let n = o.elementCount
    o.data.withUnsafeBytes { data.append(contentsOf: $0.prefix(n * MemoryLayout<Float>.size)) }
    ids.append(String(f.dropLast(4)))
}
try! data.write(to: URL(fileURLWithPath: outp + ".f32"))
try! JSONSerialization.data(withJSONObject: ["ids": ids, "dim": dim, "ms_per_image": total / Double(files.count) * 1000]).write(to: URL(fileURLWithPath: outp + ".json"))
print("\(ids.count) images, dim \(dim), \(String(format: "%.1f", total / Double(files.count) * 1000)) ms/image")
