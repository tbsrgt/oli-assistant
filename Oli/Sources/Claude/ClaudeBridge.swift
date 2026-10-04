import Foundation
import Network

// MARK: - Pont Claude Code → Oli
// A tiny HTTP server on 127.0.0.1 (random port + secret token, both written to
// ~/Library/Application Support/Oli/bridge for the hook script). Claude Code hooks POST their JSON
// to /hook/<Event>. Everything answers at once, except PermissionRequest, which waits for a click
// in the notch (or gives up after 115 s so Claude Code falls back to its own prompt).

final class ClaudeBridge: @unchecked Sendable {
    static let shared = ClaudeBridge()

    private let queue = DispatchQueue(label: "studio.oculot.oli.bridge")
    private var listener: NWListener?
    private let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
    /// Pending permission requests: approval id → reply (called once).
    private var waiting: [String: @Sendable (Data) -> Void] = [:]
    private var timeouts: [String: DispatchWorkItem] = [:]

    static var supportDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Oli")
    }

    func start() {
        queue.async { self.listen() }
    }

    private func listen() {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        guard let l = try? NWListener(using: params) else { return }
        l.newConnectionHandler = { [weak self] c in self?.accept(c) }
        l.stateUpdateHandler = { [weak self] state in
            if case .ready = state, let port = l.port?.rawValue { self?.writeConfig(port: port) }
        }
        l.start(queue: queue)
        listener = l
    }

    private func writeConfig(port: UInt16) {
        let dir = Self.supportDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("bridge")
        let text = "OLI_PORT=\(port)\nOLI_TOKEN=\(token)\n"
        try? text.write(to: file, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    // MARK: HTTP (just enough of it)

    private func accept(_ c: NWConnection) {
        c.start(queue: queue)
        read(c, buffer: Data())
    }

    private func read(_ c: NWConnection, buffer: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] chunk, _, done, error in
            guard let self else { return }
            var buf = buffer
            if let chunk { buf.append(chunk) }
            if let req = HTTPRequest(buf) {
                self.handle(req, on: c)
            } else if done || error != nil || buf.count > 4 * 1024 * 1024 {
                c.cancel()
            } else {
                self.read(c, buffer: buf)
            }
        }
    }

    private func reply(_ c: NWConnection, status: String = "200 OK", body: Data = Data()) {
        var head = "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        if body.isEmpty { head = head.replacingOccurrences(of: "Content-Type: application/json\r\n", with: "") }
        c.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in c.cancel() })
    }

    private func handle(_ req: HTTPRequest, on c: NWConnection) {
        guard req.headers["x-oli-token"] == token else { return reply(c, status: "403 Forbidden") }
        guard req.method == "POST", req.path.hasPrefix("/hook/") else { return reply(c, status: "404 Not Found") }
        let event = String(req.path.dropFirst("/hook/".count))
        let payload = (try? JSONSerialization.jsonObject(with: req.body) as? [String: Any]) ?? [:]
        let term = req.headers["x-oli-term"] ?? ""
        let hook = HookEvent(name: event.isEmpty ? (payload["hook_event_name"] as? String ?? "") : event,
                             payload: payload, terminal: term)

        if hook.name == "PermissionRequest" {
            let id = UUID().uuidString
            waiting[id] = { [weak self] body in self?.reply(c, body: body) }
            let timeout = DispatchWorkItem { [weak self] in self?.finish(id, body: Data()) }
            timeouts[id] = timeout
            queue.asyncAfter(deadline: .now() + 115, execute: timeout)
            DispatchQueue.main.async { MainActor.assumeIsolated { ClaudeSessions.shared.permission(hook, approvalId: id) } }
        } else {
            reply(c)
            DispatchQueue.main.async { MainActor.assumeIsolated { ClaudeSessions.shared.event(hook) } }
        }
    }

    /// Answer a waiting permission request (from the notch buttons, or the timeout).
    func decide(_ approvalId: String, allow: Bool?) {
        let body: Data
        if let allow {
            let decision: [String: Any] = allow ? ["behavior": "allow"]
                                                : ["behavior": "deny", "message": "Refusé depuis Oli."]
            let out: [String: Any] = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]]
            body = (try? JSONSerialization.data(withJSONObject: out)) ?? Data()
        } else {
            body = Data()        // « Répondre dans le terminal »: Claude Code shows its own prompt
        }
        queue.async { self.finish(approvalId, body: body) }
    }

    private func finish(_ id: String, body: Data) {
        timeouts.removeValue(forKey: id)?.cancel()
        guard let send = waiting.removeValue(forKey: id) else { return }
        send(body)
        if body.isEmpty {
            DispatchQueue.main.async { MainActor.assumeIsolated { ClaudeSessions.shared.dropApproval(id) } }
        }
    }
}

struct HookEvent: @unchecked Sendable {
    let name: String
    let payload: [String: Any]
    let terminal: String
}

