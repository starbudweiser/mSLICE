// mSLICE — fenêtre « À propos », d'après le modèle de Socle (swift/AboutWindow.swift, section « Fenêtre « À propos » ») :
// colonne centrée de 300 px de texte entre deux marges de 28 px, barre de titre de 30 px (`surfaceRaised`, filet `border`),
// jetons Socle.C, hauteur calculée d'après le contenu, bouton de fermeture seul, une seule instance centrée sur la fenêtre de l'appli.
import AppKit
import SwiftUI

/// Aplat de couleur dynamique (suit le thème clair/sombre de l'appli).
private final class FillView: NSView {
    let fill: NSColor
    init(_ fill: NSColor) { self.fill = fill; super.init(frame: .zero); wantsLayer = true }
    required init?(coder: NSCoder) { fatalError() }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() { effectiveAppearance.performAsCurrentDrawingAppearance { layer?.backgroundColor = fill.cgColor } }
    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }
}

@MainActor
enum About {
    private static var window: NSWindow?
    static let sideMargin: CGFloat = 28
    static let textWidth: CGFloat = 300

    static func show() {
        if window == nil { window = makeWindow() }
        guard let w = window else { return }
        centerWindow(w)
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    /// Centrée sur la fenêtre de l'appli (règle Socle « Fenêtres secondaires centrées sur la fenêtre de l'appli »).
    private static func centerWindow(_ w: NSWindow) {
        if let host = NSApp.windows.first(where: { $0 !== w && $0.isVisible && $0.canBecomeMain }) {
            let f = host.frame
            w.setFrameOrigin(NSPoint(x: f.midX - w.frame.width / 2, y: f.midY - w.frame.height / 2)); return
        }
        w.center()
    }

    private static func label(_ text: String, size: CGFloat = 12, bold: Bool = false, secondary: Bool = false, brand: Bool = false) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        let color: NSColor = secondary ? NSColor(Socle.C.textMuted) : (bold ? NSColor(Socle.C.textStrong) : NSColor(Socle.C.text))
        let a = NSMutableAttributedString(string: text, attributes: [.font: bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size), .paragraphStyle: paragraph, .foregroundColor: color])
        if brand { a.addAttribute(.foregroundColor, value: Theme.brandNS, range: NSRange(location: 0, length: 1)) }     // « m » du nom, en couleur
        field.attributedStringValue = a
        field.alignment = .center
        field.preferredMaxLayoutWidth = textWidth
        field.isSelectable = false
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(lessThanOrEqualToConstant: textWidth).isActive = true
        return field
    }

    private static let supportURL = URL(string: "https://github.com/sponsors/starbudweiser")!
    private final class SupportOpener: NSObject { @objc func go() { NSWorkspace.shared.open(About.supportURL) } }
    private static let supportOpener = SupportOpener()

    /// Lien « ♥ Soutenir le projet » : 12 px `text`, souligné ; facultatif et discret.
    private static func supportLink() -> NSButton {
        let title = NSAttributedString(string: "♥ " + L.t("about.support"), attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor(Socle.C.text), .underlineStyle: NSUnderlineStyle.single.rawValue])
        let b = NSButton(title: "", target: supportOpener, action: #selector(SupportOpener.go))
        b.isBordered = false; b.attributedTitle = title
        return b
    }

    static func makeWindow() -> NSWindow {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"

        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 84).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 84).isActive = true

        let views: [NSView] = [
            icon,
            label("mSLICE", size: 17, bold: true, brand: true),
            label(L.t("about.version", version, build), secondary: true),
            label(L.t("about.tagline")),
            label("Starbudweiser & Claude Code (Anthropic)", bold: true),
            label(L.t("about.license")),
            label(L.t("about.disclaimer"), secondary: true),
            label(L.t("about.credit"), secondary: true),
            label(L.t("about.collection"), secondary: true),
            supportLink(),
        ]
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.setCustomSpacing(6, after: views[1])     // nom → version
        stack.setCustomSpacing(18, after: views[2])    // version → description
        stack.edgeInsets = NSEdgeInsets(top: 28, left: sideMargin, bottom: 28, right: sideMargin)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: textWidth + 2 * sideMargin).isActive = true     // largeur fixe : mêmes marges dans les quatre langues

        let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.title = L.t("menu.about")
        w.isReleasedWhenClosed = false
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.standardWindowButton(.miniaturizeButton)?.isHidden = true      // bouton de fermeture seul
        w.standardWindowButton(.zoomButton)?.isHidden = true
        w.backgroundColor = NSColor(Socle.C.bg)
        let content = FillView(NSColor(Socle.C.bg))
        let bar = FillView(NSColor(Socle.C.surfaceRaised)); bar.translatesAutoresizingMaskIntoConstraints = false      // barre de titre Socle de 30 px
        let rule = FillView(NSColor(Socle.C.border)); rule.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack); content.addSubview(bar); bar.addSubview(rule)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: content.topAnchor), bar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor), bar.heightAnchor.constraint(equalToConstant: 30),
            rule.leadingAnchor.constraint(equalTo: bar.leadingAnchor), rule.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            rule.bottomAnchor.constraint(equalTo: bar.bottomAnchor), rule.heightAnchor.constraint(equalToConstant: 1),
            stack.topAnchor.constraint(equalTo: bar.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor), stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        w.contentView = content
        content.layoutSubtreeIfNeeded()
        content.layoutSubtreeIfNeeded()      // les textes à la ligne ne connaissent leur hauteur qu'après une première passe
        w.setContentSize(content.fittingSize)
        return w
    }

    /// Audit des marges : aucun texte ne doit toucher le bord (28 px de chaque côté) ni un autre bloc. Renvoie les anomalies.
    static func audit(_ w: NSWindow) -> [String] {
        guard let content = w.contentView else { return ["pas de contenu"] }
        content.layoutSubtreeIfNeeded()
        var problems: [String] = []
        func walk(_ v: NSView) {
            for s in v.subviews {
                if let t = s as? NSTextField {
                    let f = s.convert(s.bounds, to: content).insetBy(dx: 2, dy: 0)      // le champ ajoute 2 px de chaque côté autour du texte
                    if f.minX < sideMargin - 0.5 || f.maxX > content.bounds.width - sideMargin + 0.5 { problems.append("« \(t.stringValue.prefix(24))… » déborde des marges (\(Int(f.minX)) → \(Int(f.maxX)) sur \(Int(content.bounds.width)))") }
                    if t.intrinsicContentSize.width > textWidth + 0.5 { problems.append("« \(t.stringValue.prefix(24))… » plus large que la colonne") }
                }
                if let b = s as? NSButton, b.attributedTitle.length > 0 {
                    let f = s.convert(s.bounds, to: content)
                    if f.minX < sideMargin - 0.5 || f.maxX > content.bounds.width - sideMargin + 0.5 { problems.append("lien « \(b.attributedTitle.string.prefix(24)) » déborde des marges") }
                }
                walk(s)
            }
        }
        walk(content)
        return problems
    }
}
