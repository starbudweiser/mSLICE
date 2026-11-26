// mSLICE — design Flat Mat (Socle) : surfaces mates, filets fins, accent encre (clair) ou bleu système (sombre), morceaux orange.
import AppKit
import SwiftUI

enum Theme {
    static func dyn(_ dark: UInt32, _ light: UInt32) -> NSColor {
        NSColor(name: nil) { a in
            let isDark = a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return rgb(isDark ? dark : light)
        }
    }
    static func rgb(_ v: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: alpha)
    }

    // Surfaces (sombre / clair)
    static let bgNS = dyn(0x131316, 0xf4f1ec)           // fond de fenêtre
    static let cardNS = dyn(0x1c1c1f, 0xffffff)         // cartes de contenu
    static let ctlNS = dyn(0x2c2c31, 0xebe6de)          // contrôles, champs
    static let lineNS = dyn(0x303035, 0xe3ddd2)         // filets
    static let textNS = dyn(0xf5f5f7, 0x26231e)
    static let text2NS = dyn(0x98989f, 0x7b756a)
    static let accentNS = dyn(0x0a84ff, 0x26231e)       // choix actifs : bleu système (sombre), encre (clair)
    static let onAccentNS = dyn(0xffffff, 0xf4f1ec)
    static let brandNS = dyn(0xf08a52, 0xd9622b)        // lettre « m » du nom
    static let segNS = dyn(0xf08a52, 0xd9622b)          // morceaux sur la timeline
    static let okNS = dyn(0x30d158, 0x3f8f5a)
    static let warnNS = dyn(0xff9f0a, 0xb7791f)
    static let dangerNS = rgb(0xff453a)
    static let playheadNS = rgb(0xff453a)
    static let sandNS = rgb(0xe8a257)                   // bouton principal « Extraire »
    static let onSandNS = rgb(0x2a1d0c)
    static let mediaNS = rgb(0x0c0c0e)

    static let bg = Color(nsColor: bgNS), card = Color(nsColor: cardNS), ctl = Color(nsColor: ctlNS), line = Color(nsColor: lineNS)
    static let text = Color(nsColor: textNS), text2 = Color(nsColor: text2NS)
    static let accent = Color(nsColor: accentNS), onAccent = Color(nsColor: onAccentNS)
    static let brand = Color(nsColor: brandNS), seg = Color(nsColor: segNS)
    static let ok = Color(nsColor: okNS), warn = Color(nsColor: warnNS), danger = Color(nsColor: dangerNS)
    static let sand = Color(nsColor: sandNS), onSand = Color(nsColor: onSandNS)
    static let media = Color(nsColor: mediaNS)

    // Mesures
    static let rWindow: CGFloat = 12, rCard: CGFloat = 12, rControl: CGFloat = 8
    static let barHeight: CGFloat = 48, controlHeight: CGFloat = 30
    static let sidebarWidth: CGFloat = 232, rightWidth: CGFloat = 320
}

/// Pose le thème choisi (clair, sombre, automatique) sur toute l'appli.
enum Appearance: String, CaseIterable {
    case auto, light, dark
    var title: String { L.t("appearance." + rawValue) }
    func apply() { NSApp.appearance = self == .auto ? nil : NSAppearance(named: self == .dark ? .darkAqua : .aqua) }
}

// MARK: Composants de base

struct Card<Content: View>: View {
    var padding: CGFloat = 12
    var spacing: CGFloat = 8
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous).strokeBorder(Theme.line, lineWidth: 0.5))
    }
}

struct SectionTitle: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View { Text(text.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.4).foregroundStyle(Theme.text2) }
}

/// Étiquette (pilule) : sur sa propre ligne, alignée à droite dans les listes.
struct Tag: View {
    enum Kind { case plain, accent, ok, warn }
    let text: String; var kind: Kind = .plain; var symbol: String? = nil
    var body: some View {
        HStack(spacing: 3) {
            Text(text)
            if let s = symbol { Image(systemName: s).font(.system(size: 8.5, weight: .bold)) }
        }
        .font(.system(size: 10.5, weight: .semibold)).lineLimit(1)
        .padding(.horizontal, 8).frame(height: 18)
        .foregroundStyle(fg).background(bg, in: Capsule())
    }
    private var fg: Color { switch kind { case .plain: Theme.text2; case .accent: Theme.onAccent; case .ok: Theme.ok; case .warn: Theme.warn } }
    private var bg: Color { switch kind { case .plain: Theme.ctl; case .accent: Theme.accent; case .ok: Theme.ok.opacity(0.22); case .warn: Theme.warn.opacity(0.22) } }
}

/// Bouton plat : 30 pt de haut, texte centré dans la hauteur (règle d'alignement de Socle).
struct FlatButton: ButtonStyle {
    enum Kind { case normal, primary, sand }
    var kind: Kind = .normal
    var height: CGFloat = Theme.controlHeight
    func makeBody(configuration c: Configuration) -> some View {
        c.label
            .font(.system(size: 12.5, weight: kind == .normal ? .medium : .semibold)).lineLimit(1).minimumScaleFactor(0.8)
            .padding(.horizontal, 12).frame(height: height)
            .foregroundStyle(fg).background(bg, in: RoundedRectangle(cornerRadius: Theme.rControl, style: .continuous))
            .opacity(c.isPressed ? 0.8 : 1)
    }
    private var fg: Color { switch kind { case .normal: Theme.text; case .primary: Theme.onAccent; case .sand: Theme.onSand } }
    private var bg: Color { switch kind { case .normal: Theme.ctl; case .primary: Theme.accent; case .sand: Theme.sand } }
}

