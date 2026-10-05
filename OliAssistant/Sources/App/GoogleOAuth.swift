import AppKit
import Network
import CryptoKit

// MARK: - « Se connecter avec Google » (Gmail sans mot de passe d'application)
// OAuth pour app de bureau : Oli ouvre la page Google dans le navigateur, tu cliques « Autoriser »,
// Google renvoie sur http://127.0.0.1:<port> où Oli écoute un instant (PKCE, état aléatoire).
// Oli garde le jeton de renouvellement dans le Trousseau et lit Gmail en IMAP avec XOAUTH2.
//
// L'identifiant du client OAuth (projet Google Cloud « Oli Assistant », type « Application de
// bureau ») est rangé dans le Trousseau (« google-oauth-client »). Pour une app de bureau, Google
// considère ce couple comme public ; il reste quand même hors du dépôt. Au premier lancement, Oli
// importe ~/Library/Application Support/Oli/google-oauth.json s'il existe, puis efface ce fichier.

enum GoogleOAuth {
    struct Client: Codable, Sendable { let client_id: String; let client_secret: String }

    enum Failure: Error, LocalizedError {
        case notConfigured, cancelled, denied(String), network(String)
        var errorDescription: String? {
            switch self {
            case .notConfigured:   return "La connexion Google n’est pas encore installée dans Oli."
            case .cancelled:       return "Connexion Google abandonnée (rien reçu au bout de 5 minutes)."
            case .denied(let m):   return "Google a refusé : \(m)"
            case .network(let m):  return "Google injoignable : \(m)"
            }
        }
    }

    static let scopes = "openid email https://mail.google.com/"
    private static let keychainKey = "google-oauth-client"

    private static var importFile: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Oli/google-oauth.json")
    }

    /// Accepts Google's own downloaded JSON ({"installed": {...}}) or a flat {"client_id", "client_secret"}.
    static func parseClient(_ data: Data) -> Client? {
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let d = (j["installed"] as? [String: Any]) ?? j
        guard let id = d["client_id"] as? String, let secret = d["client_secret"] as? String, !id.isEmpty else { return nil }
        return Client(client_id: id, client_secret: secret)
    }

    @MainActor static var client: Client? {
        if let s = KeychainStore.shared.get(keychainKey), let c = parseClient(Data(s.utf8)) { return c }
        // First launch after setup: move the file into the Keychain, then remove the file (Oli wrote nothing else there).
        if let d = try? Data(contentsOf: importFile), let c = parseClient(d) {
            remember(c)
            try? FileManager.default.removeItem(at: importFile)
            return c
        }
        // Or the JSON Google downloads at the end of « Créer un client OAuth » (left where it is).
        if let c = downloadedClient() { remember(c); return c }
        return nil
    }

    @MainActor private static func remember(_ c: Client) {
        if let enc = try? JSONEncoder().encode(c) { KeychainStore.shared.set(keychainKey, value: String(decoding: enc, as: UTF8.self)) }
    }

    /// ~/Downloads/client_secret_….apps.googleusercontent.com.json, newest first.
    static func downloadedClient() -> Client? {
        let dl = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        let files = ((try? FileManager.default.contentsOfDirectory(at: dl, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("client_secret_") && $0.pathExtension == "json" }
            .sorted { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
                    > ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
        for f in files { if let d = try? Data(contentsOf: f), let c = parseClient(d) { return c } }
        return nil
    }

    @MainActor static var isConfigured: Bool { client != nil }

    // MARK: Sign in

    /// Opens Google in the browser and waits for the answer. Returns the address and a refresh token.
    @MainActor static func signIn(hint: String? = nil) async throws -> (email: String, refresh: String) {
        guard let c = client else { throw Failure.notConfigured }
        let verifier = randomURLSafe(48)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        let state = randomURLSafe(16)
        let server = LoopbackServer()
        let port = try await server.start()
        let redirect = "http://127.0.0.1:\(port)"
        var comps = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        comps.queryItems = [
            .init(name: "client_id", value: c.client_id), .init(name: "redirect_uri", value: redirect),
            .init(name: "response_type", value: "code"), .init(name: "scope", value: scopes),
            .init(name: "code_challenge", value: challenge), .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state), .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent select_account"),
        ] + (hint.map { [URLQueryItem(name: "login_hint", value: $0)] } ?? [])
        NSWorkspace.shared.open(comps.url!)

        let query = try await server.waitForRedirect(timeout: 300)
        let params = Dictionary(uniqueKeysWithValues: (URLComponents(string: "http://x/?" + query)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        if let e = params["error"] { throw Failure.denied(e == "access_denied" ? "accès refusé" : e) }
        guard params["state"] == state, let code = params["code"], !code.isEmpty else { throw Failure.denied("réponse inattendue") }

        let tokens = try await post(["code": code, "client_id": c.client_id, "client_secret": c.client_secret,
                                     "redirect_uri": redirect, "grant_type": "authorization_code", "code_verifier": verifier])
        guard let refresh = tokens["refresh_token"] as? String else { throw Failure.denied("pas de jeton de renouvellement") }
        let email = (tokens["id_token"] as? String).flatMap(emailFromIDToken) ?? hint ?? ""
        if let access = tokens["access_token"] as? String {
            cache[refresh] = (access, Date().addingTimeInterval(Double(tokens["expires_in"] as? Int ?? 3500) - 60))
        }
        return (email, refresh)
    }

    // MARK: Access tokens

    @MainActor private static var cache: [String: (token: String, until: Date)] = [:]

    /// A fresh access token for IMAP (cached until it expires).
    @MainActor static func accessToken(refresh: String) async throws -> String {
        if let c = cache[refresh], c.until > Date() { return c.token }
        guard let c = client else { throw Failure.notConfigured }
        let j = try await post(["client_id": c.client_id, "client_secret": c.client_secret,
                                "refresh_token": refresh, "grant_type": "refresh_token"])
        guard let t = j["access_token"] as? String else {
            throw Failure.denied((j["error"] as? String) == "invalid_grant"
                                 ? "l’autorisation a expiré, reconnecte la boîte (« Se connecter avec Google »)" : "jeton refusé")
        }
        cache[refresh] = (t, Date().addingTimeInterval(Double(j["expires_in"] as? Int ?? 3500) - 60))
        return t
    }

    private static func post(_ form: [String: String]) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "content-type")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        req.httpBody = Data(form.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&").utf8)
        let data: Data
        do { (data, _) = try await URLSession.shared.data(for: req) } catch { throw Failure.network(error.localizedDescription) }
        let j = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        if j["access_token"] == nil, let e = j["error"] as? String, e != "invalid_grant" {
            throw Failure.denied((j["error_description"] as? String) ?? e)
        }
        return j
    }

    // MARK: Helpers (pure)

    static func emailFromIDToken(_ jwt: String) -> String? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var b = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        guard let d = Data(base64Encoded: b),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        return j["email"] as? String
    }

    static func randomURLSafe(_ bytes: Int) -> String {
        var b = [UInt8](repeating: 0, count: bytes)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes, &b)
        return Data(b).base64URL
    }
}

extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func take() -> Bool { lock.lock(); defer { lock.unlock() }; if done { return false }; done = true; return true }
}

// MARK: - Tiny HTTP listener on 127.0.0.1 for Google's redirect (one request, then it closes)

final class LoopbackServer: @unchecked Sendable {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "studio.oculot.oli.oauth")
    private var continuation: CheckedContinuation<String, Error>?
    private let lock = NSLock()

    func start() async throws -> UInt16 {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let l = try NWListener(using: params)
        listener = l
        l.newConnectionHandler = { [weak self] c in self?.handle(c) }
        let once = OnceFlag()
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<UInt16, Error>) in
            l.stateUpdateHandler = { state in
                switch state {
                case .ready: if once.take() { cont.resume(returning: l.port?.rawValue ?? 0) }
                case .failed(let e): if once.take() { cont.resume(throwing: e) }
                default: break
                }
            }
            l.start(queue: queue)
        }
    }

    func waitForRedirect(timeout: TimeInterval) async throws -> String {
        defer { listener?.cancel() }
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            lock.lock(); continuation = cont; lock.unlock()
            queue.asyncAfter(deadline: .now() + timeout) { [weak self] in self?.finish(.failure(GoogleOAuth.Failure.cancelled)) }
        }
    }

    private func finish(_ r: Result<String, Error>) {
        lock.lock(); let c = continuation; continuation = nil; lock.unlock()
        c?.resume(with: r)
    }

    private func handle(_ c: NWConnection) {
        c.start(queue: queue)
        c.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, _, _ in
            let req = String(decoding: data ?? Data(), as: UTF8.self)
            // « GET /?code=…&state=… HTTP/1.1 »
            let path = req.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
            let query = path.split(separator: "?", maxSplits: 1).dropFirst().first.map(String.init) ?? ""
            let ok = query.contains("code=")
            let body = """
            <!doctype html><meta charset="utf-8"><title>Oli</title>
            <body style="font-family:-apple-system,sans-serif;background:#0E0F11;color:#F5F6F8;display:grid;place-items:center;height:100vh;margin:0">
            <div style="text-align:center"><div style="font-size:48px">\(ok ? "✨" : "🤔")</div>
            <h2>\(ok ? "C’est branché ! Tu peux revenir à Oli." : "Connexion annulée. Tu peux fermer cet onglet.")</h2></div></body>
            """
            let resp = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n" + body
            c.send(content: Data(resp.utf8), completion: .contentProcessed { _ in c.cancel() })
            if path.hasPrefix("/favicon") { return }
            self?.finish(.success(query))
        }
    }
}
