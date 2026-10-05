import Foundation
import Network

// MARK: - Client IMAP minimal (lecture + rangement)
// TLS sur le port 993, une commande à la fois. Lecture en BODY.PEEK : lire la liste dans Oli ne
// marque aucun mail comme lu. Ranger = UID MOVE vers « Oli/<Catégorie> » : rien n'est supprimé, et
// la réponse COPYUID donne les nouveaux numéros pour pouvoir tout remettre dans la boîte de réception.

enum ImapError: Error, LocalizedError {
    case closed, timeout, refused(String), failed(String)
    var errorDescription: String? {
        switch self {
        case .closed:           return "Le serveur mail a coupé la connexion."
        case .timeout:          return "Le serveur mail ne répond pas."
        case .refused(let m):   return "Adresse ou mot de passe refusé (\(m)). Pour Gmail ou iCloud, il faut un mot de passe d’application."
        case .failed(let m):    return "Le serveur mail a refusé : \(m)"
        }
    }
}

/// One untagged response: text parts with the literals ({n} blocks) that followed them.
struct ImapItem: Sendable {
    var text = ""
    var literals: [(after: String, data: Data)] = []
}

final class ImapClient: @unchecked Sendable {
    private let conn: NWConnection
    private var buffer = Data()
    private var tag = 0
    private let queue = DispatchQueue(label: "studio.oculot.oli.imap")

    /// Incoming server for well-known providers; OVH (Oculot's host) otherwise.
    static func preset(for address: String) -> (host: String, port: Int) {
        let domain = address.split(separator: "@").last.map { $0.lowercased() } ?? ""
        switch domain {
        case "gmail.com", "googlemail.com": return ("imap.gmail.com", 993)
        case "icloud.com", "me.com", "mac.com": return ("imap.mail.me.com", 993)
        case "outlook.com", "outlook.fr", "hotmail.com", "hotmail.fr", "live.com", "live.fr": return ("outlook.office365.com", 993)
        case "yahoo.com", "yahoo.fr": return ("imap.mail.yahoo.com", 993)
        case "orange.fr", "wanadoo.fr": return ("imap.orange.fr", 993)
        case "free.fr": return ("imap.free.fr", 993)
        default: return ("ssl0.ovh.net", 993)
        }
    }

