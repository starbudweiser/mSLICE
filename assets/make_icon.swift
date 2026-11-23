// mSLICE — dessine l'icône d'appli (plate : fond uni, un seul motif, sans ombre ni reflet ni contour) en PNG 1024.
// Usage : swift assets/make_icon.swift assets/icon-1024.png
// Motif : une bande (un fichier) tranchée en deux par une coupe en biais, les deux morceaux légèrement écartés.
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
let S: CGFloat = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }

func rgb(_ v: UInt32) -> CGColor { CGColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: 1) }

// Carré d'appli (824 px centré, coins continus)
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil)
ctx.addPath(tilePath); ctx.clip()
ctx.setFillColor(rgb(0xE8A257)); ctx.fill(tile)               // orange sable

// Bande tranchée
let strip = CGRect(x: 232, y: 372, width: 560, height: 280)
let stripPath = CGPath(roundedRect: strip, cornerWidth: 44, cornerHeight: 44, transform: nil)
// ligne de coupe : de (576, 760) à (448, 264) ; demi-plans à gauche et à droite
let a = CGPoint(x: 590, y: 780), b = CGPoint(x: 434, y: 244)
func halfPlane(left: Bool) -> CGPath {
    let p = CGMutablePath()
    let far: CGFloat = left ? -2000 : 2000
    p.move(to: a); p.addLine(to: b); p.addLine(to: CGPoint(x: b.x + far, y: b.y)); p.addLine(to: CGPoint(x: a.x + far, y: a.y)); p.closeSubpath()
    return p
}
for left in [true, false] {
    ctx.saveGState()
    ctx.translateBy(x: left ? -22 : 22, y: left ? -12 : 12)
    ctx.addPath(halfPlane(left: left)); ctx.clip()
    ctx.addPath(stripPath); ctx.setFillColor(rgb(0x2A1D0C)); ctx.fillPath()
    ctx.restoreGState()
}

let img = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: img)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("OK : \(out)")
