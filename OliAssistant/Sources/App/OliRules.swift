import AppKit

// MARK: - Automatisations « Quand… alors… »
// L'utilisateur construit ses règles dans l'encoche (onglet ⚡) : un déclencheur, une action.
// Le moteur regarde l'état d'Oli toutes les 10 s. Chaque déclencheur donne une « signature »
// (nil = rien à signaler) ; la règle part quand la signature change vers une valeur nouvelle,
// donc une fois par panne, par déploiement raté, par jour… jamais en boucle.
// Aucune action n'envoie un mail ni n'accepte quoi que ce soit : montrer, ranger, ouvrir, lancer
// un raccourci Apple de l'utilisateur. Ranger le bureau déplace, ne supprime jamais.

enum OliTrigger: String, Codable, CaseIterable, Identifiable {
    case siteDown, deployFailed, buildBroken, prToReview, projectLate, meetingSoon, claudeFinished, claudeQuota, desktopFull, dailyAt
    var id: String { rawValue }

    var label: String {
        switch self {
        case .siteDown:       return "un site tombe en panne"
        case .deployFailed:   return "un déploiement Vercel échoue"
        case .buildBroken:    return "un build GitHub casse"
        case .prToReview:     return "une PR attend ma relecture"
        case .projectLate:    return "un projet passe en retard"
        case .meetingSoon:    return "un rendez-vous commence dans 10 min"
        case .claudeFinished: return "Claude Code a fini"
        case .claudeQuota:    return "le quota Claude dépasse"
        case .desktopFull:    return "mon bureau a plus de"
        case .dailyAt:        return "chaque jour à"
        }
    }

    var icon: String {
        switch self {
        case .siteDown:       return "exclamationmark.triangle.fill"
        case .deployFailed:   return "triangle.fill"
        case .buildBroken:    return "hammer.fill"
        case .prToReview:     return "arrow.triangle.pull"
        case .projectLate:    return "folder.fill"
        case .meetingSoon:    return "calendar"
        case .claudeFinished: return "checkmark.seal.fill"
        case .claudeQuota:    return "gauge.with.dots.needle.67percent"
        case .desktopFull:    return "menubar.dock.rectangle"
        case .dailyAt:        return "clock.fill"
        }
    }

    /// What the parameter is, when there is one.
    var param: (placeholder: String, unit: String, defaultValue: String)? {
        switch self {
        case .claudeQuota: return ("80", "%", "80")
        case .desktopFull: return ("20", "fichiers", "20")
        case .dailyAt:     return ("09:00", "", "09:00")
        default:           return nil
        }
    }
}

enum OliRuleAction: String, Codable, CaseIterable, Identifiable {
    case bubble, notification, tidyDesktop, checkSites, refreshAll, briefing, openURL, runShortcut, sound
    var id: String { rawValue }

    var label: String {
        switch self {
        case .bubble:       return "Oli me prévient"
        case .notification: return "notification macOS"
        case .tidyDesktop:  return "ranger mon bureau"
        case .checkSites:   return "vérifier mes sites"
        case .refreshAll:   return "tout rafraîchir"
        case .briefing:     return "mon point du jour"
        case .openURL:      return "ouvrir une page"
        case .runShortcut:  return "lancer un raccourci Apple"
        case .sound:        return "jouer un son"
        }
    }

    var icon: String {
        switch self {
        case .bubble:       return "bubble.left.fill"
        case .notification: return "bell.fill"
        case .tidyDesktop:  return "sparkles.rectangle.stack.fill"
        case .checkSites:   return "globe"
        case .refreshAll:   return "arrow.triangle.2.circlepath"
        case .briefing:     return "sun.max.fill"
        case .openURL:      return "safari.fill"
        case .runShortcut:  return "square.stack.3d.up.fill"
        case .sound:        return "speaker.wave.2.fill"
        }
    }

    var param: (placeholder: String, defaultValue: String)? {
        switch self {
        case .openURL:     return ("https://…", "")
        case .runShortcut: return ("Nom du raccourci", "")
        default:           return nil
        }
    }
}

struct OliRule: Codable, Identifiable, Equatable {
    var id = UUID()
    var trigger: OliTrigger
    var triggerParam: String = ""
    var action: OliRuleAction
    var actionParam: String = ""
    var enabled = true
    var lastSignature: String? = nil
    var lastFired: Date? = nil

