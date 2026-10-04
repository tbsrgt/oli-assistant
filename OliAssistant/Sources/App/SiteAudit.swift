import Foundation

// MARK: - Sites clients : contrôles quotidiens et hebdomadaires
// Pure parsing + network probes, no dependency on AppState so that scripts/test-sites.swift
// can compile it with SiteCheck.swift alone. SitesPoller schedules it.
//
// Daily  : PageSpeed Insights mobile score, domain expiry (RDAP), www/apex redirect.
// Weekly : robots.txt, sitemap.xml, broken internal links on the home page.
// Never submits a form, never sends anything but GET/HEAD.

struct SiteAudit: Codable, Sendable, Equatable {
    static let dailyInterval: TimeInterval = 86_400
    static let weeklyInterval: TimeInterval = 7 * 86_400
    static let domainWarningDays = 30
    static let pagespeedWarning = 50

    // Daily
    var dailyAt: Date? = nil
    var pagespeed: Int? = nil              // 0…100, nil = not measured (quota, error)
    var pagespeedError: String? = nil
    var domain: String? = nil
    var domainExpiresAt: Date? = nil
    var domainChecked: Bool = false        // RDAP answered (with or without an expiry date)
    var wwwApexOK: Bool? = nil
    var wwwApexDetail: String? = nil

    // Weekly
    var weeklyAt: Date? = nil
    var robotsOK: Bool? = nil
    var robotsDetail: String? = nil
    var sitemapOK: Bool? = nil
    var sitemapCount: Int? = nil
    var linksChecked: Int = 0
    var brokenLinks: [String] = []         // "/path (404)"

    var dailyDue: Bool { dailyAt.map { Date().timeIntervalSince($0) >= Self.dailyInterval } ?? true }
    var weeklyDue: Bool { weeklyAt.map { Date().timeIntervalSince($0) >= Self.weeklyInterval } ?? true }

    var domainDaysLeft: Int? {
        guard let d = domainExpiresAt else { return nil }
        return Int(floor(d.timeIntervalSinceNow / 86400))
    }
    var domainLabel: String {
        guard domainChecked else { return "domaine pas encore vérifié" }
        guard let d = domainDaysLeft else { return "expiration du domaine inconnue" }
        if d < 0 { return "domaine expiré depuis \(-d) j" }
        return "domaine expire dans \(d) j"
    }
    var pagespeedLabel: String {
        if let p = pagespeed { return "PageSpeed \(p)" }
        if dailyAt == nil { return "PageSpeed à venir" }
        return "PageSpeed indisponible"
    }

    /// Problems worth a warning, in French, most important first. Unknown values never warn.
    var issues: [String] {
        var out: [String] = []
        if let d = domainDaysLeft, d < Self.domainWarningDays { out.append(domainLabel) }
        if wwwApexOK == false { out.append(wwwApexDetail ?? "www et domaine nu ne mènent pas au même site") }
        if robotsOK == false { out.append(robotsDetail ?? "robots.txt bloque les moteurs") }
        if sitemapOK == false { out.append("sitemap.xml absent ou illisible") }
        if !brokenLinks.isEmpty { out.append(brokenLinks.count == 1 ? "1 lien cassé" : "\(brokenLinks.count) liens cassés") }
        if let p = pagespeed, p < Self.pagespeedWarning { out.append("PageSpeed mobile \(p)/100") }
        return out
    }
}

// MARK: - Pure helpers (tested in scripts/test-sites.swift)

enum SiteAuditParse {
    /// Second-level suffixes where the registrable domain has three labels.
    static let multiPartSuffixes: Set<String> = [
        "co.uk", "org.uk", "ac.uk", "gov.uk", "me.uk",
        "com.fr", "asso.fr", "nom.fr", "gouv.fr",
        "com.au", "net.au", "org.au", "co.nz", "co.jp", "com.br", "com.es", "co.za", "com.mx",
    ]

    /// "www.shop.example.co.uk" → "example.co.uk"; "espace.oculot.studio" → "oculot.studio".
    static func registrableDomain(_ host: String) -> String? {
        let labels = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")).split(separator: ".").map(String.init)
        guard labels.count >= 2 else { return nil }
        if labels.allSatisfy({ Int($0) != nil }) { return nil }            // IPv4
        let lastTwo = labels.suffix(2).joined(separator: ".")
        if multiPartSuffixes.contains(lastTwo) {
            guard labels.count >= 3 else { return nil }
            return labels.suffix(3).joined(separator: ".")
        }
        return lastTwo
    }

