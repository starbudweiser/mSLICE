// mSLICE — timeline : règle avec images clés, vignettes, forme d'onde, morceaux à poignées, tête de lecture. Dessinée à la main (CoreGraphics) pour rester réactive.
import AppKit
import Combine
import SwiftUI

final class TimelineView: NSView {
    static let rulerH: CGFloat = 26, filmH: CGFloat = 42, waveH: CGFloat = 88, gap: CGFloat = 4
    static let totalH: CGFloat = rulerH + gap + filmH + gap + waveH
    /// Piste fine de résultats (onglet « Trouver ») sous la forme d'onde.
    static let laneH: CGFloat = 14
    static func height(lane: Bool, dialogues: Bool = false) -> CGFloat { totalH + (lane ? gap + laneH : 0) + (dialogues ? gap + laneH : 0) }
    private var hasLane: Bool { !(doc?.find.lane.isEmpty ?? true) }
    /// Piste « Dialogues » (onglet Dialogues) : sous la piste de résultats s'il y en a une.
    private var hasDialogueLane: Bool { doc?.dialogues.laneVisible ?? false }
    private var dialogueLaneY: CGFloat { TimelineView.totalH + TimelineView.gap + (hasLane ? TimelineView.laneH + TimelineView.gap : 0) }

    var doc: Doc? { didSet { bind() } }
    var player: PlayerModel? { didSet { bind() } }
    var snapEnabled: () -> Bool = { true }
    private var cancellables = Set<AnyCancellable>()
    private let playLayer = CALayer()
    private let bubble = CATextLayer()
    private var dragEdge: (id: UUID, start: Bool)?
    private var scrubbing = false

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true; layerContentsRedrawPolicy = .duringViewResize; clipsToBounds = true
        playLayer.backgroundColor = Theme.playheadNS.cgColor; playLayer.zPosition = 10
        bubble.fontSize = 10.5; bubble.font = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .semibold)
        bubble.alignmentMode = .center; bubble.foregroundColor = NSColor.white.cgColor
        bubble.backgroundColor = Theme.playheadNS.cgColor; bubble.cornerRadius = 5; bubble.zPosition = 11
        bubble.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        layer?.addSublayer(playLayer); layer?.addSublayer(bubble)
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Liens avec les modèles

    private func bind() {
        cancellables.removeAll()
        guard let doc, let player else { return }
        let redraw: () -> Void = { [weak self] in self?.needsDisplay = true; self?.window?.invalidateCursorRects(for: self!) }
        doc.objectWillChange.receive(on: RunLoop.main).sink { _ in redraw() }.store(in: &cancellables)
        player.$time.receive(on: RunLoop.main).sink { [weak self] t in self?.setPlayhead(t) }.store(in: &cancellables)
        doc.peaks.onChange = { [weak self] in self?.needsDisplay = true }
        doc.strip.onChange = { [weak self] in self?.needsDisplay = true }
        doc.find.$lane.receive(on: RunLoop.main).sink { _ in redraw() }.store(in: &cancellables)
        doc.dialogues.objectWillChange.receive(on: RunLoop.main).sink { _ in redraw() }.store(in: &cancellables)
        needsDisplay = true; setPlayhead(player.time)
    }

    private func x(_ t: Double) -> CGFloat {
        guard let d = doc, d.viewSpan > 0 else { return 0 }
        return CGFloat((t - d.viewStart) / d.viewSpan) * bounds.width
    }
    private func time(_ x: CGFloat) -> Double {
        guard let d = doc, bounds.width > 0 else { return 0 }
        return d.viewStart + Double(x / bounds.width) * d.viewSpan
    }

    func setPlayhead(_ t: Double) {
        guard let d = doc else { return }
        if player?.isPlaying == true, t > d.viewStart + d.viewSpan * 0.98 || t < d.viewStart { d.ensureVisible(t) }
        let px = x(t)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        playLayer.frame = CGRect(x: px - 1, y: 0, width: 2, height: max(bounds.height, TimelineView.totalH))
        let label = Fmt.time(t) as NSString
        bubble.string = label
        let w = label.size(withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 10.5, weight: .semibold)]).width + 12
        bubble.frame = CGRect(x: min(max(px - w / 2, 0), bounds.width - w), y: 4, width: w, height: 16)
        let visible = px >= -1 && px <= bounds.width + 1
        playLayer.isHidden = !visible; bubble.isHidden = !visible
        CATransaction.commit()
    }

    override func layout() { super.layout(); if let p = player { setPlayhead(p.time) } }
    /// Chaque changement de largeur redessine tout (règle, vignettes, onde, morceaux) : la timeline suit la fenêtre.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true; window?.invalidateCursorRects(for: self)
        if let p = player { setPlayhead(p.time) }
    }

    // MARK: Dessin

    private func niceStep(_ pxPerSec: Double) -> Double {
        for s in [0.1, 0.2, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600, 7200] where s * pxPerSec >= 72 { return s }
        return 7200
    }

    override func draw(_ dirty: NSRect) {
        guard let d = doc, let ctx = NSGraphicsContext.current?.cgContext, bounds.width > 1 else { return }
        let w = bounds.width
        let filmY = TimelineView.rulerH + TimelineView.gap
        let waveY = filmY + TimelineView.filmH + TimelineView.gap
        let pps = Double(w) / d.viewSpan
        let t0 = d.viewStart, t1 = d.viewStart + d.viewSpan
        let text2 = Theme.text2NS

        // Règle : repères et heures, images clés
        let step = niceStep(pps)
        let labelAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10.5), .foregroundColor: text2]
        var tick = (t0 / step).rounded(.down) * step
        ctx.setFillColor(text2.withAlphaComponent(0.9).cgColor)
        while tick <= t1 + step {
            let px = x(tick)
            if px >= -40, px <= w + 40 {
                ctx.fill(CGRect(x: px, y: TimelineView.rulerH - 9, width: 1, height: 9))
                let s = (step < 1 ? Fmt.time(tick) : Fmt.time(tick, decimals: false)) as NSString
                s.draw(at: NSPoint(x: px + 3, y: 3), withAttributes: labelAttrs)
            }
            tick += step
        }
        ctx.setFillColor(text2.withAlphaComponent(0.45).cgColor)
        var lastKX: CGFloat = -10
        for k in d.keyframes where k >= t0 && k <= t1 {
            let px = x(k)
            if px - lastKX >= 3 { ctx.fill(CGRect(x: px, y: TimelineView.rulerH - 5, width: 1, height: 5)); lastKX = px }
        }

        // Vignettes
        let filmRect = CGRect(x: 0, y: filmY, width: w, height: TimelineView.filmH)
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: filmRect, cornerWidth: 4, cornerHeight: 4, transform: nil)); ctx.clip()
        ctx.setFillColor(Theme.ctlNS.cgColor); ctx.fill(filmRect)
        if d.hasVideo {
            let n = d.strip.count
            for i in 0 ..< n {
                let a = Double(i) / Double(n) * d.duration, b = Double(i + 1) / Double(n) * d.duration
                guard b >= t0, a <= t1, let img = d.strip.image(i) else { continue }
                let rx = x(a), rw = max(x(b) - x(a), 1)
                ctx.saveGState()
                ctx.clip(to: CGRect(x: rx, y: filmY, width: rw, height: TimelineView.filmH))
                // image remplissant la hauteur, centrée sur la tuile (flux de dessin inversé : vue « flipped »)
                let ih = TimelineView.filmH, iw = ih * CGFloat(Filmstrip.w) / CGFloat(Filmstrip.h)
                let ox = rx + (rw - iw) / 2
                ctx.translateBy(x: ox, y: filmY + ih); ctx.scaleBy(x: 1, y: -1)
                ctx.draw(img, in: CGRect(x: 0, y: 0, width: iw, height: ih))
                ctx.restoreGState()
            }
        }
        ctx.restoreGState()

        // Forme d'onde
        let waveRect = CGRect(x: 0, y: waveY, width: w, height: TimelineView.waveH)
        ctx.setFillColor(Theme.textNS.withAlphaComponent(0.05).cgColor)
        ctx.addPath(CGPath(roundedRect: waveRect, cornerWidth: 4, cornerHeight: 4, transform: nil)); ctx.fillPath()
        if d.info.audio != nil {
            let norm = max(d.peaks.maxSeen * 0.9, 0.05)
            let mid = waveY + TimelineView.waveH / 2, half = TimelineView.waveH / 2 - 3
            let dimPath = CGMutablePath()
            var kept: [Int: CGMutablePath] = [:]                                       // un tracé par morceau (sa couleur)
            let ranges = d.segments.map { (x($0.start), x($0.end)) }
            let barW: CGFloat = 3, step: CGFloat = 5                                   // bâtons épais, espacés
            var px: CGFloat = 0
            while px < w {
                let v = d.peaks.peak(time(px), time(px + step))
                if v > 0 {
                    let amp = CGFloat(pow(Double(min(v / norm, 1)), 0.7)) * half
                    let r = CGRect(x: px, y: mid - max(amp, 1), width: barW, height: max(amp * 2, 2))
                    let bar = CGPath(roundedRect: r, cornerWidth: 1.2, cornerHeight: 1.2, transform: nil)
                    if let k = ranges.firstIndex(where: { px + barW / 2 >= $0.0 && px + barW / 2 <= $0.1 }) {
                        let path = kept[k] ?? CGMutablePath(); path.addPath(bar); kept[k] = path
                    } else { dimPath.addPath(bar) }
                }
                px += step
            }
            ctx.setFillColor(text2.withAlphaComponent(0.4).cgColor); ctx.addPath(dimPath); ctx.fillPath()
            for (k, path) in kept { ctx.setFillColor(Theme.segColorNS(k).cgColor); ctx.addPath(path); ctx.fillPath() }
        }

        // Piste de résultats : un trait par passage (accent), les passages écartés par SAUF en gris
        if let lane = doc?.find.lane, !lane.isEmpty {
            let laneY = waveY + TimelineView.waveH + TimelineView.gap
            let laneRect = CGRect(x: 0, y: laneY, width: w, height: TimelineView.laneH)
            ctx.setFillColor(Theme.textNS.withAlphaComponent(0.05).cgColor)
            ctx.addPath(CGPath(roundedRect: laneRect, cornerWidth: 4, cornerHeight: 4, transform: nil)); ctx.fillPath()
            ctx.saveGState(); ctx.addPath(CGPath(roundedRect: laneRect, cornerWidth: 4, cornerHeight: 4, transform: nil)); ctx.clip()
            for p in lane where p.end >= t0 && p.start <= t1 {
                let r = CGRect(x: x(p.start), y: laneY + 3, width: max(x(p.end) - x(p.start), 2), height: TimelineView.laneH - 6)
                ctx.setFillColor(p.excluded ? text2.withAlphaComponent(0.35).cgColor : Theme.accentNS.cgColor)
                ctx.addPath(CGPath(roundedRect: r, cornerWidth: 2, cornerHeight: 2, transform: nil)); ctx.fillPath()
            }
            ctx.restoreGState()
            if let f = doc?.find {
                let label = f.ordered.map(\.name).joined(separator: " · ").uppercased() as NSString
                let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 9.5, weight: .semibold), .foregroundColor: text2, .kern: 0.3]
                let sz = label.size(withAttributes: attrs)
                if sz.width < w * 0.5 {
                    let bgR = CGRect(x: w - sz.width - 12, y: laneY, width: sz.width + 10, height: TimelineView.laneH)
                    ctx.setFillColor(Theme.cardNS.withAlphaComponent(0.85).cgColor); ctx.fill(bgR)
                    label.draw(at: NSPoint(x: bgR.minX + 5, y: laneY + (TimelineView.laneH - sz.height) / 2), withAttributes: attrs)
                }
            }
        }

        // Piste « Dialogues » : un trait par réplique, de la couleur de son personnage, les écartées en gris, la réplique choisie cerclée
        if let dl = doc?.dialogues, dl.laneVisible {
            let laneY = dialogueLaneY
            let laneRect = CGRect(x: 0, y: laneY, width: w, height: TimelineView.laneH)
            ctx.setFillColor(Theme.textNS.withAlphaComponent(0.05).cgColor)
            ctx.addPath(CGPath(roundedRect: laneRect, cornerWidth: 4, cornerHeight: 4, transform: nil)); ctx.fillPath()
            ctx.saveGState(); ctx.addPath(CGPath(roundedRect: laneRect, cornerWidth: 4, cornerHeight: 4, transform: nil)); ctx.clip()
            for l in dl.lane where l.end >= t0 && l.start <= t1 {
                let r = CGRect(x: x(l.start), y: laneY + 3, width: max(x(l.end) - x(l.start) - 1, 2), height: TimelineView.laneH - 6)
                ctx.setFillColor(l.discarded ? text2.withAlphaComponent(0.35).cgColor : dl.nsColor(l).cgColor)
                ctx.addPath(CGPath(roundedRect: r, cornerWidth: 2, cornerHeight: 2, transform: nil)); ctx.fillPath()
                if l.id == dl.selected { ctx.setStrokeColor(Theme.textNS.cgColor); ctx.setLineWidth(1.5); ctx.addPath(CGPath(roundedRect: r.insetBy(dx: -1, dy: -1.5), cornerWidth: 3, cornerHeight: 3, transform: nil)); ctx.strokePath() }
            }
            ctx.restoreGState()
            let label = L.t("dlg.lane").uppercased() as NSString
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 9.5, weight: .semibold), .foregroundColor: text2, .kern: 0.3]
            let sz = label.size(withAttributes: attrs)
            if sz.width < w * 0.5 {
                let bgR = CGRect(x: w - sz.width - 12, y: laneY, width: sz.width + 10, height: TimelineView.laneH)
                ctx.setFillColor(Theme.cardNS.withAlphaComponent(0.85).cgColor); ctx.fill(bgR)
                label.draw(at: NSPoint(x: bgR.minX + 5, y: laneY + (TimelineView.laneH - sz.height) / 2), withAttributes: attrs)
            }
        }

        // Zones retirées : voile + hachures
        let bodyTop = filmY, bodyH = TimelineView.filmH + TimelineView.gap + TimelineView.waveH
        var edges: [Double] = [0] + d.segments.flatMap { [$0.start, $0.end] } + [d.duration]
        if d.segments.isEmpty { edges = [0, d.duration] }
        ctx.setFillColor(Theme.cardNS.withAlphaComponent(0.62).cgColor)
        for k in stride(from: 0, to: edges.count, by: 2) where edges[k + 1] > edges[k] {
            let r = CGRect(x: x(edges[k]), y: bodyTop, width: x(edges[k + 1]) - x(edges[k]), height: bodyH).intersection(CGRect(x: 0, y: bodyTop, width: w, height: bodyH))
            guard !r.isNull, r.width > 0 else { continue }
            ctx.fill(r)
            ctx.saveGState(); ctx.clip(to: r)
            ctx.setStrokeColor(NSColor.gray.withAlphaComponent(0.17).cgColor); ctx.setLineWidth(1)
            var hx = r.minX - bodyH
            while hx < r.maxX { ctx.move(to: CGPoint(x: hx, y: r.maxY)); ctx.addLine(to: CGPoint(x: hx + bodyH, y: r.minY)); hx += 6 }
            ctx.strokePath(); ctx.restoreGState()
        }

        // Entrée posée, en attente de sortie
        if let p = d.pendingIn {
            let a = x(p), b = x(player?.time ?? p)
            let r = CGRect(x: min(a, b), y: bodyTop, width: abs(b - a), height: bodyH)
            ctx.setFillColor(Theme.segNS.withAlphaComponent(0.14).cgColor); ctx.fill(r)
            ctx.setFillColor(Theme.segNS.cgColor); ctx.fill(CGRect(x: a - 1.5, y: bodyTop, width: 3, height: bodyH))
            flag("I", at: CGPoint(x: a + 4, y: bodyTop + 4), ctx)
        }

        // Morceaux
        for (i, s) in d.segments.enumerated() {
            let sx = x(s.start), ex = x(s.end)
            guard ex >= 0, sx <= w else { continue }
            let sel = s.id == d.selected
            let c = Theme.segColorNS(i)
            let r = CGRect(x: sx, y: bodyTop, width: ex - sx, height: bodyH)
            ctx.setFillColor(c.withAlphaComponent(sel ? 0.18 : 0.12).cgColor); ctx.fill(r)
            ctx.setStrokeColor(c.withAlphaComponent(sel ? 1 : 0.55).cgColor); ctx.setLineWidth(sel ? 1.5 : 1); ctx.stroke(r.insetBy(dx: 0.75, dy: 0.75))
            ctx.setFillColor(c.cgColor)
            ctx.fill(CGRect(x: sx, y: bodyTop, width: 3, height: bodyH)); ctx.fill(CGRect(x: ex - 3, y: bodyTop, width: 3, height: bodyH))
            if sel {
                for gx in [sx + 1.5, ex - 1.5] {
                    let g = CGRect(x: gx - 4, y: bodyTop + bodyH / 2 - 15, width: 8, height: 30)
                    ctx.setFillColor(c.cgColor); ctx.addPath(CGPath(roundedRect: g, cornerWidth: 3, cornerHeight: 3, transform: nil)); ctx.fillPath()
                }
            }
            if r.width >= 44 { badge("\(i + 1)", center: CGPoint(x: (sx + ex) / 2, y: bodyTop + 14), color: c, ctx) }
            if sel, r.width >= 96 { flag("I", at: CGPoint(x: sx + 8, y: bodyTop + 4), ctx); flag("O", at: CGPoint(x: ex - 26, y: bodyTop + 4), ctx) }
        }
    }

    private func badge(_ s: String, center c: CGPoint, color: NSColor, _ ctx: CGContext) {
        ctx.setFillColor(color.cgColor); ctx.fillEllipse(in: CGRect(x: c.x - 10, y: c.y - 10, width: 20, height: 20))
        let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: .bold), .foregroundColor: NSColor.white]
        let sz = (s as NSString).size(withAttributes: a)
        (s as NSString).draw(at: NSPoint(x: c.x - sz.width / 2, y: c.y - sz.height / 2), withAttributes: a)
    }
    private func flag(_ s: String, at p: CGPoint, _ ctx: CGContext) {
        let r = CGRect(x: p.x, y: p.y, width: 18, height: 18)
        ctx.setFillColor(NSColor.white.cgColor); ctx.addPath(CGPath(roundedRect: r, cornerWidth: 5, cornerHeight: 5, transform: nil)); ctx.fillPath()
        let a: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .bold), .foregroundColor: NSColor(white: 0.07, alpha: 1)]
        let sz = (s as NSString).size(withAttributes: a)
        (s as NSString).draw(at: NSPoint(x: r.midX - sz.width / 2, y: r.midY - sz.height / 2), withAttributes: a)
    }

    // MARK: Souris

    private func hitEdge(_ px: CGFloat) -> (UUID, Bool)? {
        guard let d = doc else { return nil }
        var best: (UUID, Bool, CGFloat)?
        for s in d.segments {
            for (isStart, ex) in [(true, x(s.start)), (false, x(s.end))] {
                let dist = abs(px - ex)
                if dist <= 7, dist < (best?.2 ?? 99) || (s.id == d.selected && dist <= (best?.2 ?? 99)) { best = (s.id, isStart, dist) }
            }
        }
        return best.map { ($0.0, $0.1) }
    }

    override func resetCursorRects() {
        guard let d = doc else { return }
        for s in d.segments { for ex in [x(s.start), x(s.end)] { addCursorRect(CGRect(x: ex - 6, y: 0, width: 12, height: bounds.height), cursor: .resizeLeftRight) } }
    }

    override func mouseDown(with e: NSEvent) {
        guard let d = doc, let p = player else { return }
        let pt = convert(e.locationInWindow, from: nil)
        if let (id, start) = hitEdge(pt.x) {
            d.snapshot(); dragEdge = (id, start); d.selected = id; return
        }
        let t = time(pt.x)
        let laneY = TimelineView.totalH + TimelineView.gap
        if hasLane, pt.y >= laneY - 2, let hit = d.find.lane.first(where: { t >= $0.start - 3 * d.viewSpan / Double(max(bounds.width, 1)) && t <= $0.end + 3 * d.viewSpan / Double(max(bounds.width, 1)) }) {
            p.pause(); p.seek(hit.start); scrubbing = false; return           // un clic sur un passage amène la tête de lecture à son début
        }
        if hasDialogueLane, pt.y >= dialogueLaneY - 2 {
            let tol = 5 * d.viewSpan / Double(max(bounds.width, 1))
            if let hit = d.dialogues.lane.first(where: { t >= $0.start - tol && t <= $0.end + tol }) {
                p.pause(); p.seek(hit.start); d.dialogues.select(hit.id, seek: false); scrubbing = false; return       // un clic sur une réplique amène la tête de lecture à son début
            }
        }
        if pt.y > TimelineView.rulerH, let s = d.segment(at: t) { d.selected = s.id }
        scrubbing = true; p.pause(); p.seek(t, precise: false)
    }

    override func mouseDragged(with e: NSEvent) {
        guard let d = doc, let p = player else { return }
        let pt = convert(e.locationInWindow, from: nil)
        let t = min(max(time(pt.x), 0), d.duration)
        if let de = dragEdge {
            d.moveEdge(de.id, start: de.start, to: t, snap: snapEnabled())
            if let s = d.segments.first(where: { $0.id == de.id }) { p.seek(de.start ? s.start : max(s.end - p.frameDuration, 0), precise: false) }
        } else if scrubbing {
            p.seek(t, precise: false)
            if pt.x < 0 || pt.x > bounds.width { d.viewStart += (pt.x < 0 ? -1 : 1) * d.viewSpan * 0.02; d.clampView() }
        }
    }

    /// Pendant le glissement l'aperçu saute sur l'image clé voisine (instantané) ; au relâchement, positionnement exact à l'image.
    override func mouseUp(with e: NSEvent) {
        if scrubbing || dragEdge != nil, let p = player { p.seek(p.time, precise: true) }
        dragEdge = nil; scrubbing = false
    }

    override func scrollWheel(with e: NSEvent) {
        guard let d = doc else { return }
        let scale: CGFloat = e.hasPreciseScrollingDeltas ? 1 : 8
        if e.modifierFlags.contains(.command) || e.modifierFlags.contains(.option) {
            let t = time(convert(e.locationInWindow, from: nil).x)
            d.zoom(by: exp(Double(e.scrollingDeltaY * scale) * 0.01), around: t)
        } else {
            let delta = abs(e.scrollingDeltaX) > abs(e.scrollingDeltaY) ? e.scrollingDeltaX : e.scrollingDeltaY
            d.viewStart -= Double(delta * scale) * d.viewSpan / Double(max(bounds.width, 1)); d.clampView()
        }
    }

    // Bouton de la molette (clic du milieu) maintenu enfoncé : on « attrape » la timeline zoomée et on la glisse à gauche ou à droite.
    private var panning: (x: CGFloat, start: Double)?

    override func otherMouseDown(with e: NSEvent) {
        guard e.buttonNumber == 2, let d = doc else { super.otherMouseDown(with: e); return }
        panning = (convert(e.locationInWindow, from: nil).x, d.viewStart)
        NSCursor.closedHand.push()
    }

    override func otherMouseDragged(with e: NSEvent) {
        guard let d = doc, let p = panning else { super.otherMouseDragged(with: e); return }
        let dx = convert(e.locationInWindow, from: nil).x - p.x
        d.viewStart = p.start - Double(dx) * d.viewSpan / Double(max(bounds.width, 1)); d.clampView()
    }

    override func otherMouseUp(with e: NSEvent) {
        guard panning != nil else { super.otherMouseUp(with: e); return }
        panning = nil
        NSCursor.pop()
    }

    override func magnify(with e: NSEvent) {
        guard let d = doc else { return }
        d.zoom(by: 1 + Double(e.magnification), around: time(convert(e.locationInWindow, from: nil).x))
    }
}

struct TimelineRepresentable: NSViewRepresentable {
    let doc: Doc
    let player: PlayerModel
    let snap: Bool
    func makeNSView(context: Context) -> TimelineView {
        let v = TimelineView(frame: .zero); v.player = player; v.doc = doc; v.snapEnabled = { snap }; return v
    }
    func updateNSView(_ v: TimelineView, context: Context) {
        v.snapEnabled = { snap }
        if v.doc !== doc { v.doc = doc }
        if v.player !== player { v.player = player }
    }
}
