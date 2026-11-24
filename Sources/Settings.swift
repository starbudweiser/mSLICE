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
    @State private var page = ProcessInfo.processInfo.arguments.contains("--agent-page") ? 1 : 0       // 0 : général, 1 : agent
    @AppStorage("agent.enabled") private var agentEnabled = false
    @AppStorage("agent.backend") private var backend = AgentBackend.claudeCode.rawValue
    @AppStorage("agent.cc.path") private var ccPath = ""
    @AppStorage("agent.cc.model") private var ccModel = ""
    @AppStorage("agent.anthropic.model") private var anModel = ""
    @AppStorage("agent.anthropic.base") private var anBase = ""
    @AppStorage("agent.openai.base") private var oaBase = "http://localhost:11434/v1"
    @AppStorage("agent.openai.model") private var oaModel = ""
    @State private var anKey = ""
    @State private var oaKey = ""
    @State private var keysLoaded = false
    @State private var testText: String?
    @State private var testOK = false
    @State private var copied: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L.t("settings.title")).font(.system(size: 16, weight: .bold))
                Spacer()
                Segmented(options: [(0, L.t("settings.page.general")), (1, L.t("settings.page.agent"))], selection: $page).frame(width: 220)
            }
            if page == 1 { agentPage } else { generalPage }
        }
        .padding(20).frame(width: 560).background(Theme.bg)
        .task { finderOn = await FinderExtension.status() }
        .task {
            if !keysLoaded { anKey = AgentKeychain.get("anthropic") ?? ""; oaKey = AgentKeychain.get("openai") ?? ""; keysLoaded = true }
        }
    }

    @ViewBuilder private var generalPage: some View {
        VStack(alignment: .leading, spacing: 12) {
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
    }

    // MARK: Page « Agent »

    private var mcpPath: String { AgentConfig.mcpExecutable.path }
    private func field(_ placeholder: String, _ text: Binding<String>, width: CGFloat = 250) -> some View {
        TextField(placeholder, text: text).textFieldStyle(.plain).multilineTextAlignment(.trailing).frame(width: width).font(.system(size: 12.5, weight: .semibold))
    }
    private func copy(_ id: String, _ text: String) {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        copied = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { if copied == id { copied = nil } }
    }

    @ViewBuilder private var agentPage: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                group(L.t("settings.page.agent")) {
                    row(L.t("settings.agent.allow")) { FlatSwitch(isOn: $agentEnabled) }
                    Text(L.t("settings.agent.allow.hint")).font(.system(size: 11)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 2)
                }
                group(L.t("settings.agent.chat")) {
                    Segmented(options: AgentBackend.allCases.map { ($0.rawValue, $0.title) }, selection: Binding(get: { backend }, set: { backend = $0; testText = nil }))
                    switch AgentBackend(rawValue: backend) ?? .claudeCode {
                    case .claudeCode:
                        row(L.t("settings.agent.cc.path")) {
                            HStack(spacing: 8) {
                                let found = AgentConfig.claudePath() != nil
                                Tag(text: L.t(found ? "settings.agent.cc.found" : "settings.agent.cc.missing"), kind: found ? .ok : .warn)
                                Button(L.t("settings.agent.choose")) {
                                    let p = NSOpenPanel(); p.canChooseDirectories = false; p.allowsMultipleSelection = false
                                    if p.runModal() == .OK, let u = p.url { ccPath = u.path }
                                }.buttonStyle(FlatButton(height: 24))
                            }
                        }
                        row(L.t("settings.agent.model")) { field(L.t("settings.agent.model.default"), $ccModel, width: 160) }
                        Text(L.t("settings.agent.cc.hint")).font(.system(size: 11)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 2)
                    case .anthropic:
                        row(L.t("settings.agent.key")) {
                            SecureField("sk-ant-…", text: $anKey).textFieldStyle(.plain).multilineTextAlignment(.trailing).frame(width: 250).font(.system(size: 12.5, weight: .semibold))
                                .onChange(of: anKey) { _, v in AgentKeychain.set("anthropic", v.trimmingCharacters(in: .whitespacesAndNewlines)) }
                        }
                        row(L.t("settings.agent.model")) { field("claude-sonnet-5-5", $anModel) }
                        row(L.t("settings.agent.base")) { field("https://api.anthropic.com", $anBase) }
                        Text(L.t("settings.agent.keychain")).font(.system(size: 11)).foregroundStyle(Theme.text2).padding(.horizontal, 2)
                    case .openai:
                        row(L.t("settings.agent.preset")) {
                            Menu {
                                Button("Ollama") { oaBase = "http://localhost:11434/v1" }
                                Button("LM Studio") { oaBase = "http://localhost:1234/v1" }
                                Button("OpenAI") { oaBase = "https://api.openai.com/v1" }
                                Button("OpenRouter") { oaBase = "https://openrouter.ai/api/v1" }
                            } label: { Text(oaBase.contains("11434") ? "Ollama" : oaBase.contains("1234") ? "LM Studio" : oaBase.contains("openai.com") ? "OpenAI" : oaBase.contains("openrouter") ? "OpenRouter" : "…") }.menuStyle(.borderlessButton).fixedSize()
                        }
                        row(L.t("settings.agent.base")) { field("http://localhost:11434/v1", $oaBase) }
                        row(L.t("settings.agent.model")) { field("llama3.1, gpt-4o…", $oaModel, width: 200) }
                        row(L.t("settings.agent.key.optional")) {
                            SecureField("sk-…", text: $oaKey).textFieldStyle(.plain).multilineTextAlignment(.trailing).frame(width: 250).font(.system(size: 12.5, weight: .semibold))
                                .onChange(of: oaKey) { _, v in AgentKeychain.set("openai", v.trimmingCharacters(in: .whitespacesAndNewlines)) }
                        }
                        Text(L.t("settings.agent.keychain")).font(.system(size: 11)).foregroundStyle(Theme.text2).padding(.horizontal, 2)
                    }
                    HStack(spacing: 8) {
                        Button(L.t("settings.agent.test")) {
                            testText = L.t("settings.agent.test.wait"); testOK = false
                            Task { let r = await AgentChat.shared.test(); testOK = r.ok; testText = r.ok ? L.t("settings.agent.test.ok") : r.text }
                        }.buttonStyle(FlatButton(height: 26))
                        if let t = testText { Text(t).font(.system(size: 11)).foregroundStyle(testOK ? Theme.ok : Theme.text2).lineLimit(2).truncationMode(.middle) }
                    }
                }
                group(L.t("settings.agent.mcp")) {
                    Text(L.t("settings.agent.mcp.hint")).font(.system(size: 11)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 2)
                    HStack(spacing: 6) {
                        copyButton("claude", L.t("settings.agent.copy.claude"), "claude mcp add --scope user mslice -- \"\(mcpPath)\"")
                        copyButton("json", L.t("settings.agent.copy.json"), "{\n  \"mcpServers\": {\n    \"mslice\": { \"command\": \"\(mcpPath)\" }\n  }\n}")
                        copyButton("toml", L.t("settings.agent.copy.toml"), "[mcp_servers.mslice]\ncommand = \"\(mcpPath)\"")
                    }
                    Text(mcpPath).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.text2).lineLimit(1).truncationMode(.middle).textSelection(.enabled).padding(.horizontal, 2)
                    row(L.t("settings.agent.log")) {
                        Button(L.t("settings.agent.log.open")) {
                            if !FileManager.default.fileExists(atPath: AgentLog.url.path) { try? Data().write(to: AgentLog.url) }
                            NSWorkspace.shared.activateFileViewerSelecting([AgentLog.url])
                        }.buttonStyle(FlatButton(height: 24))
                    }
                }
            }
            .padding(.bottom, 4)
        }.frame(height: 470)
    }

    private func copyButton(_ id: String, _ title: String, _ text: String) -> some View {
        Button { copy(id, text) } label: { Text(copied == id ? L.t("settings.agent.copied") : title).lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth: .infinity) }.buttonStyle(FlatButton(height: 28))
    }

    private func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) { SectionTitle(title); content() }
    }
    private func row<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack { Text(label).font(.system(size: 12.5)); Spacer(minLength: 8); content().font(.system(size: 12.5)) }
            .padding(.horizontal, 10).frame(height: 34).background(Theme.ctl, in: RoundedRectangle(cornerRadius: Theme.rControl, style: .continuous))
    }
}
