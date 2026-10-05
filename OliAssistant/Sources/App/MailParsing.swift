import Foundation

// MARK: - Mails : logique pure (testée par scripts/test-mail.sh)
// Décodage des en-têtes, extrait lisible, réponses IMAP, catégories et premier tri sans Claude.

enum MailCategory: String, Codable, CaseIterable, Sendable {
    case important, clients, factures, administratif, notifications, newsletters, promotions, perso

    var label: String {
        switch self {
        case .important:     return "À traiter"
        case .clients:       return "Clients"
        case .factures:      return "Factures"
        case .administratif: return "Administratif"
        case .notifications: return "Notifications"
        case .newsletters:   return "Newsletters"
        case .promotions:    return "Promotions"
        case .perso:         return "Perso"
        }
    }

    var icon: String {
        switch self {
        case .important:     return "exclamationmark.circle.fill"
        case .clients:       return "person.2.fill"
        case .factures:      return "eurosign.circle.fill"
        case .administratif: return "building.columns.fill"
        case .notifications: return "bell.fill"
        case .newsletters:   return "newspaper.fill"
        case .promotions:    return "tag.fill"
        case .perso:         return "heart.fill"
        }
    }

    var color: String {
        switch self {
        case .important:     return "#FF5B37"
        case .clients:       return "#3B9EFF"
        case .factures:      return "#22C55E"
        case .administratif: return "#A78BFA"
        case .notifications: return "#8E939C"
        case .newsletters:   return "#FFB547"
        case .promotions:    return "#E1306C"
        case .perso:         return "#F7C3D4"
        }
    }

    /// Folder under « Oli » on the mail server (ASCII: no modified UTF-7 needed). nil = stays in the inbox.
    var folder: String? {
        switch self {
        case .important:     return nil
        case .clients:       return "Clients"
        case .factures:      return "Factures"
        case .administratif: return "Administratif"
        case .notifications: return "Notifications"
        case .newsletters:   return "Newsletters"
        case .promotions:    return "Promotions"
        case .perso:         return "Perso"
        }
    }
}

struct OliMail: Identifiable, Sendable, Equatable {
    let uid: Int
    let fromName: String
    let fromAddress: String
    let subject: String
    let date: Date
    let unread: Bool
    let snippet: String
    let messageId: String
    let isList: Bool            // List-Unsubscribe header: a mailing
    var id: Int { uid }
}

enum MailParsing {

    // MARK: Headers

