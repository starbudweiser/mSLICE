// mSLICE — discussion avec un agent : l'utilisateur demande, l'agent agit (mêmes outils et mêmes garde-fous que le serveur MCP).
// Moteurs : Claude Code installé (abonnement, via `mslice-mcp`), API Anthropic, ou tout service compatible OpenAI (local : Ollama, LM Studio ; en ligne : OpenAI,
// OpenRouter…). Les clés sont dans le Trousseau. Rien n'est envoyé tant que l'utilisateur n'a pas écrit un message.
import AppKit
import Foundation
import Security

enum AgentBackend: String, CaseIterable {
    case claudeCode = "claudecode", anthropic, openai
    var title: String { L.t("agent.backend." + rawValue) }
}

enum AgentKeychain {
    static var service: String { Env.bundleID + ".agent" }
    static func get(_ account: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var r: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &r) == errSecSuccess, let d = r as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    static func set(_ account: String, _ value: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return }
        var add = base; add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
}

enum AgentConfig {
    static let ud = UserDefaults.standard
    static var backend: AgentBackend { AgentBackend(rawValue: ud.string(forKey: "agent.backend") ?? "") ?? .claudeCode }
    static func string(_ key: String, _ fallback: String = "") -> String { let s = (ud.string(forKey: key) ?? "").trimmingCharacters(in: .whitespacesAndNewlines); return s.isEmpty ? fallback : s }
    static var anthropicBase: String { string("agent.anthropic.base", "https://api.anthropic.com") }
    static var anthropicModel: String { string("agent.anthropic.model", "claude-sonnet-5-5") }
    static var openaiBase: String { string("agent.openai.base", "http://localhost:11434/v1") }
    static var openaiModel: String { string("agent.openai.model") }

    /// Chemin de Claude Code : réglage manuel, puis les emplacements habituels, puis le shell de connexion de l'utilisateur.
    static func claudePath() -> URL? {
        let fm = FileManager.default, home = NSHomeDirectory()
        var c: [String] = []
        if !string("agent.cc.path").isEmpty { c.append((string("agent.cc.path") as NSString).expandingTildeInPath) }
        c += ["\(home)/.local/bin/claude", "\(home)/.claude/local/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude", "\(home)/.npm-global/bin/claude", "\(home)/.bun/bin/claude"]
        if let hit = c.first(where: { fm.isExecutableFile(atPath: $0) }) { return URL(fileURLWithPath: hit) }
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/zsh"); p.arguments = ["-lc", "command -v claude"]
        let o = Pipe(); p.standardOutput = o; p.standardError = FileHandle.nullDevice; p.standardInput = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let out = String(decoding: o.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        p.waitUntilExit()
        return out.hasPrefix("/") && fm.isExecutableFile(atPath: out) ? URL(fileURLWithPath: out) : nil
    }

    /// Exécutable MCP livré dans l'appli.
    static var mcpExecutable: URL { Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/mslice-mcp") }
}

struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, assistant, tool, note }
    let id = UUID()
    var role: Role
    var text: String
    var tool: String? = nil
    var done = true
    var failed = false
}

@MainActor
final class AgentChat: ObservableObject {
    static let shared = AgentChat()
    @Published var messages: [ChatMessage] = []
    @Published var busy = false
    private var task: Task<Void, Never>?
    private var proc: Process?
    private var ccSession: String?
    private var anthropicHistory: [[String: Any]] = []
    private var openaiHistory: [[String: Any]] = []
    private var toolRows: [String: UUID] = [:]
    static let client = "panneau"

    // MARK: Commandes

    func send(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !busy else { return }
        messages.append(ChatMessage(role: .user, text: text))
        if let refus = Agent.authorize() { messages.append(ChatMessage(role: .note, text: refus, failed: true)); return }
        busy = true
        task = Task {
            await run(text)
            busy = false; proc = nil
        }
    }

    func stop() { task?.cancel(); proc?.terminate() }

    func reset() {
        stop(); messages = []; ccSession = nil; anthropicHistory = []; openaiHistory = []; toolRows = [:]
    }

