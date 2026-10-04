import Foundation

// MARK: - Email (envoi direct depuis Oli)
// The user's own mailbox, over SMTP, through the system curl (TLS, MIME, attachments).
// Settings live in the Keychain. Oli only sends when the user clicks « Envoyer ».

struct EmailAccount: Sendable {
    let address: String
    let name: String
    let password: String
    let host: String
    let port: Int

    /// smtps:// for implicit TLS (465), smtp:// + STARTTLS required otherwise.
    var url: String { port == 465 ? "smtps://\(host):465" : "smtp://\(host):\(port)" }
}

enum EmailSender {
    static let keys = ["mail-address", "mail-name", "mail-password", "mail-host", "mail-port"]

    /// Outgoing server for well-known providers; OVH (Oculot's host) otherwise.
    static func preset(for address: String) -> (host: String, port: Int) {
        let domain = address.split(separator: "@").last.map { $0.lowercased() } ?? ""
        switch domain {
        case "gmail.com", "googlemail.com": return ("smtp.gmail.com", 465)
        case "icloud.com", "me.com", "mac.com": return ("smtp.mail.me.com", 587)
        case "outlook.com", "outlook.fr", "hotmail.com", "hotmail.fr", "live.com", "live.fr": return ("smtp.office365.com", 587)
        case "yahoo.com", "yahoo.fr": return ("smtp.mail.yahoo.com", 465)
        case "orange.fr", "wanadoo.fr": return ("smtp.orange.fr", 465)
        case "free.fr": return ("smtp.free.fr", 465)
        default: return ("ssl0.ovh.net", 465)
        }
    }

    /// The configured account, or nil when the address or the password is missing.
    @MainActor static var account: EmailAccount? {
        let k = KeychainStore.shared
        guard let address = k.get("mail-address"), !address.isEmpty,
              let password = k.get("mail-password"), !password.isEmpty else { return nil }
        let preset = preset(for: address)
        let host = k.get("mail-host").flatMap { $0.isEmpty ? nil : $0 } ?? preset.host
        let port = k.get("mail-port").flatMap { Int($0) } ?? preset.port
        return EmailAccount(address: address, name: k.get("mail-name") ?? "", password: password, host: host, port: port)
    }

    enum Failure: Error, LocalizedError {
        case curl(String)
        var errorDescription: String? { if case .curl(let m) = self { return m }; return nil }
    }

    /// Sends one message (optionally with a file). Throws a readable French error.
    static func send(_ account: EmailAccount, to recipients: [String], subject: String, body: String,
                     attachment: URL? = nil) async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("oli-mail-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let bodyFile = tmp.appendingPathComponent("message.txt")
        try body.write(to: bodyFile, atomically: true, encoding: .utf8)

        let from = account.name.isEmpty ? "<\(account.address)>" : "\(encodeHeader(account.name)) <\(account.address)>"
        var args = [account.url, "-sS", "--max-time", "180", "-K", "-",
                    "--mail-from", account.address]
        if account.port != 465 { args.append("--ssl-reqd") }
        for r in recipients { args += ["--mail-rcpt", r] }
        args += ["-H", "From: \(from)", "-H", "To: \(recipients.joined(separator: ", "))",
                 "-H", "Subject: \(encodeHeader(subject))", "-H", "X-Mailer: Oli (Oculot)"]
        if let attachment {
            // curl wraps the parts in a single multipart/mixed message
            args += ["-F", "=<\(bodyFile.path);type=text/plain; charset=utf-8;encoder=quoted-printable",
                     "-F", "file=@\(attachment.path);encoder=base64"]
        } else {
            args += ["-F", "=<\(bodyFile.path);type=text/plain; charset=utf-8;encoder=quoted-printable"]
        }
        try await run(args, account: account)
    }

    /// Logs in and says NOOP: checks the server, the address and the password without sending anything.
    static func test(_ account: EmailAccount) async throws {
        var args = [account.url, "-sS", "--max-time", "30", "-K", "-", "-X", "NOOP"]
        if account.port != 465 { args.append("--ssl-reqd") }
        try await run(args, account: account)
    }

    // MARK: Internals

    private static func run(_ args: [String], account: EmailAccount) async throws {
        let result: (Int32, String) = await Task.detached(priority: .userInitiated) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            p.arguments = args
            let input = Pipe(), errPipe = Pipe()
            p.standardInput = input
            p.standardError = errPipe
            p.standardOutput = Pipe()
            do { try p.run() } catch { return (-1, error.localizedDescription) }
            // Credentials through curl's config on stdin: never visible in the process list.
            let esc = { (s: String) in s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") }
            input.fileHandleForWriting.write(Data("user = \"\(esc(account.address)):\(esc(account.password))\"\n".utf8))
            try? input.fileHandleForWriting.close()
            let err = String(decoding: errPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            p.waitUntilExit()
            return (p.terminationStatus, err)
        }.value
        guard result.0 != 0 else { return }
        throw Failure.curl(explain(code: result.0, stderr: result.1))
    }

    static func explain(code: Int32, stderr: String) -> String {
        switch code {
        case 67: return "Adresse ou mot de passe refusé. Pour Gmail ou iCloud, il faut un mot de passe d’application."
        case 6: return "Serveur mail introuvable : vérifie le serveur dans les Réglages."
        case 7, 28: return "Impossible de joindre le serveur mail (réseau ou port bloqué)."
        case 35, 60: return "Connexion sécurisée impossible avec le serveur mail."
        case 55, 26: return "Le fichier joint n’a pas pu être envoyé (trop gros ?)."
        case 64: return "Le serveur exige une connexion chiffrée que je n’arrive pas à établir."
        default:
            let line = stderr.split(separator: "\n").last.map(String.init) ?? ""
            return "Envoi impossible (\(code))" + (line.isEmpty ? "." : " : \(line)")
        }
    }

    /// RFC 2047 encoded word, so accents survive in headers.
    static func encodeHeader(_ s: String) -> String {
        s.allSatisfy { $0.isASCII } ? s : "=?UTF-8?B?\(Data(s.utf8).base64EncodedString())?="
    }
}
