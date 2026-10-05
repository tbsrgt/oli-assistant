import Foundation

// MARK: - Ligne d'état des tuiles de l'accueil
// Sous le nom de chaque service (partie droite de l'accueil), une phrase courte qui dit l'essentiel :
// « 2 en ligne », « Test · J-9 », « 1 en panne ». La couleur dit si tout va bien, sans rien lire.

enum PillTone: Equatable {
    case ok, warn, alert, neutral

    var hex: String {
        switch self {
        case .ok:      return "#4ADE80"
        case .warn:    return "#FFD65C"
        case .alert:   return "#FF6B76"
        case .neutral: return "#9398A1"
        }
    }
}

struct PillStatus: Equatable {
    let text: String
    let tone: PillTone

    /// What the tile says for this pill right now.
    @MainActor
    static func of(_ task: AgentTask, state: AppState, now: Date = Date()) -> PillStatus {
        // A live alert on the pill wins: it is what Oli is trying to tell.
        if let line = task.steps.first, !line.isEmpty {
            switch task.state {
            case .error: return PillStatus(text: line, tone: .alert)
            case .question, .approval: return PillStatus(text: line, tone: .warn)
            default: break
            }
        }
        switch task.id {
        case "integration_sites":     return sites(state)
        case "integration_espace":    return espace(state)
        case "integration_agenda":    return agenda(state, now: now)
        case "integration_vercel":    return vercel(state)
        case "integration_github":    return github(state)
        case "integration_instagram": return instagram(state)
        default:                      return session(task)
        }
    }

    @MainActor
    static func sites(_ state: AppState) -> PillStatus {
        let checks = state.siteChecks
        if checks.isEmpty { return PillStatus(text: SitesPoller.targets.isEmpty ? "Aucun site" : "Vérification…", tone: .neutral) }
        let down = checks.filter { $0.status == .down }
        if down.count == 1 { return PillStatus(text: "\(down[0].name) en panne", tone: .alert) }
        if down.count > 1 { return PillStatus(text: "\(down.count) en panne", tone: .alert) }
        let warn = checks.filter { $0.status == .warning || !(state.siteAudits[$0.url]?.issues.isEmpty ?? true) }
        let online = checks.filter { $0.status == .ok || $0.status == .warning }.count
        if !warn.isEmpty { return PillStatus(text: "\(online) en ligne · \(warn.count) à voir", tone: .warn) }
        return PillStatus(text: online == 1 ? "1 en ligne" : "\(online) en ligne", tone: .ok)
    }

    @MainActor
    static func espace(_ state: AppState) -> PillStatus {
        if KeychainStore.shared.get("espace-token") == nil { return PillStatus(text: "Se connecter", tone: .neutral) }
        let active = state.espaceClients.filter { !$0.isDone }
        if active.isEmpty { return PillStatus(text: state.espaceLastSync == nil ? "Chargement…" : "Aucun projet", tone: .neutral) }
        if let late = active.first(where: { ($0.daysLeft ?? 0) < 0 }) {
            return PillStatus(text: "\(late.name) en retard", tone: .alert)
        }
        let next = active.min { ($0.daysLeft ?? 9999) < ($1.daysLeft ?? 9999) }!
        let soon = (next.daysLeft ?? 99) <= 3
        return PillStatus(text: "\(next.name) · \(next.daysLabel)", tone: soon ? .warn : .neutral)
    }

    @MainActor
    static func agenda(_ state: AppState, now: Date) -> PillStatus {
        guard let e = state.nextEvent else { return PillStatus(text: "Rien de prévu", tone: .neutral) }
        let soon = e.start.timeIntervalSince(now) < 3600 && e.end > now
        let when = e.start <= now ? "en cours" : e.isToday ? e.timeLabel : e.isTomorrow ? "demain" : e.dayLabel
        return PillStatus(text: "\(when) · \(e.title)", tone: soon ? .warn : .neutral)
    }

    @MainActor
    static func vercel(_ state: AppState) -> PillStatus {
        guard let d = state.vercelDeployments.first else { return PillStatus(text: "Aucun déploiement", tone: .neutral) }
        switch d.state {
        case "READY":    return PillStatus(text: "\(d.projectName) · en ligne", tone: .ok)
        case "ERROR":    return PillStatus(text: "\(d.projectName) · échec", tone: .alert)
        case "CANCELED": return PillStatus(text: "\(d.projectName) · annulé", tone: .neutral)
        default:         return PillStatus(text: "\(d.projectName) · en cours…", tone: .warn)
        }
    }

    @MainActor
    static func github(_ state: AppState) -> PillStatus {
        guard let p = state.githubPulse else { return PillStatus(text: "Chargement…", tone: .neutral) }
        let failing = p.mainCI.filter { $0.ci == .failure }.map(\.repo) + p.myPRs.filter { $0.ci == .failure }.map(\.repo)
        if let repo = failing.first { return PillStatus(text: "Build cassé · \(repo.split(separator: "/").last.map(String.init) ?? repo)", tone: .alert) }
        if !p.toReview.isEmpty { return PillStatus(text: p.toReview.count == 1 ? "1 PR à relire" : "\(p.toReview.count) PR à relire", tone: .warn) }
        if !p.myPRs.isEmpty { return PillStatus(text: p.myPRs.count == 1 ? "1 PR ouverte" : "\(p.myPRs.count) PR ouvertes", tone: .neutral) }
        return PillStatus(text: "Tout est vert", tone: .ok)
    }

    @MainActor
    static func instagram(_ state: AppState) -> PillStatus {
        guard let s = state.social else { return PillStatus(text: "Chargement…", tone: .neutral) }
        if let e = s.error { return PillStatus(text: e, tone: .alert) }
        if let r = s.reminders().first { return PillStatus(text: r, tone: .warn) }
        return PillStatus(text: s.followersLabel, tone: .neutral)
    }

    /// Claude Code sessions and anything else: what the agent is doing.
    static func session(_ task: AgentTask) -> PillStatus {
        switch task.state {
        case .working, .thinking, .searching: return PillStatus(text: "Travaille…", tone: .warn)
        case .approval, .question:            return PillStatus(text: "Attend ton accord", tone: .warn)
        case .finished:                       return PillStatus(text: "Terminé", tone: .ok)
        case .error:                          return PillStatus(text: "Erreur", tone: .alert)
        case .ratelimit:                      return PillStatus(text: "En pause (quota)", tone: .warn)
        default:                              return PillStatus(text: "Prêt", tone: .neutral)
        }
    }
}
