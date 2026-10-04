import Foundation
import Network
import AppKit
import CoreImage.CIFilterBuiltins

// MARK: - Pont téléphone (Oli Android)
// A small HTTP server on the local network, off until the user turns it on (Réglages → Connexions
// → Téléphone). Every request needs the secret token carried by the pairing QR code. The phone
// uses it to chat with Claude through this Mac (the user's own Claude Code subscription).
//   GET  /v1/status  → {"name","claude","model"}
//   POST /v1/chat    {"message","session"} → {"reply","session"} | {"error"}
//   GET  /v1/claude/sessions → {"sessions":[{id,project,state,activity,updatedAt}],"approvals":[{id,project,tool,summary,detail}]}
//   POST /v1/claude/approvals/<id> {"allow":bool} → {"ok":true}

final class PhoneBridge: @unchecked Sendable {
    static let shared = PhoneBridge()
    static let preferredPort: UInt16 = 47_630

    private let queue = DispatchQueue(label: "studio.oculot.oli.phone")
    private var listener: NWListener?
    private(set) var port: UInt16 = 0

    @MainActor static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: "phoneBridgeEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "phoneBridgeEnabled"); newValue ? shared.start() : shared.stop() }
    }

    /// Secret shared with the phone through the QR code (Keychain, created on first use).
    @MainActor static var token: String {
        if let t = KeychainStore.shared.get("phone-token"), !t.isEmpty { return t }
        let t = (0..<32).map { _ in "abcdefghijkmnopqrstuvwxyz23456789".randomElement()! }.map(String.init).joined()
        KeychainStore.shared.set("phone-token", value: t)
        return t
    }

    /// Answering Claude Code permission requests from the phone: off until the user opts in.
    @MainActor static var approvalsEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "phoneApprovalsEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "phoneApprovalsEnabled") }
    }

    @MainActor static func newToken() {
        KeychainStore.shared.remove("phone-token")
        _ = token
    }

    // MARK: Server

    func start() {
        queue.async { [self] in
            guard listener == nil else { return }
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            // Local network only: never over a VPN tunnel (utun = .other) or cellular.
            params.prohibitedInterfaceTypes = [.other, .cellular]
            let l = (try? NWListener(using: params, on: NWEndpoint.Port(rawValue: Self.preferredPort)!))
                ?? (try? NWListener(using: params))
            guard let l else { appendAppLog("oli.log", "Pont téléphone : impossible de créer l’écoute"); return }
            l.newConnectionHandler = { [weak self] c in self?.accept(c) }
            l.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready: self?.port = l.port?.rawValue ?? 0; appendAppLog("oli.log", "Pont téléphone prêt sur le port \(l.port?.rawValue ?? 0)")
                case .failed(let e): appendAppLog("oli.log", "Pont téléphone en échec : \(e)")
                default: break
                }
            }
            l.start(queue: queue)
            listener = l
        }
    }

    func stop() {
        queue.async { [self] in listener?.cancel(); listener = nil; port = 0 }
    }

    // Limits (all touched on `queue` only).
    private static let maxConnections = 8
    private static let maxRequestBytes = 256 * 1024
    private static let readTimeout: TimeInterval = 10
    private var openConnections = 0
    private var failures: [String: [Date]] = [:]

    private static func peer(_ c: NWConnection) -> String {
        if case .hostPort(let host, _) = c.endpoint { return "\(host)" }
        return "?"
    }

    /// 5 bad tokens in 5 minutes from one address → refused for the rest of the window.
    private func isBlocked(_ ip: String) -> Bool {
        let recent = (failures[ip] ?? []).filter { $0.timeIntervalSinceNow > -300 }
        failures[ip] = recent.isEmpty ? nil : recent
        return recent.count >= 5
    }

    private func recordFailure(_ ip: String) {
        queue.async { [self] in
            failures[ip, default: []].append(Date())
            if failures[ip]?.count == 5 { appendAppLog("oli.log", "Pont téléphone : \(ip) bloqué 5 min (codes refusés)") }
        }
    }

    private func accept(_ c: NWConnection) {
        guard openConnections < Self.maxConnections, !isBlocked(Self.peer(c)) else { c.cancel(); return }
        openConnections += 1
        c.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed: self?.openConnections -= 1
            default: break
            }
        }
        c.start(queue: queue)
        // A request must arrive in full within 10 s.
        queue.asyncAfter(deadline: .now() + Self.readTimeout) { if c.state != .cancelled { c.cancel() } }
        read(c, Data())
    }

    private func read(_ c: NWConnection, _ buffer: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 512 * 1024) { [weak self] chunk, _, done, error in
            guard let self else { return }
            var buf = buffer
            if let chunk { buf.append(chunk) }
            if let req = PhoneRequest(buf, maxBody: Self.maxRequestBytes) { self.handle(req, c) }
            else if done || error != nil || buf.count > Self.maxRequestBytes { c.cancel() }
            else { self.read(c, buf) }
        }
    }

    private func reply(_ c: NWConnection, _ status: String, _ json: [String: Any]) {
        let body = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
        let head = "HTTP/1.1 \(status)\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        c.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in c.cancel() })
    }

    private func handle(_ req: PhoneRequest, _ c: NWConnection) {
        Task { @MainActor in
            guard Self.constantTimeEqual(req.headers["authorization"] ?? "", "Bearer \(Self.token)") else {
                self.recordFailure(Self.peer(c))
                return self.reply(c, "401 Unauthorized", ["error": "Jumelage invalide : rescanne le QR code."])
            }
            switch (req.method, req.path) {
            case ("GET", "/v1/status"):
                self.reply(c, "200 OK", ["name": Host.current().localizedName ?? "Mac",
                                         "claude": ClaudeService.claudeCodePath != nil,
                                         "model": ClaudeService.claudeCodeModel.rawValue])
            case ("POST", "/v1/chat"):
                let j = (try? JSONSerialization.jsonObject(with: req.body) as? [String: Any]) ?? [:]
                guard let message = (j["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty else {
                    return self.reply(c, "400 Bad Request", ["error": "Message vide."])
                }
                guard let claude = ClaudeService.claudeCodePath else {
                    return self.reply(c, "503 Service Unavailable", ["error": "Claude n’est pas installé sur ce Mac."])
                }
                let session = j["session"] as? String
                let system = ClaudeService.shared.phoneSystemPrompt
                let (text, sid, err) = await ClaudeService.runClaudeCode(claude: claude, prompt: message, session: session, system: system)
                if let text, !text.isEmpty {
                    self.reply(c, "200 OK", ["reply": text, "session": sid ?? session ?? ""])
                } else {
                    self.reply(c, "502 Bad Gateway", ["error": err ?? "Claude n’a pas répondu."])
                }
            case ("GET", "/v1/claude/sessions"):
                self.reply(c, "200 OK", Self.claudeSnapshot())
            case ("POST", let path) where path.hasPrefix("/v1/claude/approvals/"):
                let id = String(path.dropFirst("/v1/claude/approvals/".count))
                let j = (try? JSONSerialization.jsonObject(with: req.body) as? [String: Any]) ?? [:]
                guard let allow = j["allow"] as? Bool else {
                    return self.reply(c, "400 Bad Request", ["error": "Réponse manquante."])
                }
                guard Self.approvalsEnabled else {
                    return self.reply(c, "403 Forbidden", ["error": "Active « Répondre aux autorisations depuis le téléphone » dans Oli sur le Mac."])
                }
                guard let pending = AppState.shared.pendingApproval, Self.approvalId(pending) == id else {
                    return self.reply(c, "410 Gone", ["error": "Cette demande n’attend plus de réponse."])
                }
                appendAppLog("oli.log", "Pont téléphone : autorisation \(pending.tool) \(allow ? "accordée" : "refusée") depuis le téléphone")
                HookServer.shared.sendApprovalDecision(allow ? "allow" : "deny")
                self.reply(c, "200 OK", ["ok": true])
            default:
                self.reply(c, "404 Not Found", ["error": "Inconnu."])
            }
        }
    }

    // MARK: Claude Code

    @MainActor static func approvalId(_ a: ApprovalInfo) -> String {
        var h: UInt64 = 1469598103934665603
        for b in (a.sessionId + "|" + a.tool + "|" + a.inputKey).utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return String(h, radix: 36)
    }

    @MainActor static func claudeSnapshot() -> [String: Any] {
        let state = AppState.shared
        let agents = state.tasks.filter { $0.source == .claudeCode || $0.id == "integration_claude" || $0.id.hasPrefix("agent_") }
        let sessions: [[String: Any]] = agents.map { t in
            let s: String
            switch t.state {
            case .working, .thinking, .searching: s = "working"
            case .approval, .question: s = "waiting"
            case .finished: s = "done"
            default: s = "idle"
            }
            let project = t.sessionCwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? t.name
            let activity = t.finalLine ?? (t.steps.indices.contains(t.stepIndex) ? t.steps[t.stepIndex] : "")
            let at = state.taskUpdatedAt[t.id] ?? Date()
            return ["id": t.id, "project": project, "state": s, "activity": String(activity.prefix(200)),
                    "updatedAt": Int(at.timeIntervalSince1970)]
        }
        var approvals: [[String: Any]] = []
        if let a = state.pendingApproval {
            let task = state.tasks.first { $0.id == a.pillId }
            let project = task?.sessionCwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? task?.name ?? "Claude Code"
            approvals.append(["id": approvalId(a), "project": project, "tool": a.tool,
                              "summary": "\(a.tool) : \(String(a.command.prefix(80)))",
                              "detail": String(a.command.prefix(2000))])
        }
        return ["sessions": sessions, "approvals": approvalsEnabled ? approvals : [], "approvalsEnabled": approvalsEnabled]
    }

    static func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        var diff = UInt8(x.count == y.count ? 0 : 1)
        for i in 0..<max(x.count, y.count) {
            diff |= (i < x.count ? x[i] : 0) ^ (i < y.count ? y[i] : 0)
        }
        return diff == 0
    }

    // MARK: Pairing

    /// IPv4 address of the Mac on the local network (Wi-Fi first).
    static func localIP() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        var found: [String: String] = [:]
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let a = p.pointee
            guard let sa = a.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: a.ifa_name)
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            let ip = String(cString: host)
            if !ip.hasPrefix("127.") && !ip.hasPrefix("169.254.") { found[name] = ip }
        }
        return found["en0"] ?? found["en1"] ?? found.values.first
    }

    @MainActor static func pairingLink() -> String? {
        guard let ip = localIP() else { return nil }
        let p = shared.port == 0 ? preferredPort : shared.port
        let name = (Host.current().localizedName ?? "Mac").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Mac"
        return "oli://pair?host=\(ip)&port=\(p)&token=\(token)&name=\(name)"
    }

    static func qrImage(_ text: String) -> NSImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8)
        f.correctionLevel = "M"
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else { return nil }
        let rep = NSCIImageRep(ciImage: out)
        let img = NSImage(size: rep.size)
        img.addRepresentation(rep)
        return img
    }
}

/// Minimal HTTP/1.1 request: request line, lowercased headers, body by Content-Length.
struct PhoneRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    init?(_ data: Data, maxBody: Int = 256 * 1024) {
        guard let sep = data.range(of: Data("\r\n\r\n".utf8)),
              let head = String(data: data[..<sep.lowerBound], encoding: .utf8) else { return nil }
        var lines = head.components(separatedBy: "\r\n")
        let first = lines.removeFirst().split(separator: " ")
        guard first.count >= 2 else { return nil }
        var h: [String: String] = [:]
        for l in lines {
            guard let i = l.firstIndex(of: ":") else { continue }
            h[l[..<i].lowercased()] = l[l.index(after: i)...].trimmingCharacters(in: .whitespaces)
        }
        // Reject negative, absurd or unparsable lengths (a negative one used to crash subdata).
        guard let length = Int(h["content-length"] ?? "0"), (0...maxBody).contains(length) else { return nil }
        guard data.count - sep.upperBound >= length else { return nil }
        method = String(first[0]); path = String(first[1].split(separator: "?").first ?? ""); headers = h
        body = data.subdata(in: sep.upperBound..<(sep.upperBound + length))
    }
}
