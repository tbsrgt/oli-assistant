// Vérifie quelques URLs réelles avec le moteur de surveillance des sites (SiteCheck.swift).
// Compilation seule :
//   swiftc -parse-as-library OliAssistant/Sources/App/SiteCheck.swift scripts/test-sites.swift -o /tmp/test-sites && /tmp/test-sites
// ou : scripts/test-sites.sh [url …]

import Foundation

@main
struct TestSites {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        let urls = args.isEmpty
            ? ["https://oculot.studio", "https://espace.oculot.studio", "https://example.invalid"]
            : args
        let manual = urls.joined(separator: "\n")
        let targets = SiteMonitor.targets(espace: [], manual: manual)
        print("Surveillance de \(targets.count) site(s), \(SiteMonitor.maxConcurrent) à la fois, délai \(Int(SiteProber.timeout)) s\n")

        // Deux passes : la première laisse un site injoignable en « unknown » (1 échec),
        // la seconde le bascule en « down » (2 échecs consécutifs).
        var previous: [String: SiteCheck] = [:]
        var checks: [SiteCheck] = []
        for pass in 1...2 {
            let t0 = Date()
            checks = await SiteMonitor.runPass(targets: targets, previous: previous)
            previous = Dictionary(uniqueKeysWithValues: checks.map { ($0.id, $0) })
            print("Passe \(pass) · \(String(format: "%.1f", Date().timeIntervalSince(t0))) s")
            for c in checks.sorted(by: { $0.status.order < $1.status.order }) {
                let dot: String
                switch c.status {
                case .ok: dot = "●"; case .warning: dot = "◐"; case .down: dot = "○"; case .unknown: dot = "·"
                }
                var parts = ["\(dot) \(c.shortHost.padding(toLength: 26, withPad: " ", startingAt: 0))", c.status.label.padding(toLength: 18, withPad: " ", startingAt: 0)]
                parts.append(c.httpLabel)
                parts.append(c.latencyLabel)
                parts.append(c.tlsLabel)
                if let f = c.finalURL, f != c.url { parts.append("→ \(f)") }
                if let r = c.reason { parts.append("⚠︎ \(r)") } else if let e = c.lastError { parts.append("(1er échec : \(e))") }
                print("  " + parts.joined(separator: "  "))
            }
            print("")
        }

