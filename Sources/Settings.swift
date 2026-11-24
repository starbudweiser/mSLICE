// mSLICE — réglages : apparence, numérotation, après l'export, extension du clic droit, mises à jour.
import AppKit
import SwiftUI

enum FinderExtension {
    static let id = AppModel.isDev ? "fr.stephan.mslice.dev.finder" : "fr.stephan.mslice.finder"
    /// pluginkit : « + » devant l'identifiant = extension activée.
    static func isEnabled() -> Bool {
        let out = shell("/usr/bin/pluginkit", ["-m", "-i", id])
        return out.contains("+") && out.contains(id)
    }
    /// Demande l'activation (équivalent de la case dans Réglages Système ▸ Extensions).
    static func enable() { _ = shell("/usr/bin/pluginkit", ["-e", "use", "-i", id]) }
    /// Versions asynchrones pour les vues : `Process.waitUntilExit` fait tourner la boucle d'événements, ce qui relance le rendu
    /// SwiftUI en pleine mise à jour (plantage) quand on l'appelle depuis une vue ou un gestionnaire de bouton.
    static func status() async -> Bool { await Task.detached(priority: .userInitiated) { isEnabled() }.value }
    static func activate() async { await Task.detached(priority: .userInitiated) { enable() }.value }
    @discardableResult static func shell(_ exe: String, _ args: [String]) -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: exe); p.arguments = args
        let o = Pipe(); p.standardOutput = o; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return "" }
        let d = o.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        return String(decoding: d, as: UTF8.self)
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @AppStorage("appearance") private var appearance = Appearance.dark.rawValue
    @AppStorage("revealAfter") private var revealAfter = true
    @AppStorage("trashAfter") private var trashAfter = false
    @AppStorage("autoUpdate") private var autoUpdate = true
    @State private var finderOn: Bool? = nil          // inconnu tant que la vérification en tâche de fond n'est pas terminée

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L.t("settings.title")).font(.system(size: 16, weight: .bold))
            group(L.t("settings.general")) {
                row(L.t("settings.language")) { Text(L.t("settings.language.auto")).foregroundStyle(Theme.text2) }
                row(L.t("settings.appearance")) {
                    Segmented(options: Appearance.allCases.map { ($0.rawValue, $0.title) }, selection: Binding(get: { appearance }, set: { appearance = $0; (Appearance(rawValue: $0) ?? .auto).apply() })).frame(width: 220)
                }
            }
            group(L.t("settings.export")) {
                row(L.t("settings.digits")) {
                    Segmented(options: [(2, "01"), (3, "001"), (4, "0001")], selection: $model.opts.digits).frame(width: 190)
                }
                row(L.t("settings.suffix")) { TextField("extrait", text: $model.opts.suffix).textFieldStyle(.plain).multilineTextAlignment(.trailing).frame(width: 120).font(.system(size: 12.5, weight: .semibold)) }
                row(L.t("settings.reveal")) { FlatSwitch(isOn: $revealAfter) }
                row(L.t("settings.trash")) { FlatSwitch(isOn: $trashAfter) }
            }
            group(L.t("settings.finder")) {
                row(L.t("settings.finder.ext")) {
                    HStack(spacing: 8) {
                        Tag(text: finderOn == nil ? "…" : (finderOn! ? L.t("settings.finder.on") : L.t("settings.finder.off")), kind: finderOn == nil ? .plain : (finderOn! ? .ok : .warn))
                        if finderOn == false {
                            Button(L.t("settings.finder.open")) {
                                Task {
                                    await FinderExtension.activate()
                                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences")!)
                                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                                    finderOn = await FinderExtension.status()
                                }
                            }.buttonStyle(FlatButton(height: 24))
                        }
                    }
                }
            }
            group(L.t("settings.update")) {
                row(L.t("settings.autoUpdate")) { FlatSwitch(isOn: $autoUpdate) }
                row(L.t("settings.version", Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")) {
                    Button(L.t("settings.updateNow")) { UpdateEngine.shared.checkNow() }.buttonStyle(FlatButton(height: 24))
                }
            }
            HStack {
                Button { AppDelegate.shared?.showAbout() } label: { Text(L.t("settings.about")).font(.system(size: 11.5)).foregroundStyle(Theme.text2) }.buttonStyle(.plain)
                Spacer()
                Button { NSWorkspace.shared.open(URL(string: "https://github.com/sponsors/starbudweiser")!) } label: {
                    HStack(spacing: 5) { Image(systemName: "heart.fill").font(.system(size: 10)); Text(L.t("about.support")) }.font(.system(size: 11.5)).foregroundStyle(Theme.text2) }.buttonStyle(.plain)
            }
        }
        .padding(20).frame(width: 560).background(Theme.bg)
        .task { finderOn = await FinderExtension.status() }
    }

    private func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) { SectionTitle(title); content() }
    }
    private func row<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack { Text(label).font(.system(size: 12.5)); Spacer(minLength: 8); content().font(.system(size: 12.5)) }
            .padding(.horizontal, 10).frame(height: 34).background(Theme.ctl, in: RoundedRectangle(cornerRadius: Theme.rControl, style: .continuous))
    }
}
