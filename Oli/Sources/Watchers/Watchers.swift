import SwiftUI

// MARK: - Veilleurs
// Each watcher refreshes one source on a timer (no work while there is nothing to watch) and tells
// Oli when something deserves attention. All of them run on the main actor and hop off for network.

@MainActor
final class Watchers {
    static let shared = Watchers()
    private var timers: [Timer] = []
    private init() {}

    func start() {
        every(300, first: 3) { EspaceWatcher.shared.refresh() }
        every(600, first: 15) { SitesWatcher.shared.refresh() }
        every(300, first: 6) { AgendaWatcher.shared.refresh() }
        every(60, first: 30) { AgendaWatcher.shared.checkSoon() }
        every(1800, first: 25) { InstagramWatcher.shared.refresh() }
        NotificationCenter.default.addObserver(forName: .oliSecretsChanged, object: nil, queue: .main) { note in
            let key = note.object as? String
            MainActor.assumeIsolated {
                switch key {
                case SecretKey.espaceToken.rawValue, SecretKey.espaceURL.rawValue: EspaceWatcher.shared.refresh()
                case SecretKey.agendaURL.rawValue: AgendaWatcher.shared.refresh()
                case SecretKey.instagramToken.rawValue, SecretKey.instagramAccount.rawValue: InstagramWatcher.shared.refresh()
                default: break
                }
            }
        }
    }

    private func every(_ seconds: TimeInterval, first: TimeInterval, _ work: @escaping @MainActor () -> Void) {
        let t = Timer(timeInterval: seconds, repeats: true) { _ in MainActor.assumeIsolated { work() } }
        t.tolerance = seconds * 0.1
        RunLoop.main.add(t, forMode: .common)
        timers.append(t)
        DispatchQueue.main.asyncAfter(deadline: .now() + first) { work() }
    }
}

// MARK: - Espace client

@MainActor
final class EspaceWatcher {
    static let shared = EspaceWatcher()
    private var known: Set<String>? = nil
    private var announced: Set<String> = []
    private var model: OliModel { .shared }

    func refresh() {
        guard let token = Secrets.shared[.espaceToken] else { model.projects = []; return }
        let base = model.espaceBase
        Task {
            let result = await EspaceAPI.fetch(token: token, base: base)
            switch result {
            case .ok(let projects): self.apply(projects)
            case .failed(let why): self.model.projectsError = why
            }
        }
    }

    private func apply(_ projects: [EspaceProject]) {
        model.projects = projects
        model.projectsSynced = Date()
        model.projectsError = nil
        var news: [String] = []
        for p in projects where !p.isDone {
            if let d = p.daysLeft, d <= 3 {
                let key = "due-\(p.id)-\(p.dueAt ?? "")-\(max(d, -1))"
                if announced.insert(key).inserted {
                    news.append(d < 0 ? "\(p.name) est en retard" : d == 0 ? "\(p.name) : mise en ligne aujourd’hui" : "\(p.name) : mise en ligne dans \(d) j")
                }
            }
            if let k = known, !k.contains(p.id) { news.append("Nouveau projet : \(p.name)") }
        }
        known = Set(projects.map(\.id))
        if let first = news.first {
            Chimes.shared.play(.attention)
            model.say(first, tint: Palette.tomate)
        }
        SitesWatcher.shared.refreshIfNewTargets()
    }
}

// MARK: - Sites clients

@MainActor
final class SitesWatcher {
    static let shared = SitesWatcher()
    private var running = false
    private var auditing = false
    private var lastTargets: Set<String> = []
    private var model: OliModel { .shared }
    /// Problems already announced, numbers stripped (UserDefaults, survives a relaunch).
    private var announced = Set(UserDefaults.standard.stringArray(forKey: "sitesAnnounced") ?? []) {
        didSet { UserDefaults.standard.set(Array(announced), forKey: "sitesAnnounced") }
    }
    private var panicWork: DispatchWorkItem?