    /// Expiry date from an RDAP domain answer (event "expiration"), nil if absent.
    static func rdapExpiry(_ data: Data) -> Date? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let events = json["events"] as? [[String: Any]] else { return nil }
        for e in events where (e["eventAction"] as? String)?.lowercased() == "expiration" {
            if let s = e["eventDate"] as? String, let d = parseISODate(s) { return d }
        }
        return nil
    }

    static func parseISODate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withFullDate]
        return f.date(from: String(s.prefix(10)))
    }

    /// PageSpeed v5 answer → performance score 0…100.
    static func pagespeedScore(_ data: Data) -> Int? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let lh = json["lighthouseResult"] as? [String: Any],
              let cats = lh["categories"] as? [String: Any],
              let perf = cats["performance"] as? [String: Any],
              let score = perf["score"] as? NSNumber else { return nil }
        return Int((score.doubleValue * 100).rounded())
    }

    /// True when the group for `User-agent: *` contains `Disallow: /` (the whole site).
    static func robotsBlocksAll(_ text: String) -> Bool {
        var inStarGroup = false
        var lastWasAgent = false
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            let field = parts[0].lowercased(), value = parts[1]
            if field == "user-agent" {
                // Consecutive user-agent lines share one group.
                if !lastWasAgent { inStarGroup = false }
                if value == "*" { inStarGroup = true }
                lastWasAgent = true
                continue
            }
            lastWasAgent = false
            if inStarGroup && field == "disallow" && value == "/" { return true }
        }
        return false
    }

    /// Number of <loc> entries in a sitemap or sitemap index, nil if it does not look like one.
    static func sitemapCount(_ text: String) -> Int? {
        let lower = text.lowercased()
        guard lower.contains("<urlset") || lower.contains("<sitemapindex") else { return nil }
        return lower.components(separatedBy: "<loc>").count - 1
    }

    /// Internal links (same host, www-insensitive) found in href attributes, without fragments,
    /// deduplicated, in page order. Skips mailto:, tel:, javascript: and data:.
    static func internalLinks(html: String, base: URL, limit: Int = 40) -> [URL] {
        guard let baseHost = base.host?.lowercased() else { return [] }
        let bare = { (h: String) in h.hasPrefix("www.") ? String(h.dropFirst(4)) : h }
        var seen = Set<String>()
        var out: [URL] = []
        let pattern = #"href\s*=\s*["']([^"'#]*)(?:#[^"']*)?["']"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = html as NSString
        for m in re.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let href = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
            let low = href.lowercased()
            if href.isEmpty || low.hasPrefix("mailto:") || low.hasPrefix("tel:") || low.hasPrefix("javascript:") || low.hasPrefix("data:") { continue }
            guard let u = URL(string: href, relativeTo: base)?.absoluteURL,
                  let scheme = u.scheme?.lowercased(), scheme == "http" || scheme == "https",
                  let h = u.host?.lowercased(), bare(h) == bare(baseHost) else { continue }
            // Static assets are not pages; the stylesheet/icon links in <head> would only add noise.
            let ext = u.pathExtension.lowercased()
            if ["css", "js", "ico", "png", "jpg", "jpeg", "webp", "avif", "svg", "woff", "woff2", "xml", "json", "webmanifest"].contains(ext) { continue }
            if seen.insert(u.absoluteString).inserted { out.append(u) }
            if out.count >= limit { break }
        }
        return out
    }

    /// Host without "www.".
    static func bareHost(_ url: URL?) -> String? {
        guard let h = url?.host?.lowercased() else { return nil }
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }
}

// MARK: - Network

enum SiteAuditor {
    static let pagespeedTimeout: TimeInterval = 90

