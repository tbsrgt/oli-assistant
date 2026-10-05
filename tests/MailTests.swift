import Foundation

// Lecture et tri des mails (MailParsing). Lancer : scripts/test-mail.sh

@main
enum MailTests {
    nonisolated(unsafe) static var failures = 0
    static func check(_ label: String, _ ok: Bool, _ detail: String = "") {
        if ok { print("  ✓ \(label)") } else { print("  ✗ \(label)  \(detail)"); failures += 1 }
    }

    static func mail(_ from: String, _ subject: String, _ snippet: String = "", list: Bool = false) -> OliMail {
        OliMail(uid: 1, fromName: from, fromAddress: from, subject: subject, date: Date(), unread: true,
                snippet: snippet, messageId: "x@y", isList: list)
    }

    static func main() {
        print("En-têtes")
        let h = MailParsing.headers("From: =?UTF-8?B?w4lsb2RpZQ==?= <elodie@exemple.fr>\r\nSubject: Devis pour la\r\n refonte\r\nList-Unsubscribe: <mailto:x>\r\n")
        check("en-tête replié recollé", h["subject"] == "Devis pour la refonte", h["subject"] ?? "nil")
        let a = MailParsing.address(h["from"] ?? "")
        check("nom encodé en base64 décodé", a.name == "Élodie" && a.address == "elodie@exemple.fr", "\(a)")
        check("Q-encoding latin-1", MailParsing.decodeWords("=?ISO-8859-1?Q?R=E9union_demain?=") == "Réunion demain")
        check("deux mots encodés collés", MailParsing.decodeWords("=?UTF-8?B?Qm9u?= =?UTF-8?B?am91cg==?=") == "Bonjour")
        check("adresse seule", MailParsing.address("contact@oculot.studio").address == "contact@oculot.studio")
        check("nom entre guillemets", MailParsing.address("\"Marie D.\" <m@d.fr>").name == "Marie D.")

        print("Extrait")
        let s = MailParsing.snippet(Data("--b1\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\nBonjour, voici le devis de la r=C3=A9novation.=\r\n Merci !\r\n--b1--".utf8))
        check("MIME et quoted-printable nettoyés", s == "Bonjour, voici le devis de la rénovation. Merci !", s)
        let html = MailParsing.snippet(Data("<html><style>p{color:red}</style><p>Votre&nbsp;commande <b>est partie</b></p></html>".utf8))
        check("HTML nettoyé", html == "Votre commande est partie", html)
        let mp = MailParsing.snippet(Data("Content-Type: multipart/alternative;\r\n\tboundary=\"----=_Part_47608_2044\"\r\n\r\n------=_Part_47608_2044\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\nSuite des photos du chantier\r\n".utf8))
        check("en-têtes MIME et boundary ignorés", mp == "Suite des photos du chantier", mp)
        check("une phrase avec = reste", MailParsing.snippet(Data("Prix = 1500 euros".utf8)) == "Prix = 1500 euros")
        check("extrait coupé", MailParsing.snippet(Data(String(repeating: "mot ", count: 100).utf8), limit: 20).hasSuffix("…"))

        print("Réponses IMAP")
        check("ensemble IMAP", MailParsing.expandSet("9:11,14") == [9, 10, 11, 14])
        check("COPYUID", MailParsing.copyUID("A5 OK [COPYUID 1700 3,5:6 20:22] Moved") == [3: 20, 5: 21, 6: 22])
        check("COPYUID dans une réponse non étiquetée", MailParsing.copyUID("* OK [COPYUID 9 12 40] done") == [12: 40])
        check("séparateur /", MailParsing.delimiter("* LIST (\\Noselect) \"/\" \"\"") == "/")
        check("séparateur .", MailParsing.delimiter("* LIST (\\Noselect) \".\" \"\"") == ".")
        check("date IMAP", MailParsing.internalDate("05-Oct-2026 09:12:00 +0200") != nil)
        check("guillemets échappés", MailParsing.quote("a\"b\\c") == "\"a\\\"b\\\\c\"")

        print("Premier tri")
        check("facture", MailParsing.guess(mail("compta@ovh.com", "Votre facture d’octobre")) == .factures)
        check("newsletter", MailParsing.guess(mail("news@site.fr", "Les nouveautés", list: true)) == .newsletters)
        check("promo avant newsletter", MailParsing.guess(mail("shop@x.fr", "Soldes : -50% sur tout", list: true)) == .promotions)
        check("notification GitHub", MailParsing.guess(mail("notifications@github.com", "[oli] PR #12")) == .notifications)
        check("un humain : à traiter", MailParsing.guess(mail("jean@plomberie-durand.fr", "Question sur le site")) == .important)
        check("URSSAF", MailParsing.guess(mail("contact@urssaf.fr", "Votre échéance")) == .administratif)

        print("Réponse de Claude")
        let c = MailParsing.parseClassification("Voici :\n[{\"uid\": 12, \"cat\": \"factures\", \"resume\": \"Facture OVH\"}, {\"uid\": \"13\", \"cat\": \"IMPORTANT\"}, {\"uid\": 14, \"cat\": \"inconnue\"}]")
        check("deux classés, l'inconnu ignoré", c.count == 2, "\(c)")
        check("catégorie et résumé", c[12]?.0 == .factures && c[12]?.1 == "Facture OVH")
        check("uid en texte, catégorie en majuscules", c[13]?.0 == .important)
        check("pas de JSON : rien", MailParsing.parseClassification("Désolé").isEmpty)

        if failures > 0 { print("\(failures) échec(s)"); exit(1) }
        print("Mails : tout passe")
    }
}