    func refreshIfNewTargets() {
        if Set(model.siteTargets.map(\.url)) != lastTargets { refresh() }
    }

    func refresh() {
        let targets = model.siteTargets
        lastTargets = Set(targets.map(\.url))
        guard !targets.isEmpty else { model.sites = []; model.alarm = false; return }
        guard !running else { return }
        running = true
        let previous = Dictionary(uniqueKeysWithValues: model.sites.map { ($0.id, $0) })
        Task {
            let checks = await SiteMonitor.runPass(targets: targets, previous: previous)
            self.running = false
            self.apply(checks, previous: previous)
        }
    }

    private func apply(_ checks: [SiteCheck], previous: [String: SiteCheck]) {
        model.sites = checks
        model.sitesSynced = Date()
        let downNow = checks.filter { $0.status == .down }
        let wentDown = downNow.filter { previous[$0.id]?.status != .down }
        let cameBack = checks.filter { $0.status != .down && previous[$0.id]?.status == .down }
        model.alarm = !downNow.isEmpty

        if let d = wentDown.first {
            for s in wentDown where !s.url.contains(".invalid") { Self.logIncident(s.name) }
            raiseAlarm("\(d.name) est en panne · \(d.reason ?? "injoignable")")
        } else if let b = cameBack.first {
            Chimes.shared.play(.back)
            model.celebrate()
            model.say("\(b.name) est de nouveau en ligne", tint: Palette.menthe)
        }
        audit()
    }

    /// Outage: loud alarm, Oli red and panicking, notch open on the sites.
    func raiseAlarm(_ text: String) {
        model.alarm = true
        model.panic = true
        Chimes.shared.play(.alarm)
        model.say(text, tint: Palette.alerte, seconds: 20)
        model.open(.sites)
        panicWork?.cancel()
        let w = DispatchWorkItem { OliModel.shared.panic = false }
        panicWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: w)
    }

    /// Daily / weekly checks, one site at a time.
    func audit(force url: String? = nil) {
        guard !auditing else { return }
        let due = model.sites.filter { c in
            if let url { return c.url == url }
            guard c.status == .ok || c.status == .warning else { return false }
            let a = model.siteAudits[c.url]
            return (a?.dailyDue ?? true) || (a?.weeklyDue ?? true)
        }
        guard !due.isEmpty else { return }
        auditing = true
        let key = Secrets.shared[.pagespeed]
        Task {
            var fresh: [String] = []
            for c in due {
                let a = await SiteAuditor.run(url: c.url, previous: self.model.siteAudits[c.url], pagespeedKey: key, force: url != nil)
                self.model.siteAudits[c.url] = a
                fresh += self.newIssues(c, a)
            }
            self.auditing = false
            if let first = fresh.first, !self.model.alarm {
                Chimes.shared.play(.attention)
                self.model.say(first, tint: Palette.beurre)
            }
        }
    }

    private func newIssues(_ c: SiteCheck, _ a: SiteAudit) -> [String] {
        let key = { (i: String) in c.url + "|" + i.replacingOccurrences(of: "[0-9]+", with: "#", options: .regularExpression) }
        let current = Set(a.issues.map(key))
        announced = announced.filter { !$0.hasPrefix(c.url + "|") || current.contains($0) }
        return a.issues.filter { announced.insert(key($0)).inserted }.map { "\(c.name) : \($0)" }
    }

    // Incident log for the Friday recap (14 days)
    static func logIncident(_ name: String) {
        let cutoff = Date().addingTimeInterval(-14 * 86400).timeIntervalSince1970
        var list = (UserDefaults.standard.stringArray(forKey: "sitesIncidents") ?? [])
            .filter { (Double($0.split(separator: "|").first ?? "") ?? 0) >= cutoff }
        list.append("\(Int(Date().timeIntervalSince1970))|\(name)")
        UserDefaults.standard.set(list, forKey: "sitesIncidents")
    }

    static func incidents(since: Date) -> [BriefingFacts.Incident] {
        (UserDefaults.standard.stringArray(forKey: "sitesIncidents") ?? []).compactMap { raw in
            let p = raw.split(separator: "|", maxSplits: 1).map(String.init)
            guard p.count == 2, let ts = Double(p[0]) else { return nil }
            let at = Date(timeIntervalSince1970: ts)
            return at >= since ? BriefingFacts.Incident(name: p[1], at: at) : nil
        }
    }
}