    /// « Quand un site tombe en panne, alors Oli me prévient »
    var sentence: String {
        var t = trigger.label
        if let p = trigger.param {
            let v = triggerParam.isEmpty ? p.defaultValue : triggerParam
            t += " \(v)" + (p.unit.isEmpty ? "" : (p.unit == "%" ? " %" : " \(p.unit)"))
        }
        var a = action.label
        if action.param != nil, !actionParam.isEmpty { a += " « \(actionParam) »" }
        return trigger == .dailyAt ? "C\(t.dropFirst()), \(a)" : "Quand \(t), alors \(a)"
    }

    var isValid: Bool {
        switch action {
        case .openURL:     return OliRules.safeURL(actionParam) != nil
        case .runShortcut: return !actionParam.trimmingCharacters(in: .whitespaces).isEmpty
        default:           break
        }
        if trigger == .dailyAt { return OliRules.parseTime(triggerParam.isEmpty ? "09:00" : triggerParam) != nil }
        if trigger.param != nil, !triggerParam.isEmpty { return Int(triggerParam) != nil }
        return true
    }
}

@MainActor
final class OliRules: ObservableObject {
    static let shared = OliRules()

    private static let key = "oliRules.v1"
    private let startedAt = Date()

    @Published var rules: [OliRule] { didSet { save() } }

    private init() {
        rules = (UserDefaults.standard.data(forKey: Self.key)).flatMap { try? JSONDecoder().decode([OliRule].self, from: $0) } ?? []
    }

    /// Ready-made ideas shown when there is no rule yet.
    static let suggestions: [OliRule] = [
        OliRule(trigger: .desktopFull, triggerParam: "20", action: .tidyDesktop),
        OliRule(trigger: .dailyAt, triggerParam: "09:00", action: .checkSites),
        OliRule(trigger: .siteDown, action: .notification),
        OliRule(trigger: .claudeFinished, action: .sound),
    ]

    func add(_ rule: OliRule) {
        var r = rule
        r.id = UUID()   // a suggestion can be added twice
        r.lastSignature = signature(for: r).sig   // what is already true now does not fire
        rules.insert(r, at: 0)
    }

    func remove(_ id: UUID) { rules.removeAll { $0.id == id } }

    func toggle(_ id: UUID) {
        guard let i = rules.firstIndex(where: { $0.id == id }) else { return }
        rules[i].enabled.toggle()
        if rules[i].enabled { rules[i].lastSignature = signature(for: rules[i]).sig }
    }

    // MARK: Engine

    func tick(now: Date = Date()) {
        guard !rules.isEmpty else { return }
        let warmingUp = now.timeIntervalSince(startedAt) < 120
        var changed = rules
        for i in changed.indices where changed[i].enabled {
            let (sig, detail) = signature(for: changed[i], now: now)
            guard let sig else {
                // While the pollers load, « nothing to report » is not news: keep the last state.
                if !warmingUp { changed[i].lastSignature = nil }
                continue
            }
            guard sig != changed[i].lastSignature else { continue }
            changed[i].lastSignature = sig
            changed[i].lastFired = now
            perform(changed[i], detail: detail)
        }
        if changed != rules { rules = changed }
    }

    /// Run the action right now (« Tester »).
    func test(_ rule: OliRule) {
        let detail = signature(for: rule).detail
        perform(rule, detail: detail.isEmpty ? "Test : \(rule.sentence.lowercased())" : detail)
    }

