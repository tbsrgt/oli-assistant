import Foundation
import Security

// MARK: - Surveillance des sites clients (moteur)
// Pure model + probe logic, no dependency on AppState so that scripts/test-sites.swift
// can compile it alone with swiftc. SitesPoller drives it inside the app.

enum SiteStatus: String, Sendable {
    case ok, warning, down, unknown

    var hex: String {
        switch self {
        case .ok:      return "#22C55E"
        case .warning: return "#FFD65C"
        case .down:    return "#F4505E"
        case .unknown: return "#8E939C"
        }
    }
    var label: String {
        switch self {
        case .ok:      return "en ligne"
        case .warning: return "à surveiller"
        case .down:    return "en panne"
        case .unknown: return "pas encore vérifié"
        }
    }
    /// Sort weight: down first, then warning, ok, unknown.
    var order: Int {
        switch self {
        case .down: return 0
        case .warning: return 1
        case .ok: return 2
        case .unknown: return 3
        }
    }
}

/// A site to watch: the label shown in the notch + its URL.
struct SiteTarget: Hashable, Sendable {
    let name: String
    let url: String
}

/// Result of one probe (the raw facts, before the status rules).
struct SiteProbeResult: Sendable {
    var httpCode: Int? = nil
    var latencyMs: Int = 0
    var finalURL: String? = nil
    var tlsExpiresAt: Date? = nil
    var error: String? = nil
    var offline: Bool = false     // the Mac itself has no network: don't count it against the site

    /// Timeout, network error or 5xx.
    var isFailure: Bool {
        if error != nil { return true }
        if let c = httpCode, c >= 500 { return true }
        return false
    }
}

struct SiteCheck: Identifiable, Sendable, Equatable {
    static let tlsWarningDays = 14
    static let slowMs = 4000

    var id: String { url }
    let name: String
    let url: String
    var status: SiteStatus = .unknown
    var httpCode: Int? = nil
    var latencyMs: Int? = nil
    var finalURL: String? = nil
    var tlsExpiresAt: Date? = nil
    var lastCheckedAt: Date? = nil
    var lastError: String? = nil
    var consecutiveFailures: Int = 0

    /// "oculot.studio" for "https://www.oculot.studio/fr/" (www stripped).
    var shortHost: String {
        guard let h = URL(string: url)?.host else { return url }
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }
    var latencyLabel: String {
        guard let ms = latencyMs else { return "—" }
        if ms >= 1000 { return String(format: "%.1f s", Double(ms) / 1000) }
        return "\(ms) ms"
    }
    /// Whole days until the certificate expires (negative once expired).
    var tlsDaysLeft: Int? {
        guard let d = tlsExpiresAt else { return nil }
        return Int(floor(d.timeIntervalSinceNow / 86400))
    }
    var tlsLabel: String {
        guard let d = tlsDaysLeft else { return "certificat inconnu" }
        if d < 0 { return "certificat expiré depuis \(-d) j" }
        if d == 0 { return "certificat expire aujourd’hui" }
        return "certificat expire dans \(d) j"
    }
    var httpLabel: String { httpCode.map { "HTTP \($0)" } ?? "pas de réponse" }

    /// Why the site is not plainly ok (shown instead of the latency in the list).
    var reason: String? {
        switch status {
        case .ok, .unknown:
            return nil
        case .down:
            if let e = lastError { return e }
            if let c = httpCode, c >= 500 { return "HTTP \(c)" }
            return "injoignable"
        case .warning:
            if let c = httpCode, (400..<500).contains(c), c != 401, c != 403 { return "HTTP \(c)" }
            if let ms = latencyMs, ms > Self.slowMs { return "lent · \(latencyLabel)" }
            if let d = tlsDaysLeft, d < Self.tlsWarningDays { return tlsLabel }
            return lastError ?? "à surveiller"
        }
    }

    /// Applies the status rules to a probe result, remembering the previous check.
    /// A site is down after 2 consecutive failures; a single failure keeps the previous status.
    static func evaluate(previous: SiteCheck?, target: SiteTarget, result: SiteProbeResult, now: Date = Date()) -> SiteCheck {
        var c = previous ?? SiteCheck(name: target.name, url: target.url)
        c = SiteCheck(name: target.name, url: target.url, status: c.status, httpCode: c.httpCode, latencyMs: c.latencyMs,
                      finalURL: c.finalURL, tlsExpiresAt: c.tlsExpiresAt, lastCheckedAt: c.lastCheckedAt,
                      lastError: c.lastError, consecutiveFailures: c.consecutiveFailures)
        if result.offline { return c }      // no network on our side: leave everything as is
        c.lastCheckedAt = now
        c.httpCode = result.httpCode
        c.latencyMs = result.latencyMs
        c.finalURL = result.finalURL
        if let tls = result.tlsExpiresAt { c.tlsExpiresAt = tls }

        if result.isFailure {
            c.consecutiveFailures += 1
            c.lastError = result.error ?? result.httpCode.map { "HTTP \($0)" }
            if c.consecutiveFailures >= 2 { c.status = .down }
            return c
        }

        c.consecutiveFailures = 0
        c.lastError = nil
        let code = result.httpCode ?? 0
        let badCode = (400..<500).contains(code) && code != 401 && code != 403
        let slow = result.latencyMs > Self.slowMs
        let tlsSoon = c.tlsDaysLeft.map { $0 < Self.tlsWarningDays } ?? false
        c.status = (badCode || slow || tlsSoon) ? .warning : .ok
        return c
    }
}

// MARK: - Probe (GET + TLS expiry via URLSession delegate)

final class SiteProber: NSObject, URLSessionDelegate, @unchecked Sendable {
    static let userAgent = "Oli/1.0 (Oculot)"
    static let timeout: TimeInterval = 15