    /// Unfolds and splits a raw header block; names are lowercased.
    static func headers(_ raw: String) -> [String: String] {
        var out: [String: String] = [:]
        var lastKey: String?
        for line in raw.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            if let first = line.first, first == " " || first == "\t", let k = lastKey {
                out[k, default: ""] += " " + line.trimmingCharacters(in: .whitespaces)
                continue
            }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let k = line[..<colon].lowercased().trimmingCharacters(in: .whitespaces)
            out[k] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            lastKey = k
        }
        return out
    }

    /// RFC 2047 encoded words (=?UTF-8?B?…?= / =?ISO-8859-1?Q?…?=), spaces between words dropped.
    static func decodeWords(_ s: String) -> String {
        let pattern = #"=\?([^?]+)\?([BbQq])\?([^?]*)\?="#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        let ns = s as NSString
        var result = ""
        var last = 0
        var previousWasWord = false
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            let between = ns.substring(with: NSRange(location: last, length: m.range.location - last))
            if !(previousWasWord && between.trimmingCharacters(in: .whitespaces).isEmpty) { result += between }
            let charset = ns.substring(with: m.range(at: 1)).lowercased()
            let mode = ns.substring(with: m.range(at: 2)).uppercased()
            let text = ns.substring(with: m.range(at: 3))
            let data: Data? = mode == "B" ? Data(base64Encoded: padBase64(text))
                                          : qDecode(text.replacingOccurrences(of: "_", with: " "))
            let enc: String.Encoding = charset.contains("8859") || charset.contains("latin") ? .isoLatin1
                                     : charset.contains("1252") ? .windowsCP1252 : .utf8
            result += data.flatMap { String(data: $0, encoding: enc) } ?? text
            last = m.range.location + m.range.length
            previousWasWord = true
        }
        result += ns.substring(from: last)
        return result
    }

    private static func padBase64(_ s: String) -> String {
        let r = s.count % 4
        return r == 0 ? s : s + String(repeating: "=", count: 4 - r)
    }

    /// Quoted-printable bytes (=XX), soft line breaks removed.
    static func qDecode(_ s: String) -> Data {
        var out = Data()
        let bytes = Array(s.replacingOccurrences(of: "=\r\n", with: "").replacingOccurrences(of: "=\n", with: "").utf8)
        var i = 0
        while i < bytes.count {
            if bytes[i] == UInt8(ascii: "="), i + 2 < bytes.count,
               let v = UInt8(String(decoding: bytes[(i + 1)...(i + 2)], as: UTF8.self), radix: 16) {
                out.append(v); i += 3
            } else {
                out.append(bytes[i]); i += 1
            }
        }
        return out
    }

    /// « "Marie Dupont" <marie@x.fr> » → (Marie Dupont, marie@x.fr)
    static func address(_ raw: String) -> (name: String, address: String) {
        let s = decodeWords(raw)
        if let lt = s.lastIndex(of: "<"), let gt = s.lastIndex(of: ">"), lt < gt {
            let addr = String(s[s.index(after: lt)..<gt]).trimmingCharacters(in: .whitespaces)
            var name = String(s[..<lt]).trimmingCharacters(in: .whitespaces)
            name = name.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            return (name.isEmpty ? addr : name, addr)
        }
        let a = s.trimmingCharacters(in: .whitespaces)
        return (a, a)
    }

    /// First words of the body, readable: MIME parts, HTML, quoted-printable and base64 cleaned up.
    static func snippet(_ raw: Data, limit: Int = 180) -> String {
        var text = String(decoding: raw, as: UTF8.self)
        if text.contains("=\r\n") || text.range(of: #"=[0-9A-F]{2}"#, options: .regularExpression) != nil {
            text = String(decoding: qDecode(text), as: UTF8.self)
        }
        var kept: [String] = []
        for line in text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n") {
            let l = line.trimmingCharacters(in: .whitespaces)
            if l.isEmpty || l.hasPrefix("--") || l.hasPrefix("This is a multi-part") { continue }
            // MIME headers of the parts and their parameters (boundary=…, charset=…).
            if l.range(of: #"^(content|mime|x)-[a-z-]*:"#, options: [.regularExpression, .caseInsensitive]) != nil { continue }
            if l.range(of: #"^[a-z-]+=("|[^\s]+;?$)"#, options: [.regularExpression, .caseInsensitive]) != nil { continue }
            // A long run without spaces is base64: try to read it.
            if l.count >= 40, !l.contains(" "), let d = Data(base64Encoded: padBase64(l)), let s = String(data: d, encoding: .utf8) {
                kept.append(s); continue
            }
            if l.count >= 60, !l.contains(" ") { continue }
            kept.append(l)
        }
        var s = kept.joined(separator: " ")
        s = s.replacingOccurrences(of: #"<style[\s\S]*?</style>"#, with: " ", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        for (e, r) in [("&nbsp;", " "), ("&amp;", "&"), ("&eacute;", "é"), ("&egrave;", "è"), ("&agrave;", "à"), ("&#39;", "'"), ("&quot;", "\"")] {
            s = s.replacingOccurrences(of: e, with: r)
        }
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        return s.count > limit ? String(s.prefix(limit)) + "…" : s
    }

    // MARK: IMAP responses

    /// « 05-Oct-2026 09:12:00 +0200 »
    static func internalDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "dd-MMM-yyyy HH:mm:ss Z"
        return f.date(from: s.trimmingCharacters(in: .whitespaces))
    }

    /// IMAP set « 9:11,14 » → [9, 10, 11, 14]
    static func expandSet(_ s: String) -> [Int] {
        s.split(separator: ",").flatMap { part -> [Int] in
            let ends = part.split(separator: ":").compactMap { Int($0) }
            if ends.count == 2 { return ends[0] <= ends[1] ? Array(ends[0]...ends[1]) : Array(ends[1]...ends[0]) }
            return ends
        }
    }

    /// « [COPYUID 1700 3,5:6 20:22] » → [3: 20, 5: 21, 6: 22]
    static func copyUID(_ line: String) -> [Int: Int] {
        guard let r = line.range(of: #"COPYUID \d+ ([0-9:,]+) ([0-9:,]+)"#, options: .regularExpression) else { return [:] }
        let parts = line[r].split(separator: " ")
        guard parts.count == 4 else { return [:] }
        let from = expandSet(String(parts[2])), to = expandSet(String(parts[3]))
        guard from.count == to.count else { return [:] }
        return Dictionary(uniqueKeysWithValues: zip(from, to))
    }

    /// Hierarchy delimiter from « * LIST (\Noselect) "/" "" ».
    static func delimiter(_ line: String) -> String {
        guard let r = line.range(of: #"\) "(.)""#, options: .regularExpression) else { return "/" }
        return String(line[r].dropFirst(3).prefix(1))
    }

    /// SASL XOAUTH2 initial response for IMAP AUTHENTICATE (« Se connecter avec Google »).
    static func xoauth2(user: String, token: String) -> String {
        Data("user=\(user)\u{01}auth=Bearer \(token)\u{01}\u{01}".utf8).base64EncodedString()
    }

    static func quote(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    // MARK: First sort, without Claude

    static func guess(_ m: OliMail) -> MailCategory {
        let from = m.fromAddress.lowercased()
        let text = (m.subject + " " + m.snippet).lowercased()
        let has = { (words: [String]) in words.contains { text.contains($0) } }
        if has(["facture", "invoice", "reçu", "receipt", "avis d’échéance", "avis d'échéance", "paiement reçu", "votre commande"]) { return .factures }
        if has(["urssaf", "impots.gouv", "impôts", "caf.fr", "ameli", "pôle emploi", "france travail", "banque", "attestation"])
            || from.contains("impots.gouv") || from.contains("urssaf") { return .administratif }
        if has(["promo", "% de réduction", "soldes", "offre spéciale", "black friday", "code promo", "-50%", "-30%"]) { return .promotions }
        if m.isList { return .newsletters }
        if from.contains("noreply") || from.contains("no-reply") || from.contains("notification") || from.contains("notifications@")
            || from.hasPrefix("mailer-daemon") || from.contains("github.com") || from.contains("vercel.com") { return .notifications }
        return .important
    }

    // MARK: Claude's answer

    /// [{"uid":12,"cat":"factures","resume":"…"}] somewhere in Claude's text.
    static func parseClassification(_ text: String) -> [Int: (MailCategory, String)] {
        guard let a = text.firstIndex(of: "["), let b = text.lastIndex(of: "]"), a < b,
              let data = String(text[a...b]).data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [:] }
        var out: [Int: (MailCategory, String)] = [:]
        for item in arr {
            let uid = (item["uid"] as? Int) ?? (item["uid"] as? String).flatMap { Int($0) }
            guard let uid, let raw = item["cat"] as? String, let cat = MailCategory(rawValue: raw.lowercased()) else { continue }
            out[uid] = (cat, (item["resume"] as? String) ?? "")
        }
        return out
    }
}