/// Touche (I, O, Espace…) : capsule à fond de contrôle.
struct Key: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View {
        Text(text).font(.system(size: 11, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 5).frame(minWidth: 20, minHeight: 18)
            .background(Theme.ctl, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Theme.text2.opacity(0.35), lineWidth: 0.5))
    }
}

struct Chip: View {
    let text: String; var on = false; var enabled = true
    var body: some View {
        HStack(spacing: 5) {
            if on { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)) }
            Text(text).lineLimit(1)
        }
        .font(.system(size: 11.5, weight: on ? .semibold : .regular))
        .padding(.horizontal, 10).frame(height: 24)
        .foregroundStyle(on ? Theme.onAccent : Theme.text).background(on ? Theme.accent : Theme.ctl, in: Capsule())
        .opacity(enabled ? 1 : 0.45)
    }
}

/// Choix segmenté (deux ou trois options) : capsule, option active en accent.
struct Segmented<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    /// Onglets du panneau de droite : fond de carte et filet, 28 pt de haut (maquette ergonomie.html).
    var tabs = false
    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { i in
                let (v, label) = options[i]
                Button { selection = v } label: {
                    Text(label).font(.system(size: 12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity).frame(height: tabs ? 28 : 26)
                        .foregroundStyle(selection == v ? Theme.onAccent : Theme.text2)
                        .background(selection == v ? Theme.accent : .clear, in: Capsule())
                }.buttonStyle(.plain)
            }
        }
        .padding(3).background(tabs ? Theme.card : Theme.ctl, in: Capsule())
        .overlay { if tabs { Capsule().strokeBorder(Theme.line, lineWidth: 0.5) } }
    }
}

/// Engrenage de la maquette : un disque central et huit rayons (barre de titre).
struct GearGlyph: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let s = min(r.width, r.height) / 16, ox = r.minX, oy = r.minY
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
        p.addEllipse(in: CGRect(x: ox + 5.8 * s, y: oy + 5.8 * s, width: 4.4 * s, height: 4.4 * s))
        for (a, b) in [((8.0, 1.8), (8.0, 3.4)), ((8.0, 12.6), (8.0, 14.2)), ((1.8, 8.0), (3.4, 8.0)), ((12.6, 8.0), (14.2, 8.0)),
                       ((3.6, 3.6), (4.7, 4.7)), ((11.3, 11.3), (12.4, 12.4)), ((3.6, 12.4), (4.7, 11.3)), ((11.3, 4.7), (12.4, 3.6))] {
            p.move(to: pt(a.0, a.1)); p.addLine(to: pt(b.0, b.1))
        }
        return p
    }
}

/// Barres de voix de la maquette (avatar d'une voix sans visage, bouton « voix seules »).
struct WaveGlyph: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let s = min(r.width, r.height) / 16, ox = r.minX, oy = r.minY
        for (x, y1, y2) in [(2.0, 6.0, 10.0), (5.0, 3.5, 12.5), (8.0, 5.5, 10.5), (11.0, 2.5, 13.5), (14.0, 6.0, 10.0)] {
            p.move(to: CGPoint(x: ox + x * s, y: oy + y1 * s)); p.addLine(to: CGPoint(x: ox + x * s, y: oy + y2 * s))
        }
        return p
    }
}

/// Réglages d'export de la maquette : deux curseurs.
struct SlidersGlyph: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let s = min(r.width, r.height) / 16, ox = r.minX, oy = r.minY
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
        for (a, b) in [((2.0, 4.0), (9.0, 4.0)), ((12.0, 4.0), (14.0, 4.0)), ((2.0, 12.0), (4.0, 12.0)), ((7.0, 12.0), (14.0, 12.0))] { p.move(to: pt(a.0, a.1)); p.addLine(to: pt(b.0, b.1)) }
        p.addEllipse(in: CGRect(x: ox + 9 * s, y: oy + 2.5 * s, width: 3 * s, height: 3 * s))
        p.addEllipse(in: CGRect(x: ox + 4 * s, y: oy + 10.5 * s, width: 3 * s, height: 3 * s))
        return p
    }
}

/// Encadré d'information teinté (maquette : fond ambre à 14 %).
struct InfoBox<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: 10) { content }
            .padding(.horizontal, 10).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.warn.opacity(0.14), in: RoundedRectangle(cornerRadius: Theme.rControl, style: .continuous))
    }
}

/// Interrupteur plat aux couleurs du thème.
struct FlatSwitch: View {
    @Binding var isOn: Bool
    var body: some View {
        Button { isOn.toggle() } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? Theme.accent : Theme.ctl).frame(width: 34, height: 20)
                Circle().fill(.white).frame(width: 16, height: 16).shadow(color: .black.opacity(0.3), radius: 1, y: 1).padding(2)
            }
        }.buttonStyle(.plain).animation(.easeOut(duration: 0.12), value: isOn)
    }
}

/// Dessin du bistouri (monochrome, simple).
struct ScalpelShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let s = min(r.width, r.height) / 24, ox = r.minX, oy = r.minY
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
        p.move(to: pt(3, 21)); p.addLine(to: pt(14, 10))
        p.move(to: pt(14, 10)); p.addLine(to: pt(19, 5))
        p.addQuadCurve(to: pt(22, 8), control: pt(21.2, 3.2)); p.addLine(to: pt(17, 13)); p.closeSubpath()
        return p
    }
}
