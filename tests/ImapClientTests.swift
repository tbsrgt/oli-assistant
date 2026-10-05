import Foundation

// ImapClient contre un faux serveur local (tests/fake_imap.py). Lancer : scripts/test-imap.sh

@main
enum ImapClientTests {
    nonisolated(unsafe) static var failures = 0
    static func check(_ label: String, _ ok: Bool, _ detail: String = "") {
        if ok { print("  ✓ \(label)") } else { print("  ✗ \(label)  \(detail)"); failures += 1 }
    }

    static func main() async {
        let port = Int(CommandLine.arguments[1])!
        do {
            let c = ImapClient(host: "127.0.0.1", port: port, tls: false)
            try await c.connect()
            try await c.login("moi@exemple.fr", "secret")
            check("connexion et identifiants", true)
            check("non lus", await c.unseen() == 1)
            let total = try await c.select("INBOX")
            check("2 mails dans la boîte", total == 2, "\(total)")
            let mails = try await c.recent(40, total: total)
            check("2 mails lus avec leurs blocs {n}", mails.count == 2, "\(mails.count)")
            if mails.count == 2 {
                check("le plus récent d'abord", mails[0].uid == 41)
                check("expéditeur décodé", mails[0].fromName == "Élodie", mails[0].fromName)
                check("non lu", mails[0].unread && !mails[1].unread)
                check("extrait", mails[0].snippet.hasPrefix("Bonjour"), mails[0].snippet)
                check("liste de diffusion repérée", mails[1].isList)
                check("Message-ID", mails[1].messageId == "b2@ovh")
            }
            check("séparateur", await c.delimiter() == "/")
            await c.create("Oli/Factures")   // NO [ALREADYEXISTS] must not throw
            let moved = try await c.move([42], to: "Oli/Factures")
            check("déplacement : nouveau numéro pour annuler", moved == [42: 300], "\(moved)")
            await c.logout()

            let bad = ImapClient(host: "127.0.0.1", port: port, tls: false)
            try await bad.connect()
            do { try await bad.login("moi@exemple.fr", "bad"); check("mauvais mot de passe refusé", false) }
            catch ImapError.refused { check("mauvais mot de passe : message clair", true) }
            await bad.logout()
        } catch {
            check("pas d'erreur", false, "\(error)")
        }
        do {
            let g = ImapClient(host: "127.0.0.1", port: port, tls: false)
            try await g.connect()
            try await g.authenticate(user: "moi@gmail.com", accessToken: "bon-jeton")
            check("Google (XOAUTH2) accepté", true)
            await g.logout()
            let g2 = ImapClient(host: "127.0.0.1", port: port, tls: false)
            try await g2.connect()
            do { try await g2.authenticate(user: "moi@gmail.com", accessToken: "perime"); check("jeton périmé refusé", false) }
            catch ImapError.refused { check("jeton périmé : refus clair, sans rester bloqué sur « + »", true) }
            await g2.logout()
        } catch {
            check("XOAUTH2 sans erreur", false, "\(error)")
        }
        check("chaîne XOAUTH2", Data(base64Encoded: MailParsing.xoauth2(user: "a@b.c", token: "t")).map { String(decoding: $0, as: UTF8.self) }
              == "user=a@b.c\u{01}auth=Bearer t\u{01}\u{01}")

        if failures > 0 { print("\(failures) échec(s)"); exit(1) }
        print("Client IMAP : tout passe")
    }
}