    /// `tls: false` only for the local fake server of the tests.
    init(host: String, port: Int, tls: Bool = true) {
        conn = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(integerLiteral: UInt16(port)), using: tls ? .tls : .tcp)
    }

    deinit { conn.cancel() }

    // MARK: Connection

    func connect(timeout: TimeInterval = 20) async throws {
        let once = Once()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready: once.run { cont.resume() }
                case .failed(let e): once.run { cont.resume(throwing: e) }
                case .waiting(let e): once.run { cont.resume(throwing: e) }
                default: break
                }
            }
            conn.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { once.run { cont.resume(throwing: ImapError.timeout) } }
        }
        _ = try await readLine()   // greeting
    }

    func login(_ user: String, _ password: String) async throws {
        do { _ = try await command("LOGIN \(MailParsing.quote(user)) \(MailParsing.quote(password))") }
        catch ImapError.failed(let m) { throw ImapError.refused(m) }
    }

    /// Gmail with « Se connecter avec Google »: SASL XOAUTH2, no password.
    func authenticate(user: String, accessToken: String) async throws {
        do { _ = try await command("AUTHENTICATE XOAUTH2 " + MailParsing.xoauth2(user: user, token: accessToken)) }
        catch ImapError.failed(let m) { throw ImapError.refused(m) }
    }

    func logout() async {
        _ = try? await command("LOGOUT")
        conn.cancel()
    }

    // MARK: Commands

    /// Sends one tagged command; returns the untagged items. Throws on NO / BAD.
    @discardableResult
    func command(_ cmd: String) async throws -> [ImapItem] {
        tag += 1
        let t = "A\(tag)"
        try await send(Data("\(t) \(cmd)\r\n".utf8))
        var items: [ImapItem] = []
        while true {
            var item = ImapItem()
            var line = try await readLine()
            // « + … »: the server waits for more (XOAUTH2 error details); an empty line lets it answer NO.
            if line.hasPrefix("+") {
                try await send(Data("\r\n".utf8))
                continue
            }
            // A line ending in {n} is followed by n raw bytes, then the rest of the same response.
            while let n = Self.literalLength(line) {
                let data = try await readBytes(n)
                item.literals.append((after: line, data: data))
                item.text += line + " "
                line = try await readLine()
            }
            item.text += line
            if item.text.hasPrefix(t + " ") {
                let rest = item.text.dropFirst(t.count + 1)
                if rest.hasPrefix("OK") { return items }
                throw ImapError.failed(String(rest.dropFirst(3)).trimmingCharacters(in: .whitespaces))
            }
            items.append(item)
        }
    }

    private static func literalLength(_ line: String) -> Int? {
        guard line.hasSuffix("}"), let open = line.lastIndex(of: "{") else { return nil }
        return Int(line[line.index(after: open)..<line.index(before: line.endIndex)].replacingOccurrences(of: "+", with: ""))
    }

    // MARK: Mail operations

    /// « / » or « . » between « Oli » and the category, as the server wants it.
    func delimiter() async -> String {
        let items = (try? await command("LIST \"\" \"\"")) ?? []
        return items.first.map { MailParsing.delimiter($0.text) } ?? "/"
    }

    /// Unread count of a mailbox without opening it.
    func unseen(_ mailbox: String = "INBOX") async -> Int? {
        guard let items = try? await command("STATUS \(MailParsing.quote(mailbox)) (UNSEEN)"),
              let r = items.first?.text.range(of: #"UNSEEN (\d+)"#, options: .regularExpression) else { return nil }
        return Int(items.first!.text[r].split(separator: " ").last ?? "")
    }

    /// Opens a mailbox; returns the number of messages in it.
    @discardableResult
    func select(_ mailbox: String) async throws -> Int {
        let items = try await command("SELECT \(MailParsing.quote(mailbox))")
        for i in items {
            let p = i.text.split(separator: " ")
            if p.count >= 3, p[2] == "EXISTS", let n = Int(p[1]) { return n }
        }
        return 0
    }

    /// The last `count` messages of the selected mailbox, newest first. Nothing is marked read.
    func recent(_ count: Int, total: Int) async throws -> [OliMail] {
        guard total > 0 else { return [] }
        let from = max(1, total - count + 1)
        let items = try await command("FETCH \(from):\(total) (UID FLAGS INTERNALDATE BODY.PEEK[HEADER.FIELDS (FROM SUBJECT MESSAGE-ID LIST-UNSUBSCRIBE)] BODY.PEEK[TEXT]<0.1500>)")
        var out: [OliMail] = []
        for i in items where i.text.contains("FETCH") {
            guard let uidR = i.text.range(of: #"UID (\d+)"#, options: .regularExpression),
                  let uid = Int(i.text[uidR].dropFirst(4)) else { continue }
            let flags = i.text.range(of: #"FLAGS \(([^)]*)\)"#, options: .regularExpression).map { String(i.text[$0]) } ?? ""
            let dateStr = i.text.range(of: #"INTERNALDATE "([^"]+)""#, options: .regularExpression)
                .map { String(i.text[$0].dropFirst(14).dropLast()) } ?? ""
            let headerData = i.literals.first { $0.after.contains("HEADER") }?.data ?? Data()
            let bodyData = i.literals.first { $0.after.contains("TEXT") }?.data ?? Data()
            let h = MailParsing.headers(String(decoding: headerData, as: UTF8.self))
            let from = MailParsing.address(h["from"] ?? "")
            out.append(OliMail(uid: uid, fromName: from.name, fromAddress: from.address,
                               subject: MailParsing.decodeWords(h["subject"] ?? "(sans objet)"),
                               date: MailParsing.internalDate(dateStr) ?? Date(),
                               unread: !flags.contains("\\Seen"),
                               snippet: MailParsing.snippet(bodyData),
                               messageId: (h["message-id"] ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "<> ")),
                               isList: h["list-unsubscribe"] != nil))
        }
        return out.sorted { $0.date > $1.date }
    }

    func create(_ mailbox: String) async {
        _ = try? await command("CREATE \(MailParsing.quote(mailbox))")   // « already exists » is fine
        _ = try? await command("SUBSCRIBE \(MailParsing.quote(mailbox))")
    }

    /// Moves messages of the selected mailbox; returns old UID → new UID in `to` (when the server says).
    func move(_ uids: [Int], to mailbox: String) async throws -> [Int: Int] {
        guard !uids.isEmpty else { return [:] }
        let items = try await command("UID MOVE \(uids.map(String.init).joined(separator: ",")) \(MailParsing.quote(mailbox))")
        var map: [Int: Int] = [:]
        for i in items { map.merge(MailParsing.copyUID(i.text)) { a, _ in a } }
        return map
    }

    // MARK: Socket

    private func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.send(content: data, completion: .contentProcessed { e in
                if let e { cont.resume(throwing: e) } else { cont.resume() }
            })
        }
    }

    private func receiveMore() async throws {
        let once = Once()
        let data: Data = try await withCheckedThrowingContinuation { cont in
            conn.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { d, _, complete, e in
                once.run {
                    if let e { cont.resume(throwing: e) }
                    else if let d, !d.isEmpty { cont.resume(returning: d) }
                    else if complete { cont.resume(throwing: ImapError.closed) }
                    else { cont.resume(returning: Data()) }
                }
            }
            queue.asyncAfter(deadline: .now() + 30) { once.run { cont.resume(throwing: ImapError.timeout) } }
        }
        buffer.append(data)
    }

    private func readLine() async throws -> String {
        while true {
            if let r = buffer.range(of: Data("\r\n".utf8)) {
                let line = buffer.subdata(in: buffer.startIndex..<r.lowerBound)
                buffer.removeSubrange(buffer.startIndex..<r.upperBound)
                return String(decoding: line, as: UTF8.self)
            }
            try await receiveMore()
        }
    }

    private func readBytes(_ n: Int) async throws -> Data {
        while buffer.count < n { try await receiveMore() }
        let d = buffer.prefix(n)
        buffer.removeFirst(n)
        return Data(d)
    }
}

/// Resumes a continuation once, whatever fires first (answer, error or timeout).
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func run(_ f: () -> Void) {
        lock.lock()
        let first = !done
        done = true
        lock.unlock()
        if first { f() }
    }
}