// MARK: - Agenda

@MainActor
final class AgendaWatcher {
    static let shared = AgendaWatcher()
    private var announced: Set<String> = []
    private var model: OliModel { .shared }

    /// Where a click goes: agenda.oculot.studio, or Google Agenda when the feed comes from Google.
    static var calendarURL: URL {
        URL(string: (Secrets.shared[.agendaURL] ?? "").contains("google.com") ? "https://calendar.google.com" : "https://agenda.oculot.studio")!
    }

    func refresh() {
        guard let raw = Secrets.shared[.agendaURL] else { model.agenda = []; return }
        let fixed = raw.hasPrefix("webcal://") ? "https://" + raw.dropFirst("webcal://".count) : Substring(raw)
        guard let url = URL(string: String(fixed)), ["https", "http"].contains(url.scheme?.lowercased() ?? "") else {
            model.agendaError = "le lien doit commencer par https:// ou webcal://"
            return
        }
        Task {
            var req = URLRequest(url: url, timeoutInterval: 20)
            req.cachePolicy = .reloadIgnoringLocalCacheData
            guard let (data, resp) = try? await URLSession.shared.data(for: req) else {
                self.model.agendaError = "agenda injoignable"; return
            }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200, let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
                  text.contains("BEGIN:VCALENDAR") else {
                self.model.agendaError = code == 403 || code == 404 ? "lien refusé : redemande un lien de calendrier" : "réponse \(code)"
                return
            }
            self.model.agenda = AgendaICS.parse(text)
            self.model.agendaSynced = Date()
            self.model.agendaError = nil
            self.checkSoon()
        }
    }

    /// Ten minutes before an appointment, once.
    func checkSoon() {
        let now = Date()
        guard let e = model.agenda.first(where: { !$0.isAllDay && $0.start > now && $0.start.timeIntervalSince(now) <= 600 }),
              announced.insert(e.id).inserted else { return }
        Chimes.shared.play(.attention)
        model.say("Dans \(max(1, e.minutesUntilStart(from: now))) min · \(e.title)", tint: Palette.ciel, seconds: 30)
    }
}

// MARK: - Instagram

@MainActor
final class InstagramWatcher {
    static let shared = InstagramWatcher()
    private var model: OliModel { .shared }
    private var announced = Set(UserDefaults.standard.stringArray(forKey: "instagramAnnounced") ?? []) {
        didSet { UserDefaults.standard.set(Array(announced), forKey: "instagramAnnounced") }
    }

    func refresh() {
        guard let token = Secrets.shared[.instagramToken] else { model.instagram = nil; return }
        let account = Secrets.shared[.instagramAccount]
        Task {
            let snap = await SocialFetcher.fetch(token: token, accountId: account)
            self.model.instagram = snap
            let ids = snap.unanswered.map(\.id).sorted().joined(separator: ",")
            let keyed = snap.reminders().map { r in
                (r.contains("commentaire") ? "comments|" + ids : r.replacingOccurrences(of: "[0-9]+", with: "#", options: .regularExpression), r)
            }
            let fresh = keyed.filter { self.announced.insert($0.0).inserted }.map(\.1)
            self.announced = self.announced.filter { k in keyed.contains { $0.0 == k } }
            if let first = fresh.first {
                Chimes.shared.play(.attention)
                self.model.say("Instagram : \(first)", tint: Palette.rose)
            }
        }
    }
}
