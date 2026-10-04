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

    private func accept(_ c: NWConnection) {
        c.start(queue: queue)
        read(c, Data())
    }

    private func read(_ c: NWConnection, _ buffer: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 512 * 1024) { [weak self] chunk, _, done, error in
            guard let self else { return }
            var buf = buffer
            if let chunk { buf.append(chunk) }
            if let req = PhoneRequest(buf) { self.handle(req, c) }
            else if done || error != nil || buf.count > 2 * 1024 * 1024 { c.cancel() }
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
            guard req.headers["authorization"] == "Bearer \(Self.token)" else {
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
            default:
                self.reply(c, "404 Not Found", ["error": "Inconnu."])
            }
        }
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

    init?(_ data: Data) {
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
        let length = Int(h["content-length"] ?? "0") ?? 0
        guard data.count - sep.upperBound >= length else { return nil }
        method = String(first[0]); path = String(first[1].split(separator: "?").first ?? ""); headers = h
        body = data.subdata(in: sep.upperBound..<(sep.upperBound + length))
    }
}