    func signature(for rule: OliRule, now: Date = Date()) -> (sig: String?, detail: String) {
        let app = AppState.shared
        switch rule.trigger {
        case .siteDown:
            let down = app.siteChecks.filter { $0.status == .down }.map(\.name).sorted()
            return (down.isEmpty ? nil : down.joined(separator: ","), down.isEmpty ? "" : "En panne : " + down.joined(separator: ", "))
        case .deployFailed:
            guard let d = app.vercelDeployments.first, d.state == "ERROR" else { return (nil, "") }
            return (d.id, "Déploiement raté : \(d.projectName)")
        case .buildBroken:
            let st = PillStatus.github(app)
            return st.tone == .alert ? (st.text, st.text) : (nil, "")
        case .prToReview:
            let prs = app.githubPulse?.toReview ?? []
            guard !prs.isEmpty else { return (nil, "") }
            return (prs.map(\.url).sorted().joined(separator: ","), prs.count == 1 ? "1 PR à relire : \(prs[0].title)" : "\(prs.count) PR à relire")
        case .projectLate:
            let late = app.espaceClients.filter { !$0.isDone && ($0.daysLeft ?? 0) < 0 }.map(\.name).sorted()
            return (late.isEmpty ? nil : late.joined(separator: ","), late.isEmpty ? "" : "En retard : " + late.joined(separator: ", "))
        case .meetingSoon:
            guard let e = app.nextEvent, !e.isAllDay else { return (nil, "") }
            let left = e.start.timeIntervalSince(now)
            return left > 0 && left <= 600 ? (e.id, "Dans \(max(1, Int(left / 60))) min : \(e.title)") : (nil, "")
        case .claudeFinished:
            return app.effectiveState == .finished ? ("finished", "Claude Code a fini ✔︎") : (nil, "")
        case .claudeQuota:
            let limit = Double(rule.triggerParam) ?? 80
            guard let u = app.claudePlanUsage, let pct = ClaudePlanGauge.dominantPct(u), pct >= limit else { return (nil, "") }
            let window = u.fiveHour.map { "\(Int($0.resetsAt.timeIntervalSince1970))" } ?? "w"
            return (window, "Quota Claude à \(Int(pct.rounded())) %")
        case .desktopFull:
            let limit = Int(rule.triggerParam) ?? 20
            let n = Self.looseDesktopFiles()
            return n >= limit ? ("full", "\(n) fichiers sur ton bureau") : (nil, "")
        case .dailyAt:
            guard let (h, m) = Self.parseTime(rule.triggerParam.isEmpty ? "09:00" : rule.triggerParam) else { return (nil, "") }
            let c = Calendar.current.dateComponents([.hour, .minute], from: now)
            let mins = (c.hour ?? 0) * 60 + (c.minute ?? 0), target = h * 60 + m
            // Window of 30 min so a Mac waking from sleep still gets it, once a day.
            guard mins >= target && mins < target + 30 else { return (nil, "") }
            return (now.formatted(.iso8601.year().month().day()), String(format: "Il est %02d:%02d", h, m))
        }
    }

    private func perform(_ rule: OliRule, detail: String) {
        appendAppLog("oli.log", "Automatisation : \(rule.sentence) (\(detail))")
        switch rule.action {
        case .bubble:
            DesktopOliController.shared.say(detail.isEmpty ? rule.sentence : detail, tone: .warn)
        case .notification:
            SystemNotify.post(title: "Oli", body: detail.isEmpty ? rule.sentence : detail, id: "rule-\(rule.id.uuidString)")
        case .tidyDesktop:
            OliAutomations.tidyDesktop()
        case .checkSites:
            OliAction.checkSites.run()
        case .refreshAll:
            OliAction.refreshAll.run()
        case .briefing:
            OliAction.briefing.run()
        case .openURL:
            if let u = Self.safeURL(rule.actionParam) { NSWorkspace.shared.open(u) }
        case .runShortcut:
            Self.runShortcut(rule.actionParam)
        case .sound:
            SoundEngine.shared.play("approve")
        }
    }

    // MARK: Helpers

    nonisolated static func parseTime(_ s: String) -> (Int, Int)? {
        let parts = s.replacingOccurrences(of: "h", with: ":").split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let h = parts.first.flatMap({ Int($0) }), (0..<24).contains(h) else { return nil }
        let m = parts.count > 1 ? (Int(parts[1].isEmpty ? "0" : parts[1]) ?? -1) : 0
        guard (0..<60).contains(m) else { return nil }
        return (h, m)
    }

    /// Only web pages: a rule never opens a file or an app link.
    nonisolated static func safeURL(_ s: String) -> URL? {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty, !t.contains("://") { t = "https://" + t }
        guard let u = URL(string: t), ["http", "https"].contains(u.scheme?.lowercased() ?? ""), u.host != nil else { return nil }
        return u
    }

    /// The user's own Shortcuts (app Raccourcis), by name, in the background.
    nonisolated static func runShortcut(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        p.arguments = ["run", n]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }

    nonisolated static func looseDesktopFiles() -> Int {
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(at: DesktopTidy.desktopURL, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
                                                 options: [.skipsHiddenFiles])) ?? []
        return items.filter { u in
            let v = try? u.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            return !(v?.isDirectory == true && v?.isPackage != true) && u.pathExtension.lowercased() != "app"
        }.count
    }

    private func save() {
        if let d = try? JSONEncoder().encode(rules) { UserDefaults.standard.set(d, forKey: Self.key) }
    }
}