        // Garde-fous : les règles du moteur.
        var failures = 0
        func expect(_ cond: Bool, _ msg: String) {
            print((cond ? "  ✓ " : "  ✗ ") + msg)
            if !cond { failures += 1 }
        }
        print("Règles")
        if let invalid = checks.first(where: { $0.url.contains("example.invalid") }) {
            expect(invalid.status == .down, "example.invalid est « down » après 2 échecs (\(invalid.lastError ?? "?"))")
            expect(invalid.consecutiveFailures == 2, "2 échecs consécutifs comptés")
        }
        for c in checks where !c.url.contains("example.invalid") {
            expect(c.status == .ok || c.status == .warning, "\(c.shortHost) répond (\(c.httpLabel), \(c.latencyLabel))")
            expect(c.tlsExpiresAt != nil, "\(c.shortHost) : date d’expiration du certificat lue (\(c.tlsLabel))")
        }
        let slow = SiteCheck.evaluate(previous: nil, target: SiteTarget(name: "x", url: "https://x.test"),
                                      result: SiteProbeResult(httpCode: 200, latencyMs: 4500))
        expect(slow.status == .warning && slow.reason == "lent · 4.5 s", "200 en 4,5 s → warning « lent »")
        let notFound = SiteCheck.evaluate(previous: nil, target: SiteTarget(name: "x", url: "https://x.test"),
                                          result: SiteProbeResult(httpCode: 404, latencyMs: 100))
        expect(notFound.status == .warning && notFound.reason == "HTTP 404", "404 → warning « HTTP 404 »")
        let protected = SiteCheck.evaluate(previous: nil, target: SiteTarget(name: "x", url: "https://x.test"),
                                           result: SiteProbeResult(httpCode: 401, latencyMs: 100))
        expect(protected.status == .ok, "401 (preview protégée) → ok")
        let soon = SiteCheck.evaluate(previous: nil, target: SiteTarget(name: "x", url: "https://x.test"),
                                      result: SiteProbeResult(httpCode: 200, latencyMs: 100, tlsExpiresAt: Date().addingTimeInterval(5 * 86400)))
        expect(soon.status == .warning && soon.reason?.hasPrefix("certificat expire dans") == true, "certificat < 14 j → warning (\(soon.reason ?? "?"))")
        let one = SiteCheck.evaluate(previous: slow, target: SiteTarget(name: "x", url: "https://x.test"),
                                     result: SiteProbeResult(httpCode: 503, latencyMs: 100))
        expect(one.status == .warning && one.consecutiveFailures == 1, "1er 503 garde le statut précédent")
        let two = SiteCheck.evaluate(previous: one, target: SiteTarget(name: "x", url: "https://x.test"),
                                     result: SiteProbeResult(httpCode: 503, latencyMs: 100))
        expect(two.status == .down && two.reason == "HTTP 503", "2e 503 → down « HTTP 503 »")
        let back = SiteCheck.evaluate(previous: two, target: SiteTarget(name: "x", url: "https://x.test"),
                                      result: SiteProbeResult(httpCode: 200, latencyMs: 100))
        expect(back.status == .ok && back.consecutiveFailures == 0, "retour 200 → ok, compteur à zéro")
        let offline = SiteCheck.evaluate(previous: back, target: SiteTarget(name: "x", url: "https://x.test"),
                                         result: SiteProbeResult(error: "pas de connexion Internet", offline: true))
        expect(offline.status == .ok && offline.consecutiveFailures == 0, "Mac hors ligne → rien ne change")
        let list = SiteMonitor.targets(espace: [("Client A", "https://a.test/"), ("Client B", ""), ("Client C", "https://a.test/")],
                                       manual: "b.test\n# commentaire\n\n https://a.test/ \nhttp://c.test")
        expect(list.map(\.url) == ["https://a.test/", "https://b.test", "http://c.test"] && list[0].name == "Client A" && list[1].name == "b.test",
               "liste : espace + manuelle, doublons et vides ignorés, https ajouté")


