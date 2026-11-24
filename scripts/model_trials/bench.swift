// Vitesse native d'un modèle Core ML d'empreinte : compilation, chargement, puis 300 prédictions sur un vrai visage (CVPixelBuffer BGRA).
// Usage : bench <modèle.mlpackage> <image.jpg> <entrée-largeur> <nom-sortie>
import CoreML
import CoreImage
import Foundation
let a = CommandLine.arguments
let src = URL(fileURLWithPath: a[1]); let img = URL(fileURLWithPath: a[2]); let side = Int(a[3])!; let outName = a[4]
func pixelBuffer() -> CVPixelBuffer {
    let ci = CIImage(contentsOf: img)!
    var pb: CVPixelBuffer?
    CVPixelBufferCreate(nil, side, side, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pb)
    CIContext().render(ci.transformed(by: CGAffineTransform(scaleX: CGFloat(side) / ci.extent.width, y: CGFloat(side) / ci.extent.height)), to: pb!)
    return pb!
}
let t0 = Date()
let compiled = try! MLModel.compileModel(at: src)
print(String(format: "compilation : %.2f s", Date().timeIntervalSince(t0)))
let pb = pixelBuffer()
for (label, units) in [("ANE (cpuAndNeuralEngine)", MLComputeUnits.cpuAndNeuralEngine), ("GPU (cpuAndGPU)", .cpuAndGPU), ("CPU seul", .cpuOnly)] {
    let cfg = MLModelConfiguration(); cfg.computeUnits = units
    let t1 = Date()
    let m = try! MLModel(contentsOf: compiled, configuration: cfg)
    let input = try! MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(pixelBuffer: pb)])
    _ = try! m.prediction(from: input)
    let first = Date().timeIntervalSince(t1)
    for _ in 0 ..< 30 { _ = try! m.prediction(from: input) }
    var ts = [Double]()
    for _ in 0 ..< 300 { let s = Date(); let r = try! m.prediction(from: input); ts.append(Date().timeIntervalSince(s) * 1000); _ = r.featureValue(for: outName) }
    ts.sort()
    print(String(format: "%@ : chargement + 1re prédiction %.2f s ; par image moyenne %.2f ms, médiane %.2f, p95 %.2f", label, first, ts.reduce(0, +) / 300, ts[150], ts[285]))
}
try? FileManager.default.removeItem(at: compiled)