    private let lock = NSLock()
    private var _tlsExpiresAt: Date? = nil
    var tlsExpiresAt: Date? { lock.lock(); defer { lock.unlock() }; return _tlsExpiresAt }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust,
           let date = Self.notAfter(trust) {
            lock.lock(); _tlsExpiresAt = date; lock.unlock()
        }
        completionHandler(.performDefaultHandling, nil)
    }

    /// "notAfter" of the leaf certificate (macOS: SecCertificateCopyValues).
    static func notAfter(_ trust: SecTrust) -> Date? {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = chain.first else { return nil }
        let keys = [kSecOIDX509V1ValidityNotAfter] as CFArray
        guard let values = SecCertificateCopyValues(leaf, keys, nil) as? [CFString: Any],
              let entry = values[kSecOIDX509V1ValidityNotAfter] as? [CFString: Any],
              let num = entry[kSecPropertyKeyValue] as? NSNumber else { return nil }
        return Date(timeIntervalSinceReferenceDate: num.doubleValue)
    }

    /// One GET with redirects, 15 s timeout, Oli user agent.
    static func probe(_ urlString: String) async -> SiteProbeResult {
        guard let url = URL(string: urlString), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host != nil else {
            return SiteProbeResult(error: "URL invalide")
        }
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = timeout
        cfg.timeoutIntervalForResource = timeout
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.httpAdditionalHeaders = ["User-Agent": userAgent, "Accept": "text/html,*/*;q=0.8"]
        let prober = SiteProber()
        let session = URLSession(configuration: cfg, delegate: prober, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = "GET"
        let start = DispatchTime.now().uptimeNanoseconds
        var result = SiteProbeResult()
        do {
            let (_, response) = try await session.data(for: req)
            result.latencyMs = Int((DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
            let http = response as? HTTPURLResponse
            result.httpCode = http?.statusCode
            result.finalURL = response.url?.absoluteString
        } catch {
            result.latencyMs = Int((DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
            let (text, offline) = describe(error)
            result.error = text
            result.offline = offline
        }
        result.tlsExpiresAt = prober.tlsExpiresAt
        return result
    }

    /// French one-liner for a transport error, plus whether it is our own connectivity.
    static func describe(_ error: Error) -> (String, Bool) {
        let e = error as NSError
        guard e.domain == NSURLErrorDomain else { return (e.localizedDescription, false) }
        switch URLError.Code(rawValue: e.code) {
        case .timedOut:                       return ("délai dépassé (\(Int(timeout)) s)", false)
        case .cannotFindHost, .dnsLookupFailed: return ("domaine introuvable", false)
        case .cannotConnectToHost:            return ("connexion refusée", false)
        case .networkConnectionLost:          return ("connexion perdue", false)
        case .notConnectedToInternet, .internationalRoamingOff, .dataNotAllowed:
            return ("pas de connexion Internet", true)
        case .secureConnectionFailed:         return ("échec TLS", false)
        case .serverCertificateHasBadDate:    return ("certificat expiré", false)
        case .serverCertificateUntrusted, .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .clientCertificateRejected:
            return ("certificat invalide", false)
        case .httpTooManyRedirects:           return ("trop de redirections", false)
        default:                              return (e.localizedDescription, false)
        }
    }
}

// MARK: - One pass over every site, 4 at a time

enum SiteMonitor {
    static let maxConcurrent = 4

    /// Builds the watch list: every non-empty espace `liveUrl` (client name as label) + manual URLs.
    static func targets(espace: [(name: String, liveUrl: String)], manual: String) -> [SiteTarget] {
        var seen = Set<String>()
        var out: [SiteTarget] = []
        for c in espace {
            let u = normalize(c.liveUrl)
            guard !u.isEmpty, seen.insert(u).inserted else { continue }
            out.append(SiteTarget(name: c.name.isEmpty ? host(u) : c.name, url: u))
        }
        for line in manual.split(whereSeparator: \.isNewline) {
            let raw = line.trimmingCharacters(in: .whitespaces)
            guard !raw.isEmpty, !raw.hasPrefix("#") else { continue }
            let u = normalize(raw)
            guard !u.isEmpty, seen.insert(u).inserted else { continue }
            out.append(SiteTarget(name: host(u), url: u))
        }
        return out
    }

    /// Trims, adds https:// when the scheme is missing.
    static func normalize(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return "" }
        if s.lowercased().hasPrefix("http://") || s.lowercased().hasPrefix("https://") { return s }
        return "https://" + s
    }
    static func host(_ url: String) -> String {
        guard let h = URL(string: url)?.host else { return url }
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }

    /// Probes every target (max 4 in flight) and merges with the previous checks.
    static func runPass(targets: [SiteTarget], previous: [String: SiteCheck]) async -> [SiteCheck] {
        var results: [String: SiteProbeResult] = [:]
        await withTaskGroup(of: (String, SiteProbeResult).self) { group in
            var pending = targets.makeIterator()
            var inFlight = 0
            func launch() {
                while inFlight < maxConcurrent, let t = pending.next() {
                    inFlight += 1
                    group.addTask { (t.url, await SiteProber.probe(t.url)) }
                }
            }
            launch()
            for await (url, r) in group {
                inFlight -= 1
                results[url] = r
                launch()
            }
        }
        // Offline on our side (every probe says so): keep the previous checks untouched.
        let allOffline = !results.isEmpty && results.values.allSatisfy(\.offline)
        let now = Date()
        return targets.map { t in
            let r = results[t.url] ?? SiteProbeResult(error: "non vérifié")
            let adjusted = allOffline ? SiteProbeResult(offline: true) : r
            return SiteCheck.evaluate(previous: previous[t.url], target: t, result: adjusted, now: now)
        }
    }
}