    private func run(_ text: String) async {
        switch AgentConfig.backend {
        case .claudeCode: await runClaudeCode(text)
        case .anthropic: await runAnthropic(text)
        case .openai: await runOpenAI(text)
        }
    }

    private func note(_ s: String, failed: Bool = true) { messages.append(ChatMessage(role: .note, text: s, failed: failed)) }

    // MARK: Contexte

    func systemPrompt() -> String {
        let m = AppModel.shared
        var ctx = ""
        if let d = m.current {
            ctx = "\nCurrent state: the file open in the window is \"\(d.url.path)\" (\(Fmt.time(d.duration)), \(d.info.summary)); playhead at \(Fmt.time(m.player.time)); \(d.segments.count) piece(s) marked."
            if m.docs.count > 1 { ctx += " Other open files: " + m.docs.filter { $0 !== d }.map { "\"\($0.url.path)\"" }.joined(separator: ", ") + "." }
        } else { ctx = "\nNo file is open in the window." }
        let lang = ["fr": "French", "en": "English", "es": "Spanish", "it": "Italian"][L.lang == .fr ? "fr" : L.lang == .es ? "es" : L.lang == .it ? "it" : "en"] ?? "English"
        return """
        You are the assistant built into mSLICE, a macOS app that trims audio and video. The user talks to you in a chat panel next to the timeline and expects you to DO what they ask with the tools, not to explain how.
        \(Agent.instructions)
        Rules: answer in \(lang), briefly and plainly. When the request is clear, act without asking; ask one short question only when something essential is ambiguous (which file, merged or separate, re-encode or not). \
        Prefer direct stream copy (passthrough) unless the user wants exact cuts or another codec. After marking pieces, tell the user they are visible on the timeline. After an export, give the created file names. \
        Never say something was done unless a tool confirmed it. You cannot delete, overwrite or move files to the trash.\(ctx)
        """
    }

    // MARK: Claude Code