    private static func session(timeout: TimeInterval) -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = timeout
        cfg.timeoutIntervalForResource = timeout
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.httpAdditionalHeaders = ["User-Agent": SiteProber.userAgent]
        return URLSession(configuration: cfg)
    }

    private static func get(_ url: URL, timeout: TimeInterval = 15, method: String = "GET") async -> (Int?, Data?, URL?) {
        let s = session(timeout: timeout)
        defer { s.finishTasksAndInvalidate() }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = method
        guard let (data, resp) = try? await s.data(for: req) else { return (nil, nil, nil) }
        let http = resp as? HTTPURLResponse
        return (http?.statusCode, data, resp.url)
    }

    /// Runs whichever of the daily / weekly checks is due and returns the updated audit.
    static func run(url: String, previous: SiteAudit?, pagespeedKey: String?, force: Bool = false) async -> SiteAudit {
        var a = previous ?? SiteAudit()
        guard let base = URL(string: url), let host = base.host else { return a }
        if force || a.dailyDue { await daily(&a, base: base, host: host, key: pagespeedKey) }
        if force || a.weeklyDue { await weekly(&a, base: base) }
        return a
    }

    static func daily(_ a: inout SiteAudit, base: URL, host: String, key: String?) async {
        let domain = SiteAuditParse.registrableDomain(host)
        // www / bare domain only makes sense for a site on the domain itself, not on a subdomain like espace.
        let h = host.lowercased()
        let onApex = domain.map { h == $0 || h == "www." + $0 } ?? false
        async let ps = pagespeed(base, key: key)
        async let rdap = domainExpiry(domain)
        async let wa = wwwApex(onApex ? domain : nil, scheme: "https")
        let (score, psError) = await ps
        let (rdapOK, expiry) = await rdap
        let (waOK, waDetail) = await wa

        a.dailyAt = Date()
        // Quota or transient error: keep yesterday's score rather than blanking it.
        if let score { a.pagespeed = score; a.pagespeedError = nil } else { a.pagespeedError = psError }
        a.domain = domain
        if rdapOK { a.domainChecked = true; a.domainExpiresAt = expiry }
        a.wwwApexOK = waOK
        a.wwwApexDetail = waDetail
    }

    static func weekly(_ a: inout SiteAudit, base: URL) async {
        guard let root = URL(string: "/", relativeTo: base)?.absoluteURL else { return }
        async let robots = robotsCheck(root)
        async let sitemap = sitemapCheck(root)
        async let links = brokenLinks(base)
        let (rOK, rDetail) = await robots
        let (sOK, sCount) = await sitemap
        let (checked, broken) = await links
        a.weeklyAt = Date()
        a.robotsOK = rOK; a.robotsDetail = rDetail
        a.sitemapOK = sOK; a.sitemapCount = sCount
        if let checked { a.linksChecked = checked; a.brokenLinks = broken }
    }

    /// PageSpeed Insights v5, mobile, performance only. Returns (score, error text).
    static func pagespeed(_ url: URL, key: String?) async -> (Int?, String?) {
        var comps = URLComponents(string: "https://www.googleapis.com/pagespeedonline/v5/runPagespeed")!
        var q = [URLQueryItem(name: "url", value: url.absoluteString),
                 URLQueryItem(name: "strategy", value: "mobile"),
                 URLQueryItem(name: "category", value: "performance")]
        if let key, !key.isEmpty { q.append(URLQueryItem(name: "key", value: key)) }
        comps.queryItems = q
        guard let api = comps.url else { return (nil, "URL invalide") }
        let (code, data, _) = await get(api, timeout: pagespeedTimeout)
        guard let code else { return (nil, "PageSpeed injoignable") }
        if code == 429 { return (nil, "quota PageSpeed atteint, nouvel essai demain") }
        guard code == 200, let data, let score = SiteAuditParse.pagespeedScore(data) else { return (nil, "PageSpeed HTTP \(code)") }
        return (score, nil)
    }

    /// RDAP via rdap.org (follows to the registry). Returns (answered, expiry).
    static func domainExpiry(_ domain: String?) async -> (Bool, Date?) {
        guard let domain, let url = URL(string: "https://rdap.org/domain/\(domain)") else { return (false, nil) }
        let (code, data, _) = await get(url, timeout: 20)
        guard code == 200, let data else { return (false, nil) }
        return (true, SiteAuditParse.rdapExpiry(data))
    }

    /// www.<domain> and <domain> must both answer and land on the same host.
    static func wwwApex(_ domain: String?, scheme: String) async -> (Bool?, String?) {
        guard let domain,
              let apex = URL(string: "\(scheme)://\(domain)/"),
              let www = URL(string: "\(scheme)://www.\(domain)/") else { return (nil, nil) }
        async let a = get(apex)
        async let w = get(www)
        let (aCode, _, aFinal) = await a
        let (wCode, _, wFinal) = await w
        let aOK = aCode.map { $0 < 400 || $0 == 401 || $0 == 403 } ?? false
        let wOK = wCode.map { $0 < 400 || $0 == 401 || $0 == 403 } ?? false
        if !aOK && !wOK { return (nil, nil) }                    // the main probe already reports it
        if !aOK { return (false, "\(domain) sans www ne répond pas") }
        if !wOK { return (false, "www.\(domain) ne répond pas") }
        guard let ah = aFinal?.host?.lowercased(), let wh = wFinal?.host?.lowercased() else { return (nil, nil) }
        if ah != wh { return (false, "www et domaine nu restent séparés (\(wh) / \(ah))") }
        return (true, "www et \(domain) mènent à \(ah)")
    }

    static func robotsCheck(_ root: URL) async -> (Bool?, String?) {
        guard let url = URL(string: "robots.txt", relativeTo: root)?.absoluteURL else { return (nil, nil) }
        let (code, data, _) = await get(url)
        guard let code else { return (nil, nil) }
        if code == 404 { return (true, "pas de robots.txt (tout est indexable)") }
        guard code == 200, let data, let text = String(data: data, encoding: .utf8) else { return (nil, "robots.txt HTTP \(code)") }
        if SiteAuditParse.robotsBlocksAll(text) { return (false, "robots.txt bloque tout le site (Disallow: /)") }
        return (true, "robots.txt ok")
    }

    static func sitemapCheck(_ root: URL) async -> (Bool?, Int?) {
        guard let url = URL(string: "sitemap.xml", relativeTo: root)?.absoluteURL else { return (nil, nil) }
        let (code, data, _) = await get(url)
        guard let code else { return (nil, nil) }
        guard code == 200, let data, let text = String(data: data, encoding: .utf8),
              let n = SiteAuditParse.sitemapCount(text) else { return (false, nil) }
        return (true, n)
    }

    /// HEAD (then GET on 405/501) on up to 40 internal links of the home page, 4 at a time.
    /// Returns (links checked, ["/path (404)"]) or (nil, []) if the home page could not be read.
    static func brokenLinks(_ base: URL) async -> (Int?, [String]) {
        let (code, data, final) = await get(base)
        guard let code, code < 400, let data, let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return (nil, []) }
        let links = SiteAuditParse.internalLinks(html: html, base: final ?? base)
        var broken: [(Int, String)] = []
        await withTaskGroup(of: (Int, String, Int?).self) { group in
            var it = links.enumerated().makeIterator()
            var inFlight = 0
            func launch() {
                while inFlight < 4, let (i, u) = it.next() {
                    inFlight += 1
                    group.addTask {
                        var (c, _, _) = await get(u, method: "HEAD")
                        if c == 405 || c == 501 || c == nil { (c, _, _) = await get(u) }
                        return (i, u.path.isEmpty ? "/" : u.path, c)
                    }
                }
            }
            launch()
            for await (i, path, c) in group {
                inFlight -= 1
                if let c, c >= 400, c != 401, c != 403 { broken.append((i, "\(path) (\(c))")) }
                else if c == nil { broken.append((i, "\(path) (injoignable)")) }
                launch()
            }
        }
        return (links.count, broken.sorted { $0.0 < $1.0 }.map(\.1))
    }
}

