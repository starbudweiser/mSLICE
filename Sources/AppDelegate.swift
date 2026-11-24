// mSLICE — cycle de vie, fenêtre principale, menus, ouverture depuis le Finder (fichiers et mslice://), essais sans fenêtre (`--capture`).
import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?
    var window: NSWindow?
    var settingsWindow: NSWindow?
    var aboutWindow: NSWindow?
    var batchWindow: NSWindow?
    let args = CommandLine.arguments
    var launched = false
    var queued: [URL] = []
    func arg(_ name: String) -> String? { args.firstIndex(of: name).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } }
    var silent: Bool { args.contains("--silent") || arg("--capture") != nil || arg("--selftest-ui") != nil }

    func applicationWillFinishLaunching(_ n: Notification) {
        AppDelegate.shared = self
        (Appearance(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "") ?? .dark).apply()
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        launched = true
        let model = AppModel.shared
        if let t = arg("--theme"), let a = Appearance(rawValue: t) { a.apply() }
        buildMenu()
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in MainActor.assumeIsolated { model.handleKey(e) ? nil : e } }
        UpdateEngine.shared.configure(repo: "mSLICE", lang: { L.lang == .fr ? "fr" : L.lang == .es ? "es" : L.lang == .it ? "it" : "en" }, brandName: "mSLICE")
        UpdateEngine.shared.autoInstall = { UserDefaults.standard.object(forKey: "autoUpdate") == nil || UserDefaults.standard.bool(forKey: "autoUpdate") }
        if !AppModel.isDev, !silent { UpdateEngine.shared.start() }
        if !silent, !AppModel.isDev { DispatchQueue.global(qos: .utility).async { if !FinderExtension.isEnabled() { FinderExtension.enable() } } }

        if let f = arg("--selftest-ui") {
            model.testMode = true; openMainWindow(show: false)
            Task { @MainActor in exit(await UITest.run(path: f, delegate: self)) }
            return
        }
        if let out = arg("--capture") {
            openMainWindow(show: false)
            let files = args.enumerated().filter { $0.element == "--open" && args.indices.contains($0.offset + 1) }.map { URL(fileURLWithPath: args[$0.offset + 1]) }
            model.open(files)
            capture(to: out); return
        }
        openMainWindow(show: true)
        if !queued.isEmpty { handle(queued); queued = [] }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ app: NSApplication, hasVisibleWindows flag: Bool) -> Bool { if !flag { openMainWindow(show: true) }; return true }

    // MARK: Ouverture (Finder : « Ouvrir avec », glisser sur l'icône, mslice://)

    func application(_ application: NSApplication, open urls: [URL]) {
        if launched { handle(urls) } else { queued += urls }
    }

    /// `mslice://open?f=<chemin>&f=…` ouvre l'éditeur ; `mslice://trim?f=…` ouvre l'élagage en lot ; un fichier seul s'ouvre dans l'éditeur.
    func handle(_ urls: [URL]) {
        var files: [URL] = [], trim: [URL] = []
        for u in urls {
            if u.isFileURL { files.append(u); continue }
            guard u.scheme == "mslice" || u.scheme == "mslice-dev", let c = URLComponents(url: u, resolvingAgainstBaseURL: false) else { continue }
            let paths = (c.queryItems ?? []).filter { $0.name == "f" }.compactMap { $0.value }.map { URL(fileURLWithPath: $0) }
            if c.host == "trim" { trim += paths } else { files += paths }
        }
        if !files.isEmpty { openMainWindow(show: true); AppModel.shared.open(files) }
        if !trim.isEmpty { openBatch(trim) }
    }

    // MARK: Fenêtres

    func openMainWindow(show: Bool) {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true; w.titleVisibility = .hidden
            w.minSize = NSSize(width: 1180, height: 720)
            w.backgroundColor = Theme.bgNS
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: MainView(model: AppModel.shared).ignoresSafeArea())
            w.setFrameAutosaveName("")
            centerHigh(w)
            window = w; AppModel.shared.mainWindow = w
            for n in [NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification, NSWindow.didExitFullScreenNotification, NSWindow.didEnterFullScreenNotification] {
                NotificationCenter.default.addObserver(forName: n, object: w, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.layoutTrafficLights() } }
            }
        }
        guard show else { return }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        layoutTrafficLights(); DispatchQueue.main.async { self.layoutTrafficLights() }
    }

    /// Boutons de fenêtre centrés dans notre barre de 48 pt (même axe que le nom et les boutons de la barre).
    func layoutTrafficLights() {
        guard let w = window, let close = w.standardWindowButton(.closeButton), let mini = w.standardWindowButton(.miniaturizeButton), let zoom = w.standardWindowButton(.zoomButton),
              let container = close.superview?.superview, !w.styleMask.contains(.fullScreen) else { return }
        let h = Theme.barHeight
        var f = container.frame; f.size.height = h; f.origin.y = w.frame.height - h; container.frame = f
        for (i, b) in [close, mini, zoom].enumerated() { var bf = b.frame; bf.origin.x = 16 + CGFloat(i) * 20; bf.origin.y = (h - bf.height) / 2; b.frame = bf }
    }

    func centerHigh(_ w: NSWindow) {
        guard let s = NSScreen.main?.visibleFrame else { w.center(); return }
        w.setFrameOrigin(NSPoint(x: s.midX - w.frame.width / 2, y: s.midY - w.frame.height / 2 + s.height * 0.03))
    }

    func panel(_ size: NSSize, title: String = "", _ view: NSView, store: inout NSWindow?) {
        store?.close()
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true; w.titleVisibility = .hidden; w.backgroundColor = Theme.bgNS; w.isReleasedWhenClosed = false
        w.contentView = view; w.setContentSize(view.fittingSize.width > 10 ? view.fittingSize : size)
        if let host = window, host.isVisible { let f = host.frame; w.setFrameOrigin(NSPoint(x: f.midX - w.frame.width / 2, y: f.midY - w.frame.height / 2)) } else { w.center() }
        store = w; NSApp.activate(ignoringOtherApps: true); w.makeKeyAndOrderFront(nil)
    }

    @objc func openSettings() { panel(NSSize(width: 560, height: 560), NSHostingView(rootView: SettingsView(model: AppModel.shared)), store: &settingsWindow) }

    func openBatch(_ urls: [URL]) {
        let m = BatchModel(urls: urls)
        var w: NSWindow? = batchWindow
        panel(NSSize(width: 460, height: 380), NSHostingView(rootView: BatchView(model: m) { [weak self] in self?.batchWindow?.close() }), store: &w)
        batchWindow = w
    }

    @objc func showAbout() {
        let info = Bundle.main.infoDictionary ?? [:]
        let v = info["CFBundleShortVersionString"] as? String ?? "?", b = info["CFBundleVersion"] as? String ?? "?"
        let icon = NSImageView(image: NSApp.applicationIconImage); icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 84).isActive = true; icon.heightAnchor.constraint(equalToConstant: 84).isActive = true
        func label(_ s: String, size: CGFloat = 12, bold: Bool = false, secondary: Bool = false, brand: Bool = false) -> NSTextField {
            let p = NSMutableParagraphStyle(); p.alignment = .center
            let a = NSMutableAttributedString(string: s, attributes: [.font: bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size), .paragraphStyle: p, .foregroundColor: secondary ? NSColor.secondaryLabelColor : NSColor.labelColor])
            if brand { a.addAttribute(.foregroundColor, value: Theme.brandNS, range: NSRange(location: 0, length: 1)) }
            let f = NSTextField(wrappingLabelWithString: s); f.attributedStringValue = a; f.alignment = .center; f.preferredMaxLayoutWidth = 300; f.isSelectable = false; f.translatesAutoresizingMaskIntoConstraints = false
            return f
        }
        let support = NSButton(title: "♥ " + L.t("about.support"), target: self, action: #selector(openSupport)); support.isBordered = false; support.contentTintColor = .secondaryLabelColor
        let stack = NSStackView(views: [icon, label("mSLICE", size: 17, bold: true, brand: true), label(L.t("about.version", v, b), secondary: true), label(L.t("app.tagline")),
                                        label("Starbudweiser & Claude Code (Anthropic)", bold: true), label(L.t("about.collection"), secondary: true), support])
        stack.orientation = .vertical; stack.alignment = .centerX; stack.spacing = 10; stack.edgeInsets = NSEdgeInsets(top: 34, left: 28, bottom: 24, right: 28)
        panel(NSSize(width: 360, height: 360), stack, store: &aboutWindow)
    }
    @objc func openSupport() { NSWorkspace.shared.open(URL(string: "https://github.com/sponsors/starbudweiser")!) }

    // MARK: Menus

    @objc func openFiles() { AppModel.shared.chooseFiles() }
    @objc func exportCmd() { AppModel.shared.exportNow() }
    @objc func closeFile() { if let d = AppModel.shared.current { AppModel.shared.close(d) } }
    @objc func undoCmd() { AppModel.shared.current?.undo() }
    @objc func shortcutsCmd() { AppModel.shared.showShortcuts.toggle() }

    func buildMenu() {
        let main = NSMenu()
        func item(_ title: String, _ sel: Selector?, _ key: String = "", mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: sel, keyEquivalent: key); i.keyEquivalentModifierMask = mods; i.target = self; return i
        }
        let app = NSMenu()
        app.addItem(item(L.t("menu.about"), #selector(showAbout)))
        UpdateEngine.shared.installAppMenuItem()
        app.addItem(.separator())
        app.addItem(item(L.t("menu.settings"), #selector(openSettings), ","))
        app.addItem(.separator())
        let hide = NSMenuItem(title: L.t("menu.hide"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"); hide.target = NSApp; app.addItem(hide)
        app.addItem(.separator())
        let q = NSMenuItem(title: L.t("menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"); q.target = NSApp; app.addItem(q)
        let appItem = NSMenuItem(); appItem.submenu = app; main.addItem(appItem)

        let file = NSMenu(title: L.t("menu.file"))
        file.addItem(item(L.t("menu.open"), #selector(openFiles), "o"))
        file.addItem(item(L.t("menu.export"), #selector(exportCmd), "\r"))
        file.addItem(.separator())
        file.addItem(item(L.t("menu.closeFile"), #selector(closeFile), "w"))
        let fileItem = NSMenuItem(); fileItem.submenu = file; main.addItem(fileItem)

        let edit = NSMenu(title: L.t("menu.edit"))
        edit.addItem(item(L.t("menu.undo"), #selector(undoCmd), "z"))
        edit.addItem(.separator())
        edit.addItem(item(L.t("menu.shortcuts"), #selector(shortcutsCmd), "/"))
        let editItem = NSMenuItem(); editItem.submenu = edit; main.addItem(editItem)

        let win = NSMenu(title: L.t("menu.window"))
        win.addItem(NSMenuItem(title: L.t("menu.minimize"), action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m"))
        let winItem = NSMenuItem(); winItem.submenu = win; main.addItem(winItem)
        NSApp.mainMenu = main; NSApp.windowsMenu = win
    }

    // MARK: Essais sans fenêtre

    /// `mSLICE --capture out.png --open fichier [--time 125.3] [--segments 15-60,120-150] [--state export|done|shortcuts] [--theme dark|light] [--wait 4]`
    func snapshot(to path: String) {
        guard let w = window, let v = w.contentView else { return }
        v.frame = NSRect(origin: .zero, size: w.frame.size); v.layoutSubtreeIfNeeded()
        guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
        v.cacheDisplay(in: v.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: path)) }
    }

    func capture(to path: String) {
        guard let w = window, let v = w.contentView else { exit(2) }
        let model = AppModel.shared
        let wait = Double(arg("--wait") ?? "") ?? 4
        if let sz = arg("--size")?.split(separator: "x").compactMap({ Double($0) }), sz.count == 2 { w.setFrame(NSRect(x: 0, y: 0, width: sz[0], height: sz[1]), display: true) }
        DispatchQueue.main.asyncAfter(deadline: .now() + wait * 0.6) {
            if let d = model.current {
                if let s = self.arg("--segments") {
                    d.segments = s.split(separator: ",").compactMap { p in let ab = p.split(separator: "-").compactMap { Double($0) }; return ab.count == 2 ? Segment(start: ab[0], end: ab[1]) : nil }
                    d.selected = d.segments.dropFirst().first?.id ?? d.segments.first?.id
                }
                if let n = self.arg("--names") { for (i, nm) in n.split(separator: ",", omittingEmptySubsequences: false).enumerated() where d.segments.indices.contains(i) && !nm.isEmpty { d.segments[i].name = String(nm) } }
                if let b = self.arg("--base") { d.baseName = b }
                if let t = self.arg("--time").flatMap(Double.init) { model.player.seek(t) }
            }
            if self.arg("--state") == "shortcuts" { model.showShortcuts = true }
            if self.arg("--state") == "export", let d = model.current { let r = ExportRun(); r.items = d.segments.map { ExportRun.Item(name: $0.id.uuidString.prefix(8) + ".mp4", duration: $0.duration, fraction: 0.5, state: .running) }; model.run = r; model.sheet = .export }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
            v.frame = NSRect(origin: .zero, size: w.frame.size)
            v.layoutSubtreeIfNeeded()
            guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { exit(3) }
            v.cacheDisplay(in: v.bounds, to: rep)
            if let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: path)); print("OK : \(path) (\(Int(v.bounds.width))×\(Int(v.bounds.height)))") }
            exit(0)
        }
    }
}