    private func runClaudeCode(_ text: String) async {
        guard let bin = AgentConfig.claudePath() else { note(L.t("agent.err.noclaude")); return }
        guard FileManager.default.isExecutableFile(atPath: AgentConfig.mcpExecutable.path) else { note(L.t("agent.err.nomcp")); return }
        let work = Env.supportDir.appendingPathComponent("agent-workdir", isDirectory: true)
        try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let cfg = work.appendingPathComponent("mcp.json")
        let json: [String: Any] = ["mcpServers": ["mslice": ["command": AgentConfig.mcpExecutable.path, "args": [String]()]]]
        try? JSONSerialization.data(withJSONObject: json).write(to: cfg)

        var args = ["-p", "--output-format", "stream-json", "--verbose", "--mcp-config", cfg.path, "--strict-mcp-config", "--allowedTools", "mcp__mslice", "--tools", "", "--append-system-prompt", systemPrompt()]
        let model = AgentConfig.string("agent.cc.model")
        if !model.isEmpty { args += ["--model", model] }
        if let s = ccSession { args += ["--resume", s] }

        let p = Process(); p.executableURL = bin; p.arguments = args; p.currentDirectoryURL = work
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = ["\(NSHomeDirectory())/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", env["PATH"] ?? ""].joined(separator: ":")
        p.environment = env
        let inp = Pipe(), out = Pipe(), err = Pipe()
        p.standardInput = inp; p.standardOutput = out; p.standardError = err
        let carry = LineBuffer(), errTail = LineBuffer()
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData; if d.isEmpty { return }
            let lines = carry.feed(d)
            Task { @MainActor in for l in lines { self?.handleClaudeEvent(l) } }
        }
        err.fileHandleForReading.readabilityHandler = { h in let d = h.availableData; if !d.isEmpty { _ = errTail.feed(d) } }
        proc = p
        let status: Int32 = await withCheckedContinuation { c in
            p.terminationHandler = { c.resume(returning: $0.terminationStatus) }
            do { try p.run() } catch { c.resume(returning: -1); return }
            inp.fileHandleForWriting.write(Data(text.utf8)); try? inp.fileHandleForWriting.close()
        }
        out.fileHandleForReading.readabilityHandler = nil; err.fileHandleForReading.readabilityHandler = nil
        for l in carry.rest() { handleClaudeEvent(l) }
        for i in messages.indices where messages[i].role == .tool && !messages[i].done { messages[i].done = true }
        if Task.isCancelled { note(L.t("agent.stopped"), failed: false); return }
        if status != 0, !messages.contains(where: { $0.role == .assistant && !$0.text.isEmpty }) {
            let tail = errTail.all().trimmingCharacters(in: .whitespacesAndNewlines)
            note(tail.isEmpty ? "claude : code \(status)" : String(tail.suffix(400)))
        }
    }

    /// Une ligne du flux `--output-format stream-json`.
    private func handleClaudeEvent(_ line: String) {
        guard let o = AgentJSON.parse(line), let type = o["type"] as? String else { return }
        switch type {
        case "system":
            if let s = o["session_id"] as? String { ccSession = s }
        case "assistant":
            let blocks = ((o["message"] as? [String: Any])?["content"] as? [[String: Any]]) ?? []
            for b in blocks {
                switch b["type"] as? String {
                case "text": if let t = b["text"] as? String, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { messages.append(ChatMessage(role: .assistant, text: t)) }
                case "tool_use":
                    let name = ((b["name"] as? String) ?? "").replacingOccurrences(of: "mcp__mslice__", with: "")
                    let row = ChatMessage(role: .tool, text: Self.toolSummary(name, b["input"] as? [String: Any] ?? [:]), tool: name, done: false)
                    messages.append(row)
                    if let id = b["id"] as? String { toolRows[id] = row.id }
                default: break
                }
            }
        case "user":
            let blocks = ((o["message"] as? [String: Any])?["content"] as? [[String: Any]]) ?? []
            for b in blocks where (b["type"] as? String) == "tool_result" {
                if let id = b["tool_use_id"] as? String, let rid = toolRows[id], let i = messages.firstIndex(where: { $0.id == rid }) {
                    messages[i].done = true; messages[i].failed = (b["is_error"] as? Bool) ?? false
                }
            }
        case "result":
            if let s = o["session_id"] as? String { ccSession = s }
            if (o["is_error"] as? Bool) == true, let r = o["result"] as? String, !r.isEmpty {
                let lower = r.lowercased()
                let text = lower.contains("authenticate") || lower.contains("auth login") || lower.contains("/login") || lower.contains("not logged in") ? L.t("agent.err.cclogin") : r
                if let i = messages.lastIndex(where: { $0.role == .assistant }), messages[i].text == r { messages.remove(at: i) }      // l'erreur arrive aussi comme message : une seule fois
                note(text)
            }
        default: break
        }
    }

    final class LineBuffer: @unchecked Sendable {
        private var buf = Data(), whole = Data(); private let lock = NSLock()
        func feed(_ d: Data) -> [String] {
            lock.lock(); defer { lock.unlock() }
            buf.append(d); whole.append(d); if whole.count > 16384 { whole = whole.suffix(16384) }
            var lines: [String] = []
            while let i = buf.firstIndex(of: 10) { lines.append(String(decoding: buf[buf.startIndex ..< i], as: UTF8.self)); buf.removeSubrange(buf.startIndex ... i) }
            return lines
        }
        func rest() -> [String] { lock.lock(); defer { lock.unlock() }; let s = String(decoding: buf, as: UTF8.self); buf = Data(); return s.isEmpty ? [] : [s] }
        func all() -> String { lock.lock(); defer { lock.unlock() }; return String(decoding: whole, as: UTF8.self) }
    }

    // MARK: API Anthropic

    private func runAnthropic(_ text: String) async {
        guard let key = AgentKeychain.get("anthropic"), !key.isEmpty else { note(L.t("agent.err.nokey")); return }
        guard let url = URL(string: AgentConfig.anthropicBase.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/v1/messages") else { note("URL ?"); return }
        let mark = anthropicHistory.count
        anthropicHistory.append(["role": "user", "content": [["type": "text", "text": text]]])
        let tools = Agent.tools.map { ["name": $0.name, "description": $0.description, "input_schema": $0.schema] as [String: Any] }
        do {
            for _ in 0 ..< 25 {
                try Task.checkCancellation()
                let body: [String: Any] = ["model": AgentConfig.anthropicModel, "max_tokens": 4096, "system": systemPrompt(), "tools": tools, "messages": anthropicHistory]
                let r = try await Self.post(url, ["x-api-key": key, "anthropic-version": "2023-06-01", "content-type": "application/json"], body)
                let blocks = (r["content"] as? [[String: Any]]) ?? []
                anthropicHistory.append(["role": "assistant", "content": blocks])
                for b in blocks where (b["type"] as? String) == "text" { if let t = b["text"] as? String, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { messages.append(ChatMessage(role: .assistant, text: t)) } }
                let uses = blocks.filter { ($0["type"] as? String) == "tool_use" }
                if uses.isEmpty { return }
                var results: [[String: Any]] = []
                for u in uses {
                    try Task.checkCancellation()
                    let name = u["name"] as? String ?? "", input = u["input"] as? [String: Any] ?? [:]
                    let out = await runTool(name, input)
                    let content: [[String: Any]] = out.content.map { b in
                        if (b["type"] as? String) == "image" { return ["type": "image", "source": ["type": "base64", "media_type": b["mimeType"] as? String ?? "image/png", "data": b["data"] as? String ?? ""]] }
                        return b
                    }
                    results.append(["type": "tool_result", "tool_use_id": u["id"] as? String ?? "", "is_error": out.isError, "content": content])
                }
                anthropicHistory.append(["role": "user", "content": results])
            }
            note(L.t("agent.err.toolloop"))
        } catch is CancellationError { anthropicHistory = Array(anthropicHistory.prefix(mark)); note(L.t("agent.stopped"), failed: false) }
        catch { anthropicHistory = Array(anthropicHistory.prefix(mark)); note(error.localizedDescription) }
    }

    // MARK: Compatible OpenAI (Ollama, LM Studio, OpenAI, OpenRouter…)

    private func runOpenAI(_ text: String) async {
        let model = AgentConfig.openaiModel
        guard !model.isEmpty else { note(L.t("agent.err.nomodel")); return }
        guard let url = URL(string: AgentConfig.openaiBase.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions") else { note("URL ?"); return }
        var headers = ["content-type": "application/json"]
        if let k = AgentKeychain.get("openai"), !k.isEmpty { headers["authorization"] = "Bearer " + k }
        let mark = openaiHistory.count
        openaiHistory.append(["role": "user", "content": text])
        let tools = Agent.tools.map { ["type": "function", "function": ["name": $0.name, "description": $0.description, "parameters": $0.schema]] as [String: Any] }
        do {
            for _ in 0 ..< 25 {
                try Task.checkCancellation()
                let body: [String: Any] = ["model": model, "messages": [["role": "system", "content": systemPrompt()]] + openaiHistory, "tools": tools, "tool_choice": "auto"]
                let r = try await Self.post(url, headers, body)
                guard let msg = ((r["choices"] as? [[String: Any]])?.first?["message"]) as? [String: Any] else { throw AgentError(Self.errorText(r) ?? "Réponse vide du service.") }
                let content = msg["content"] as? String ?? ""
                let calls = (msg["tool_calls"] as? [[String: Any]]) ?? []
                var entry: [String: Any] = ["role": "assistant", "content": content]
                if !calls.isEmpty { entry["tool_calls"] = calls }
                openaiHistory.append(entry)
                if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { messages.append(ChatMessage(role: .assistant, text: content)) }
                if calls.isEmpty { return }
                for c in calls {
                    try Task.checkCancellation()
                    let fn = c["function"] as? [String: Any] ?? [:]
                    let name = fn["name"] as? String ?? ""
                    let args = AgentJSON.parse(fn["arguments"] as? String ?? "{}") ?? [:]
                    let out = await runTool(name, args)
                    let text = out.content.map { ($0["type"] as? String) == "image" ? "[image]" : ($0["text"] as? String ?? "") }.joined(separator: "\n")
                    openaiHistory.append(["role": "tool", "tool_call_id": c["id"] as? String ?? "", "content": text])
                }
            }
            note(L.t("agent.err.toolloop"))
        } catch is CancellationError { openaiHistory = Array(openaiHistory.prefix(mark)); note(L.t("agent.stopped"), failed: false) }
        catch { openaiHistory = Array(openaiHistory.prefix(mark)); note(error.localizedDescription) }
    }

    // MARK: Outils et réseau

    private func runTool(_ name: String, _ args: [String: Any]) async -> ToolOutput {
        let row = ChatMessage(role: .tool, text: Self.toolSummary(name, args), tool: name, done: false)
        messages.append(row)
        let out = await Agent.run(name, args, host: AppAgentHost.shared, client: Self.client)
        if let i = messages.firstIndex(where: { $0.id == row.id }) { messages[i].done = true; messages[i].failed = out.isError }
        return out
    }

    /// « set_segments · 2 morceaux », « export · fusion »…
    static func toolSummary(_ name: String, _ a: [String: Any]) -> String {
        var bits: [String] = []
        if let p = a["path"] as? String { bits.append((p as NSString).lastPathComponent) }
        if let s = a["segments"] as? [Any] { bits.append("\(s.count)×") }
        if let t = a["time"] { bits.append("\(t)") }
        if a["merge"] as? Bool == true { bits.append("merge") }
        return ([name] + bits).joined(separator: " · ")
    }

    static func errorText(_ r: [String: Any]) -> String? {
        if let e = r["error"] as? [String: Any], let m = e["message"] as? String { return m }
        if let e = r["error"] as? String { return e }
        return nil
    }

    static func post(_ url: URL, _ headers: [String: String], _ body: [String: Any]) async throws -> [String: Any] {
        var req = URLRequest(url: url); req.httpMethod = "POST"; req.timeoutInterval = 300
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (d, resp) = try await URLSession.shared.data(for: req)
        let obj = ((try? JSONSerialization.jsonObject(with: d)) as? [String: Any]) ?? [:]
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 { throw AgentError(errorText(obj) ?? "HTTP \(http.statusCode)") }
        return obj
    }

    // MARK: Essai de connexion (préférences)

    func test() async -> (ok: Bool, text: String) {
        switch AgentConfig.backend {
        case .claudeCode:
            guard let bin = AgentConfig.claudePath() else { return (false, L.t("agent.err.noclaude")) }
            let v = await Run.exec(bin, ["--version"])
            guard v.status == 0 else { return (false, v.err.isEmpty ? "claude : code \(v.status)" : String(v.err.suffix(200))) }
            // Connecté ? (`claude auth status` : JSON avec « loggedIn »)
            let out = await Task.detached { () -> Data? in Run.data(bin, ["auth", "status"]) }.value
            if let out, let o = (try? JSONSerialization.jsonObject(with: out)) as? [String: Any], (o["loggedIn"] as? Bool) == false { return (false, L.t("agent.err.cclogin")) }
            return (true, bin.path)
        case .anthropic:
            guard let key = AgentKeychain.get("anthropic"), !key.isEmpty else { return (false, L.t("agent.err.nokey")) }
            guard let url = URL(string: AgentConfig.anthropicBase.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/v1/models?limit=1") else { return (false, "URL ?") }
            return await Self.get(url, ["x-api-key": key, "anthropic-version": "2023-06-01"])
        case .openai:
            guard let url = URL(string: AgentConfig.openaiBase.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/models") else { return (false, "URL ?") }
            var h: [String: String] = [:]
            if let k = AgentKeychain.get("openai"), !k.isEmpty { h["authorization"] = "Bearer " + k }
            return await Self.get(url, h)
        }
    }

    private static func get(_ url: URL, _ headers: [String: String]) async -> (Bool, String) {
        var req = URLRequest(url: url); req.timeoutInterval = 10
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        do {
            let (d, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code < 400 { return (true, url.host ?? url.absoluteString) }
            let obj = ((try? JSONSerialization.jsonObject(with: d)) as? [String: Any]) ?? [:]
            return (false, errorText(obj) ?? "HTTP \(code)")
        } catch { return (false, error.localizedDescription) }
    }
}
