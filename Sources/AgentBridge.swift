// mSLICE — pont entre `mslice-mcp` (processus séparé lancé par l'agent) et l'appli ouverte : une prise Unix locale dans Application Support
// (droits 0600, donc réservée à l'utilisateur). L'appli exécute alors l'outil elle-même : la timeline se met à jour en direct.
import Foundation

enum AgentBridge {
    /// `MSLICE_AGENT_SOCKET` redirige la prise (essais). Chemin limité à ~100 octets par le système.
    static var socketPath: String { ProcessInfo.processInfo.environment["MSLICE_AGENT_SOCKET"] ?? Env.supportDir.appendingPathComponent("agent.sock").path }

    static func address(_ path: String) -> sockaddr_un? {
        var a = sockaddr_un()
        a.sun_family = sa_family_t(AF_UNIX)
        let cap = MemoryLayout.size(ofValue: a.sun_path)
        guard path.utf8.count < cap else { return nil }
        withUnsafeMutablePointer(to: &a.sun_path) { p in
            p.withMemoryRebound(to: CChar.self, capacity: cap) { dst in _ = path.withCString { strncpy(dst, $0, cap - 1) } }
        }
        return a
    }

    static func connectSocket(_ path: String) -> Int32? {
        guard var addr = address(path) else { return nil }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var on: Int32 = 1; setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        let ok = withUnsafePointer(to: &addr) { p in p.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        if ok != 0 { close(fd); return nil }
        return fd
    }

    static func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        var sent = 0
        return data.withUnsafeBytes { raw -> Bool in
            while sent < data.count {
                let n = write(fd, raw.baseAddress! + sent, data.count - sent)
                if n <= 0 { return false }
                sent += n
            }
            return true
        }
    }

    /// Lit jusqu'à la fin de ligne (ou de flux). `carry` conserve ce qui suit la ligne pour l'appel suivant.
    static func readLine(_ fd: Int32, carry: inout Data) -> Data? {
        while true {
            if let i = carry.firstIndex(of: 10) { let line = carry[carry.startIndex ..< i]; carry.removeSubrange(carry.startIndex ... i); return Data(line) }
            var buf = [UInt8](repeating: 0, count: 65536)
            let n = read(fd, &buf, buf.count)
            if n <= 0 { if carry.isEmpty { return nil }; let l = carry; carry = Data(); return l }
            carry.append(buf, count: n)
            if carry.count > 16 * 1_048_576 { return nil }          // une requête ne fait jamais 16 Mo : on coupe plutôt que de gonfler en mémoire
        }
    }

    /// Côté `mslice-mcp` : transmet l'appel à l'appli ouverte. nil si l'appli ne répond pas (l'outil s'exécute alors sans elle).
    static func forward(_ tool: String, _ args: [String: Any], client: String) -> ToolOutput? {
        guard FileManager.default.fileExists(atPath: socketPath), let fd = connectSocket(socketPath) else { return nil }
        defer { close(fd) }
        let req: [String: Any] = ["tool": tool, "args": args, "client": client]
        guard JSONSerialization.isValidJSONObject(req), var d = try? JSONSerialization.data(withJSONObject: req) else { return nil }
        d.append(10)
        guard writeAll(fd, d) else { return nil }
        var carry = Data()
        guard let line = readLine(fd, carry: &carry), let o = try? JSONSerialization.jsonObject(with: line) as? [String: Any], let content = o["content"] as? [[String: Any]] else { return nil }
        return ToolOutput(content: content, isError: (o["isError"] as? Bool) ?? false)
    }
}
