import AppKit

// MARK: - Sites clients Oculot
// Every 10 minutes (first pass 20 s after launch) probes every delivered site of the espace client
// (non-empty liveUrl) plus the manual list (UserDefaults "sitesManual"), 4 at a time.
// Fills AppState.siteChecks and raises the integration_sites pill when a site goes down,
// a certificate is about to expire, or a site comes back.

@MainActor
final class SitesPoller {
    static let shared = SitesPoller()
    static let pillId = "integration_sites"
    static let interval: TimeInterval = 600

    private var timer: Timer?
    private var running = false
    private var alertedTLS: Set<String> = []     // "url|notAfter" already announced
    private var auditing = false
    /// "url|issue" already announced (UserDefaults "sitesAlertedIssues"), so a relaunch does not repeat them.
    private var alertedIssues: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "sitesAlertedIssues") ?? []) {
        didSet { UserDefaults.standard.set(Array(alertedIssues), forKey: "sitesAlertedIssues") }
    }

    private init() {}

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: Self.interval, repeats: true) { _ in
            Task { @MainActor in SitesPoller.shared.checkNow() }
        }
        t.tolerance = 30
        RunLoop.main.add(t, forMode: .common)
        timer = t
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.checkNow() }
        #if DEBUG
        // Dev only: `scripts/sites-check-now.sh` posts this to run a pass without waiting 10 min.
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("studio.oculot.oli.sitesCheckNow"),
                                                            object: nil, queue: .main) { _ in
            Task { @MainActor in SitesPoller.shared.checkNow() }
        }
        // Dev only: `scripts/sites-demo.sh` replays a site going down through the real alert path.
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("studio.oculot.oli.sitesDemoDown"),
                                                            object: nil, queue: .main) { _ in
            Task { @MainActor in SitesPoller.shared.demoDown() }
        }
        #endif
    }

    /// Current watch list (espace live sites + manual list).
    static var targets: [SiteTarget] {
        let app = AppState.shared
        return SiteMonitor.targets(espace: app.espaceClients.map { ($0.name, $0.liveUrl) }, manual: app.sitesManual)
    }

    /// Runs a pass right away (Settings saved, « Revérifier » button, timer).
    func checkNow() {
        guard !running else { return }
        let targets = Self.targets
        let app = AppState.shared
        guard !targets.isEmpty else {
            app.siteChecks = []
            return
        }
        running = true
        let previous = Dictionary(uniqueKeysWithValues: app.siteChecks.map { ($0.id, $0) })
        Task { [weak self] in
            let checks = await SiteMonitor.runPass(targets: targets, previous: previous)
            self?.handle(checks, previous: previous)
        }
    }

    // MARK: - Alerts

    private func handle(_ checks: [SiteCheck], previous: [String: SiteCheck]) {
        running = false
        let app = AppState.shared
        app.siteChecks = checks
        app.sitesLastSync = Date()
        // Oli stays red as long as one site is down.
        app.sitesAlarm = checks.contains { $0.status == .down }

        var downs: [String] = []
        var warnings: [String] = []
        var recovered: [String] = []
        for c in checks {
            let before = previous[c.id]?.status ?? .unknown
            if c.status == .down && before != .down {
                downs.append("\(c.name) : \(c.reason ?? "injoignable")")
                if !c.url.contains(".invalid") { Self.logIncident(name: c.name) }   // demo / test sites stay out of the recap
            } else if c.status != .down && before == .down {
                recovered.append("\(c.name) : de nouveau en ligne")
            } else if c.status == .warning && before != .warning && before != .down {
                // 4xx or slow: announce the transition once; TLS has its own key below.
                if let d = c.tlsDaysLeft, d < SiteCheck.tlsWarningDays {
                    let key = "\(c.id)|\(Int(c.tlsExpiresAt?.timeIntervalSince1970 ?? 0))"
                    if alertedTLS.insert(key).inserted { warnings.append("\(c.name) : \(c.tlsLabel)") }
                } else {
                    warnings.append("\(c.name) : \(c.reason ?? "à surveiller")")
                }
            } else if let d = c.tlsDaysLeft, d < SiteCheck.tlsWarningDays, c.status != .down {
                let key = "\(c.id)|\(Int(c.tlsExpiresAt?.timeIntervalSince1970 ?? 0))"
                if alertedTLS.insert(key).inserted { warnings.append("\(c.name) : \(c.tlsLabel)") }
            }
        }

        defer { auditDue() }
        let state: BotState
        let steps: [String]
        let badge: PillBadge
        let sound: String
        if !downs.isEmpty {
            state = .error;    steps = downs;     badge = .error;    sound = "error"
            soundAlarm()
        } else if !warnings.isEmpty {
            state = .question; steps = warnings;  badge = .approval; sound = "question"
        } else if !recovered.isEmpty {
            state = .finished; steps = recovered; badge = .finished; sound = "finish"
        } else {
            return
        }
        raise(state: state, steps: steps, badge: badge, sound: sound)
    }

    #if DEBUG
    /// Pretends « Site de démo » was online and has just failed twice: same alert, list and detail as a real outage.
    func demoDown() {
        let app = AppState.shared
        let url = "https://demo.oculot.invalid"
        let up = SiteCheck(name: "Site de démo", url: url, status: .ok, httpCode: 200, latencyMs: 240,
                           tlsExpiresAt: Date().addingTimeInterval(60 * 86400), lastCheckedAt: Date().addingTimeInterval(-600))
        var previous = Dictionary(uniqueKeysWithValues: app.siteChecks.filter { $0.url != url }.map { ($0.id, $0) })
        var down = up
        down.status = .down; down.httpCode = 503; down.latencyMs = 15000
        down.lastError = "HTTP 503"; down.consecutiveFailures = 2; down.lastCheckedAt = Date()
        let checks = Array(previous.values) + [down]
        previous[url] = up
        running = true
        handle(checks, previous: previous)
    }
    #endif

    // MARK: - Incident log (Friday recap)

    /// Outages of the last 14 days, as "timestamp|name" (UserDefaults "sitesIncidents").
    static func logIncident(name: String, at: Date = Date()) {
        let ud = UserDefaults.standard
        let cutoff = at.addingTimeInterval(-14 * 86400).timeIntervalSince1970
        var list = (ud.stringArray(forKey: "sitesIncidents") ?? []).filter {
            (Double($0.split(separator: "|").first ?? "") ?? 0) >= cutoff
        }
        list.append("\(Int(at.timeIntervalSince1970))|\(name)")
        ud.set(list, forKey: "sitesIncidents")
    }

    static func incidents(since: Date) -> [BriefingFacts.Incident] {
        (UserDefaults.standard.stringArray(forKey: "sitesIncidents") ?? []).compactMap { raw in
            let parts = raw.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2, let ts = Double(parts[0]) else { return nil }
            let at = Date(timeIntervalSince1970: ts)
            return at >= since ? BriefingFacts.Incident(name: parts[1], at: at) : nil
        }
    }

    // MARK: - « Corriger avec Claude Code »

    /// GitHub repo of the espace client whose live site is this URL ("owner/name"), if any.
    static func repo(for url: String) -> String? {
        let want = SiteMonitor.normalize(url)
        return AppState.shared.espaceClients
            .first { SiteMonitor.normalize($0.liveUrl) == want && !$0.repo.isEmpty }
            .flatMap { LocalRepoFinder.slug($0.repo) }
    }

    /// Opens Terminal with `claude` in the local clone of the site's repo, else the repo on GitHub.
    /// Returns a short French status for the detail view.
    @discardableResult
    static func openInClaudeCode(_ site: SiteCheck) -> String {
        guard let repo = repo(for: site.url) else { return "aucun dépôt GitHub relié dans l’espace client" }
        let home = FileManager.default.homeDirectoryForCurrentUser
        // A quote or backslash in the path would break the AppleScript string: fall back to GitHub.
        if let dir = LocalRepoFinder.find(repo: repo, roots: [home, home.appendingPathComponent("refontes")]),
           !dir.path.contains("\""), !dir.path.contains("\\") {
            let path = dir.path.replacingOccurrences(of: "'", with: "'\\''")
            let script = """
            tell application "Terminal"
                activate
                do script "cd '\(path)' && claude"
            end tell
            """
            var err: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&err)
            if err == nil { return "Claude Code ouvert dans \(dir.lastPathComponent)" }
        }
        if let gh = URL(string: "https://github.com/\(repo)") { NSWorkspace.shared.open(gh) }
        return "pas de clone local, dépôt ouvert sur GitHub"
    }

    // MARK: - Daily / weekly audits

    /// Audits, one site at a time, every reachable site whose daily or weekly checks are due.
    /// `force` re-runs everything for that one URL (« Revérifier »).
    func auditDue(force url: String? = nil) {
        guard !auditing else { return }
        let app = AppState.shared
        let targets: [SiteCheck] = app.siteChecks.filter { c in
            if let url { return c.url == url }
            guard c.status == .ok || c.status == .warning else { return false }
            let a = app.siteAudits[c.url]
            return a?.dailyDue ?? true || a?.weeklyDue ?? true
        }
        guard !targets.isEmpty else { return }
        auditing = true
        let key = KeychainStore.shared.get("pagespeed-api-key")
        Task { @MainActor [weak self] in
            var fresh: [String] = []
            for c in targets {
                let audit = await SiteAuditor.run(url: c.url, previous: app.siteAudits[c.url], pagespeedKey: key, force: url != nil)
                app.siteAudits[c.url] = audit
                fresh += self?.newIssues(for: c, audit: audit) ?? []
            }
            self?.auditing = false
            guard !fresh.isEmpty else { return }
            // A site down already owns the pill: don't downgrade it to a warning.
            if let i = app.tasks.firstIndex(where: { $0.id == Self.pillId }), app.tasks[i].state == .error { return }
            self?.raise(state: .question, steps: fresh, badge: .approval, sound: "question")
        }
    }

    /// Issues of this site not announced yet; forgets the ones that went away so they can be announced again.
    private func newIssues(for c: SiteCheck, audit: SiteAudit) -> [String] {
        // Keys drop the numbers: « 17 liens cassés » then « 18 liens cassés », or a countdown in days,
        // is the same problem and is announced once.
        let key = { (issue: String) in "\(c.url)|\(Self.issueKey(issue))" }
        let current = Set(audit.issues.map(key))
        alertedIssues = alertedIssues.filter { !$0.hasPrefix(c.url + "|") || current.contains($0) }
        var out: [String] = []
        for issue in audit.issues where alertedIssues.insert(key(issue)).inserted {
            out.append("\(c.name) : \(issue)")
        }
        return out
    }

    /// An issue without its numbers (« domaine expire dans 29 j » → « domaine expire dans # j »).
    nonisolated static func issueKey(_ issue: String) -> String {
        issue.replacingOccurrences(of: "[0-9]+", with: "#", options: .regularExpression)
    }

    /// A site just went down: loud triple alarm, Oli panics for 20 s (he stays red while it is down).
    private func soundAlarm() {
        let app = AppState.shared
        SoundEngine.shared.playLoud("error", volume: 1.0, times: 3, gap: 0.45)
        app.sitesPanic = true
        panicWork?.cancel()
        let work = DispatchWorkItem { AppState.shared.sitesPanic = false }
        panicWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: work)
    }
    private var panicWork: DispatchWorkItem?

    private func raise(state: BotState, steps: [String], badge: PillBadge, sound: String) {
        let app = AppState.shared
        guard let idx = app.tasks.firstIndex(where: { $0.id == Self.pillId }) else {
            // Sites pill not in the island: an outage still opens Oli, on the Oculot home that lists it first.
            if state == .error {
                app.focusId = app.mainPillId
                NotificationCenter.default.post(name: .hookExpand, object: IslandView.overview)
            }
            return
        }
        app.tasks[idx].state = state
        app.tasks[idx].steps = steps
        if state == .error {
            // Outage: open the island on the sites pill so the problem is on screen right away.
            app.tasks[idx].pillBadge = nil
            app.focusId = Self.pillId
            NotificationCenter.default.post(name: .hookExpand, object: IslandView.overview)
        } else {
            if app.focusId != Self.pillId { app.tasks[idx].pillBadge = badge }
            SoundEngine.shared.play(sound)
            NotificationCenter.default.post(name: .hookReveal, object: nil)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
            guard let i = app.tasks.firstIndex(where: { $0.id == Self.pillId }) else { return }
            guard app.tasks[i].state == state else { return }
            app.tasks[i].state = .idle
            app.tasks[i].steps = []
            app.tasks[i].pillBadge = nil
        }
    }
}
