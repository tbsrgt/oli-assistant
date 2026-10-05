import AppKit

// MARK: - Plusieurs boîtes mail (lecture et rangement)
// La boîte des Réglages (celle qui envoie les fichiers) plus les boîtes ajoutées depuis la page Mails
// (Gmail, iCloud, OVH…). Les mots de passe restent dans le Trousseau (« mail-extra-accounts »).
// Gmail et iCloud demandent un mot de passe d'application : Oli ouvre la bonne page et le reprend
// au presse-papiers dès qu'on clique « Copier » (espaces retirés), comme la connexion en un clic.

struct MailBox: Codable, Equatable, Sendable, Identifiable {
    let address: String
    let password: String          // app password, or Google's refresh token when `google` is true
    var google: Bool? = nil       // « Se connecter avec Google » (XOAUTH2)
    var id: String { address.lowercased() }

    var isGmail: Bool { ["gmail.com", "googlemail.com"].contains(domain) }
    var isICloud: Bool { ["icloud.com", "me.com", "mac.com"].contains(domain) }
    var domain: String { address.split(separator: "@").last.map { $0.lowercased() } ?? "" }
}

enum MailAccounts {
    private static let key = "mail-extra-accounts"
    private static let selectedKey = "mailSelectedAccount"

    /// Google shows « abcd efgh ijkl mnop »: the servers want it without spaces.
    static func cleanAppPassword(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.range(of: #"^[a-z]{4}( [a-z]{4}){3}$"#, options: .regularExpression) != nil ? t.replacingOccurrences(of: " ", with: "") : t
    }

    /// 16 lowercase letters, with or without spaces: a Google / Apple app password on the clipboard.
    static func looksLikeAppPassword(_ s: String) -> Bool {
        s.trimmingCharacters(in: .whitespacesAndNewlines).range(of: #"^[a-z]{4} ?[a-z]{4} ?[a-z]{4} ?[a-z]{4}$"#, options: .regularExpression) != nil
    }

    /// Where to create an app password, for the address typed.
    static func appPasswordPage(for address: String) -> URL? {
        let d = address.split(separator: "@").last.map { $0.lowercased() } ?? ""
        if ["gmail.com", "googlemail.com"].contains(d) { return URL(string: "https://myaccount.google.com/apppasswords") }
        if ["icloud.com", "me.com", "mac.com"].contains(d) { return URL(string: "https://account.apple.com/account/manage") }
        return nil
    }

    @MainActor static var extras: [MailBox] {
        (KeychainStore.shared.get(key)?.data(using: .utf8)).flatMap { try? JSONDecoder().decode([MailBox].self, from: $0) } ?? []
    }

    @MainActor static var all: [MailBox] {
        var out: [MailBox] = []
        if let a = EmailSender.account { out.append(MailBox(address: a.address, password: a.password)) }
        for e in extras where !out.contains(where: { $0.id == e.id }) { out.append(e) }
        return out
    }

    @MainActor static var selected: MailBox? {
        let want = UserDefaults.standard.string(forKey: selectedKey)
        return all.first { $0.id == want } ?? all.first
    }

    @MainActor static func select(_ b: MailBox) { UserDefaults.standard.set(b.id, forKey: selectedKey) }

    @MainActor static func add(_ b: MailBox) {
        var list = extras.filter { $0.id != b.id }
        list.append(b)
        if let d = try? JSONEncoder().encode(list) { KeychainStore.shared.set(key, value: String(decoding: d, as: UTF8.self)) }
        select(b)
    }

    @MainActor static func remove(_ b: MailBox) {
        let list = extras.filter { $0.id != b.id }
        if list.isEmpty { KeychainStore.shared.remove(key) }
        else if let d = try? JSONEncoder().encode(list) { KeychainStore.shared.set(key, value: String(decoding: d, as: UTF8.self)) }
    }

    /// « Se connecter avec Google » from start to finish: browser, test, Trousseau, mailbox shown.
    /// nil when it worked, else what went wrong.
    @MainActor static func connectGoogle(hint: String? = nil) async -> String? {
        do {
            let r = try await GoogleOAuth.signIn(hint: hint)
            let box = MailBox(address: r.email.lowercased(), password: r.refresh, google: true)
            if let problem = await test(box) {
                appendAppLog("oli.log", "Connexion Google : IMAP refusé (\(problem))")
                return problem
            }
            add(box)
            SoundEngine.shared.play("approve")
            appendAppLog("oli.log", "Boîte Google connectée en un clic (\(box.domain))")
            MailCenter.shared.switchTo(box)
            NotificationCenter.default.post(name: .oliConnectionsChanged, object: nil)
            return nil
        } catch {
            appendAppLog("oli.log", "Connexion Google : \(error.localizedDescription)")
            return error.localizedDescription
        }
    }

    /// Logs in over IMAP: nil when it works, else a French explanation.
    @MainActor static func test(_ b: MailBox) async -> String? {
        let preset = ImapClient.preset(for: b.address)
        do {
            let token = b.google == true ? try await GoogleOAuth.accessToken(refresh: b.password) : nil
            let c = ImapClient(host: preset.host, port: preset.port)
            try await c.connect()
            if let token { try await c.authenticate(user: b.address, accessToken: token) }
            else { try await c.login(b.address, b.password) }
            await c.logout()
            return nil
        } catch ImapError.refused where b.google == true {
            return "Gmail refuse la connexion : vérifie qu’IMAP est activé (Gmail → Paramètres → Transfert et POP/IMAP)."
        } catch ImapError.refused {
            if b.isGmail { return "Google refuse : il faut un mot de passe d’application (16 lettres), pas ton mot de passe Gmail. La validation en deux étapes doit être activée sur ton compte Google." }
            if b.isICloud { return "Apple refuse : il faut un mot de passe pour app (identifiant Apple → Connexion et sécurité)." }
            return "Adresse ou mot de passe refusé."
        } catch {
            return error.localizedDescription
        }
    }
}
