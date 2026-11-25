// mslice-mcp — serveur MCP (stdio, JSON-RPC 2.0) livré dans mSLICE.app/Contents/MacOS : un agent (Claude Code, Claude Desktop, Cursor, Codex,
// Gemini CLI…) découpe, fusionne et exporte des fichiers audio / vidéo. Si l'appli est ouverte, l'appel lui est transmis (la timeline se met
// à jour en direct) ; sinon l'outil s'exécute ici, sans fenêtre. Désactivé tant que l'utilisateur n'a pas coché « Autoriser un agent ».
import Foundation

// `mslice-mcp --analyze <fichier>` : processus d'analyse lancé par l'appli (voir Analysis/AnalysisRunner.swift)
if let i = CommandLine.arguments.firstIndex(of: "--analyze"), CommandLine.arguments.indices.contains(i + 1) { AnalysisChild.main(path: CommandLine.arguments[i + 1]) }
// `mslice-mcp --faces <fichier>` : reconnaissance des personnages (modèle optionnel), même principe
if let i = CommandLine.arguments.firstIndex(of: "--faces"), CommandLine.arguments.indices.contains(i + 1) { AnalysisChild.main(path: CommandLine.arguments[i + 1], faces: true) }
// `mslice-mcp --voices <fichier>` : reconnaissance des voix (modèle optionnel)
if let i = CommandLine.arguments.firstIndex(of: "--voices"), CommandLine.arguments.indices.contains(i + 1) { AnalysisChild.main(path: CommandLine.arguments[i + 1], voices: true) }
// `mslice-mcp --dialogues <fichier> <langue> <sortie.json>` : transcription de la parole en répliques (macOS 26)
if let i = CommandLine.arguments.firstIndex(of: "--dialogues"), CommandLine.arguments.indices.contains(i + 3) {
    DialoguesChild.main(path: CommandLine.arguments[i + 1], language: CommandLine.arguments[i + 2], out: CommandLine.arguments[i + 3])
}

signal(SIGPIPE, SIG_IGN)
setvbuf(stdout, nil, _IOLBF, 0)

func send(_ m: [String: Any]) {
    guard JSONSerialization.isValidJSONObject(m), let d = try? JSONSerialization.data(withJSONObject: m), let s = String(data: d, encoding: .utf8) else { return }
    print(s); fflush(stdout)
}

@MainActor
final class MCPServer {
    var clientName = "unknown"

    func handle(_ message: [String: Any]) async -> [String: Any]? {
        guard let method = message["method"] as? String, let id = message["id"] else { return nil }      // notifications : pas de réponse
        func reply(_ result: [String: Any]) -> [String: Any] { ["jsonrpc": "2.0", "id": id, "result": result] }
        func fail(_ code: Int, _ text: String) -> [String: Any] { ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": text]] }
        switch method {
        case "initialize":
            let params = message["params"] as? [String: Any]
            if let info = params?["clientInfo"] as? [String: Any], let n = info["name"] as? String, !n.isEmpty { clientName = n }
            return reply(["protocolVersion": params?["protocolVersion"] as? String ?? "2025-03-26", "capabilities": ["tools": [String: Any]()],
                          "serverInfo": ["name": "mslice", "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1"], "instructions": Agent.instructions])
        case "ping": return reply([:])
        case "tools/list": return reply(["tools": Agent.tools.map(\.mcp)])
        case "tools/call":
            let params = message["params"] as? [String: Any] ?? [:]
            let name = params["name"] as? String ?? ""
            let args = params["arguments"] as? [String: Any] ?? [:]
            guard Agent.toolNames.contains(name) else { return fail(-32602, "Unknown tool: \(name)") }
            let client = clientName
            let out: ToolOutput
            if let viaApp = await Task.detached(operation: { AgentBridge.forward(name, args, client: client) }).value { out = viaApp }
            else { out = await Agent.run(name, args, host: nil, client: client) }
            return reply(["content": out.content, "isError": out.isError])
        default: return fail(-32601, "Method not found: \(method)")
        }
    }
}

let lines = AsyncStream<String> { cont in
    Thread.detachNewThread {
        while let l = readLine(strippingNewline: true) { cont.yield(l) }
        cont.finish()
    }
}

Task { @MainActor in
    let server = MCPServer()
    for await line in lines {
        guard let d = line.data(using: .utf8), let m = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { continue }
        if let r = await server.handle(m) { send(r) }
    }
    exit(0)
}
dispatchMain()