        print("\nContrôles quotidiens et hebdomadaires (analyse)")
        expect(SiteAuditParse.registrableDomain("www.espace.oculot.studio") == "oculot.studio", "domaine enregistrable : espace.oculot.studio → oculot.studio")
        expect(SiteAuditParse.registrableDomain("shop.example.co.uk") == "example.co.uk", "domaine enregistrable : .co.uk sur trois niveaux")
        expect(SiteAuditParse.registrableDomain("127.0.0.1") == nil && SiteAuditParse.registrableDomain("localhost") == nil, "IP et localhost ignorés")
        let rdap = #"{"events":[{"eventAction":"registration","eventDate":"2020-01-01T00:00:00Z"},{"eventAction":"expiration","eventDate":"2027-03-14T10:00:00Z"}]}"#
        let exp = SiteAuditParse.rdapExpiry(Data(rdap.utf8))
        expect(exp.map { Calendar(identifier: .gregorian).component(.year, from: $0) } == 2027, "RDAP : date d’expiration lue")
        expect(SiteAuditParse.rdapExpiry(Data(#"{"events":[]}"#.utf8)) == nil, "RDAP sans expiration → inconnue")
        let ps = #"{"lighthouseResult":{"categories":{"performance":{"score":0.87}}}}"#
        expect(SiteAuditParse.pagespeedScore(Data(ps.utf8)) == 87, "PageSpeed : score 0,87 → 87")
        expect(SiteAuditParse.robotsBlocksAll("User-agent: *\nDisallow: /\n"), "robots : Disallow: / pour * → bloque tout")
        expect(!SiteAuditParse.robotsBlocksAll("User-agent: *\nDisallow: /admin\nSitemap: https://x/sitemap.xml"), "robots : Disallow: /admin → ok")
        expect(!SiteAuditParse.robotsBlocksAll("User-agent: GPTBot\nDisallow: /\n\nUser-agent: *\nAllow: /"), "robots : blocage d’un seul robot → ok")
        expect(SiteAuditParse.robotsBlocksAll("User-agent: Googlebot\nUser-agent: *\nDisallow: / # tout\n"), "robots : groupe partagé avec * → bloque tout")
        expect(SiteAuditParse.sitemapCount("<?xml?><urlset><url><loc>a</loc></url><url><loc>b</loc></url></urlset>") == 2, "sitemap : 2 URL comptées")
        expect(SiteAuditParse.sitemapCount("<html>404</html>") == nil, "sitemap : page HTML → illisible")
        let html = #"<link href="/style.css"><a href="/contact">C</a><a href='https://www.x.test/a#top'>A</a><a href="https://autre.test/">E</a><a href="mailto:a@x.test">M</a><a href="/contact#form">C2</a><a href="tel:0600">T</a>"#
        let links = SiteAuditParse.internalLinks(html: html, base: URL(string: "https://x.test/")!)
        expect(links.map(\.path) == ["/contact", "/a"], "liens internes : externes, mailto, tel, css et doublons écartés (\(links.map(\.path)))")
        var audit = SiteAudit()
        expect(audit.issues.isEmpty && audit.dailyDue && audit.weeklyDue, "audit vide : aucun problème, contrôles à faire")
        audit.domainChecked = true; audit.domainExpiresAt = Date().addingTimeInterval(10 * 86400)
        audit.robotsOK = false; audit.brokenLinks = ["/x (404)", "/y (500)"]; audit.pagespeed = 92; audit.dailyAt = Date(); audit.weeklyAt = Date()
        expect(audit.issues.count == 3 && audit.issues[0].hasPrefix("domaine expire dans") && audit.issues.last == "2 liens cassés", "audit : domaine < 30 j, robots, liens cassés (\(audit.issues))")
        expect(!audit.dailyDue && !audit.weeklyDue, "audit récent : rien à refaire")
        expect(LocalRepoFinder.slug("https://github.com/TBSRGT/Oculot.git") == "tbsrgt/oculot" && LocalRepoFinder.slug("git@github.com:a/b") == "a/b", "dépôt : formes https et ssh reconnues")
        expect(LocalRepoFinder.remoteSlugs(gitConfig: "[remote \"origin\"]\n\turl = https://github.com/tbsrgt/oculot.git\n") == ["tbsrgt/oculot"], "dépôt : remote lu dans .git/config")
        let home = FileManager.default.homeDirectoryForCurrentUser
        let found = LocalRepoFinder.find(repo: "tbsrgt/oculot", roots: [home])
        expect(found != nil, "dépôt local de tbsrgt/oculot trouvé (\(found?.path ?? "aucun"))")

        let sub = await SiteAuditor.run(url: "https://espace.oculot.studio", previous: nil, pagespeedKey: nil)
        expect(sub.wwwApexOK == nil, "sous-domaine : pas de contrôle www / domaine nu (\(sub.wwwApexDetail ?? "ignoré"))")

        print("\nContrôles réels sur oculot.studio (PageSpeed peut prendre 30 s)")
        let real = await SiteAuditor.run(url: "https://oculot.studio", previous: nil, pagespeedKey: nil)
        print("  \(real.pagespeedLabel) \(real.pagespeedError.map { "(\($0))" } ?? "") · \(real.domainLabel) · \(real.wwwApexDetail ?? "www/apex ?")")
        print("  robots : \(real.robotsDetail ?? "?") · sitemap : \(real.sitemapCount.map { "\($0) URL" } ?? "absent") · \(real.linksChecked) liens vérifiés, \(real.brokenLinks.count) cassé(s) \(real.brokenLinks.prefix(3).joined(separator: ", "))")
        expect(real.domainChecked && real.domainDaysLeft != nil, "oculot.studio : expiration du domaine lue via RDAP")
        expect(real.wwwApexOK != nil, "oculot.studio : www/apex évalué")
        expect(real.robotsOK == true, "oculot.studio : robots.txt n’empêche pas l’indexation")
        expect(real.sitemapOK != nil && real.linksChecked > 0, "oculot.studio : sitemap et liens de l’accueil contrôlés")
        expect(real.pagespeed != nil || real.pagespeedError != nil, "oculot.studio : PageSpeed mesuré ou erreur expliquée")

        print(failures == 0 ? "\nOK" : "\n\(failures) échec(s)")
        exit(failures == 0 ? 0 : 1)
    }
}
