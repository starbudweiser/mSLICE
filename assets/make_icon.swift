// mSLICE — dessine l'icône d'appli (plate : fond uni, motif simple, sans ombre ni reflet ni contour) en PNG 1024.
// Usage : swift assets/make_icon.swift <1|2|3|planche> <sortie.png>
//   1 = bistouri (vert pétrole) · 2 = crochets d'entrée / sortie autour d'une onde (indigo) · 3 = onde tranchée (noir, coupe rouge) · planche = les trois côte à côte
import AppKit

let variant = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "1"
let out = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "icon-1024.png"
let cs = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ v: UInt32) -> CGColor { CGColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: 1) }
let white = rgb(0xFFFFFF)

/// Dessine l'icône n° `v` dans un espace de 1024 × 1024 (carré d'appli de 824 px centré).
func icon(_ ctx: CGContext, _ v: Int) {
    ctx.saveGState()
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    ctx.addPath(CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil)); ctx.clip()
    switch v {
    case 1:   // bistouri
        ctx.setFillColor(rgb(0x0F766E)); ctx.fill(tile)
        ctx.translateBy(x: 512, y: 512); ctx.rotate(by: .pi / 4)          // lame vers le haut à droite
        ctx.setFillColor(white)
        ctx.addPath(CGPath(roundedRect: CGRect(x: -330, y: -40, width: 360, height: 80), cornerWidth: 40, cornerHeight: 40, transform: nil)); ctx.fillPath()
        let blade = CGMutablePath()
        blade.move(to: CGPoint(x: 62, y: 40)); blade.addLine(to: CGPoint(x: 230, y: 40)); blade.addLine(to: CGPoint(x: 360, y: -30))
        blade.addQuadCurve(to: CGPoint(x: 62, y: -40), control: CGPoint(x: 190, y: -100)); blade.closeSubpath()
        ctx.addPath(blade); ctx.fillPath()
    case 2:   // crochets I / O autour d'une onde
        ctx.setFillColor(rgb(0x4338CA)); ctx.fill(tile)
        ctx.setStrokeColor(white); ctx.setLineWidth(72); ctx.setLineCap(.round); ctx.setLineJoin(.round)
        let l = CGMutablePath(); l.move(to: CGPoint(x: 340, y: 292)); l.addLine(to: CGPoint(x: 252, y: 292)); l.addLine(to: CGPoint(x: 252, y: 732)); l.addLine(to: CGPoint(x: 340, y: 732))
        let r = CGMutablePath(); r.move(to: CGPoint(x: 684, y: 292)); r.addLine(to: CGPoint(x: 772, y: 292)); r.addLine(to: CGPoint(x: 772, y: 732)); r.addLine(to: CGPoint(x: 684, y: 732))
        ctx.addPath(l); ctx.strokePath(); ctx.addPath(r); ctx.strokePath()
        ctx.setLineWidth(42)
        for (i, h) in [150.0, 290, 420, 290, 150].enumerated() {
            let x = 380 + CGFloat(i) * 66
            ctx.move(to: CGPoint(x: x, y: 512 - h / 2)); ctx.addLine(to: CGPoint(x: x, y: 512 + h / 2)); ctx.strokePath()
        }
    default:  // onde tranchée
        ctx.setFillColor(rgb(0x1D1D21)); ctx.fill(tile)
        let heights: [CGFloat] = [150, 270, 390, 310, 450, 330, 390, 210, 130]
        let a = CGPoint(x: 604, y: 800), b = CGPoint(x: 420, y: 224)
        func half(_ left: Bool) -> CGPath {
            let p = CGMutablePath(); let far: CGFloat = left ? -2000 : 2000
            p.move(to: a); p.addLine(to: b); p.addLine(to: CGPoint(x: b.x + far, y: b.y)); p.addLine(to: CGPoint(x: a.x + far, y: a.y)); p.closeSubpath(); return p
        }
        for left in [true, false] {
            ctx.saveGState(); ctx.translateBy(x: left ? -28 : 28, y: left ? -14 : 14)
            ctx.addPath(half(left)); ctx.clip()
            ctx.setStrokeColor(white); ctx.setLineWidth(46); ctx.setLineCap(.round)
            for (i, h) in heights.enumerated() {
                let x = 236 + CGFloat(i) * 69
                ctx.move(to: CGPoint(x: x, y: 512 - h / 2)); ctx.addLine(to: CGPoint(x: x, y: 512 + h / 2)); ctx.strokePath()
            }
            ctx.restoreGState()
        }
        ctx.setStrokeColor(rgb(0xFF453A)); ctx.setLineWidth(14); ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: 608, y: 790)); ctx.addLine(to: CGPoint(x: 416, y: 234)); ctx.strokePath()
    }
    ctx.restoreGState()
}

func write(_ img: CGImage, _ path: String) {
    let rep = NSBitmapImageRep(cgImage: img)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    print("OK : \(path)")
}

if variant == "planche" {
    let ctx = CGContext(data: nil, width: 1536, height: 512, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(rgb(0xE9E9EC)); ctx.fill(CGRect(x: 0, y: 0, width: 1536, height: 512))
    for i in 0 ..< 3 { ctx.saveGState(); ctx.translateBy(x: CGFloat(i) * 512, y: 0); ctx.scaleBy(x: 0.5, y: 0.5); icon(ctx, i + 1); ctx.restoreGState() }
    write(ctx.makeImage()!, out)
} else {
    let ctx = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    icon(ctx, Int(variant) ?? 1)
    write(ctx.makeImage()!, out)
}