// MARK: - « Corriger avec Claude Code » : local clone of a GitHub repo

enum LocalRepoFinder {
    /// "tbsrgt/oculot", "https://github.com/tbsrgt/oculot.git" → "tbsrgt/oculot".
    static func slug(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !s.isEmpty else { return nil }
        for p in ["https://github.com/", "http://github.com/", "git@github.com:", "ssh://git@github.com/", "github.com/"] where s.hasPrefix(p) {
            s = String(s.dropFirst(p.count))
        }
        if s.hasSuffix(".git") { s = String(s.dropLast(4)) }
        if s.hasSuffix("/") { s = String(s.dropLast()) }
        let parts = s.split(separator: "/")
        guard parts.count == 2 else { return nil }
        return parts.joined(separator: "/")
    }

    /// Slugs of the GitHub remotes declared in a .git/config text.
    static func remoteSlugs(gitConfig: String) -> [String] {
        gitConfig.split(whereSeparator: \.isNewline).compactMap { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("url"), let eq = t.firstIndex(of: "=") else { return nil }
            let value = t[t.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            guard value.lowercased().contains("github.com") else { return nil }
            return slug(value)
        }
    }

    /// First folder (top level of the given roots) whose .git/config points to the repo.
    static func find(repo: String, roots: [URL]) -> URL? {
        guard let want = slug(repo) else { return nil }
        let fm = FileManager.default
        for root in roots {
            guard let items = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { continue }
            for dir in items {
                let cfg = dir.appendingPathComponent(".git/config")
                guard let text = try? String(contentsOf: cfg, encoding: .utf8) else { continue }
                if remoteSlugs(gitConfig: text).contains(want) { return dir }
            }
        }
        return nil
    }
}
