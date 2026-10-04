import SwiftUI

// MARK: - Contenu des cartes
// The three lines the focus card shows for each section, its subtitle, and the mood / badge of each
// mini Oli in the grid.

struct CardLine: Identifiable {
    let id: String
    let color: Color
    let title: String
    let detail: String
    var urgent = false
    let action: () -> Void
}

@MainActor
enum CardContent {
    static func lines(_ s: Section, _ m: OliModel) -> [CardLine] {
        let full = { m.tab = .full }
        switch s {
        case .home:
            var out: [CardLine] = []
            if m.briefing != nil {
                out.append(CardLine(id: "brief", color: Palette.beurre, title: "Le mot d’Oli", detail: "lire", action: full))
            }
            if let a = m.approvals.first {
                out.append(CardLine(id: "appr", color: Palette.beurre, title: "Claude attend ton accord", detail: a.project, urgent: true,
                                    action: { m.section = .claude }))
            }
            let down = m.sites.filter { $0.status == .down }
            if let d = down.first {
                out.append(CardLine(id: "down", color: Palette.alerte, title: down.count == 1 ? "\(d.name) en panne" : "\(down.count) sites en panne",
                                    detail: d.reason ?? "", urgent: true, action: { m.section = .sites }))
            }
            if let l = m.projects.first(where: \.isLate) {
                out.append(CardLine(id: "late", color: Palette.alerte, title: "\(l.name) en retard", detail: l.stepLabel, urgent: true,
                                    action: { m.section = .projects }))
            }
            if let w = m.sessions.first(where: { $0.phase == .working }) {
                out.append(CardLine(id: "claude", color: Palette.lilas, title: "Claude · \(w.project)", detail: w.activity, action: { m.section = .claude }))
            }
            if let e = m.nextEvent {
                out.append(CardLine(id: "agenda", color: Palette.ciel, title: when(e), detail: e.title, action: { m.section = .agenda }))
            }
            if let p = m.projects.first(where: { !$0.isDone && !$0.isLate }) {
                out.append(CardLine(id: "proj", color: Palette.tomate, title: p.name, detail: "\(p.dueLabel) · \(p.stepLabel)", action: { m.section = .projects }))
            }
            if down.isEmpty, !m.sites.isEmpty {
                let warn = m.sites.first { $0.status == .warning || !(m.siteAudits[$0.url]?.issues.isEmpty ?? true) }
                out.append(CardLine(id: "sites", color: warn == nil ? Palette.menthe : Palette.beurre,
                                    title: "\(m.sites.count) site\(m.sites.count > 1 ? "s" : "") en ligne",
                                    detail: warn.map { $0.reason ?? m.siteAudits[$0.url]?.issues.first ?? "" } ?? "tout va bien",
                                    action: { m.section = .sites }))
            }
            if let i = m.instagram, i.fetchedAt != nil, let r = i.reminders().first {
                out.append(CardLine(id: "insta", color: Palette.rose, title: "Instagram", detail: r, action: { m.section = .instagram }))
            }
            return out

        case .claude:
            return m.sessions.map { x in
                CardLine(id: x.id, color: x.phase == .working ? Palette.lilas : x.phase == .waiting ? Palette.beurre : x.phase == .done ? Palette.menthe : Palette.dust,
                         title: x.project, detail: x.activity, action: { TerminalCommands.open(folder: x.cwd) })
            }

        case .projects:
            return m.projects.filter { !$0.isDone }.map { p in
                CardLine(id: p.id, color: p.isLate ? Palette.alerte : (p.daysLeft ?? 99) <= 7 ? Palette.beurre : Palette.tomate,
                         title: p.name, detail: "\(p.dueLabel) · \(p.stepLabel)", urgent: p.isLate, action: full)
            }

        case .sites:
            return m.sites.sorted { $0.status.order < $1.status.order }.map { x in
                let issue = x.reason ?? m.siteAudits[x.url]?.issues.first
                let c: Color = x.status == .down ? Palette.alerte : (x.status == .warning || issue != nil) ? Palette.beurre : Palette.menthe
                return CardLine(id: x.id, color: c, title: x.name, detail: issue ?? x.latencyLabel, urgent: x.status == .down, action: full)
            }

        case .agenda:
            return m.agenda.filter { $0.end > Date() }.map { e in
                CardLine(id: e.id, color: Palette.ciel, title: when(e), detail: e.title,
                         action: { openURL(e.meetingURL?.absoluteString ?? AgendaWatcher.calendarURL.absoluteString) })
            }

        case .instagram:
            guard let i = m.instagram else { return [] }
            if let e = i.error { return [CardLine(id: "err", color: Palette.alerte, title: "Instagram", detail: e, action: full)] }
            var out = [CardLine(id: "stats", color: Palette.rose, title: i.followersLabel, detail: i.lastPostLabel(), action: full)]
            out += i.unanswered.prefix(2).map { c in
                CardLine(id: c.id, color: Palette.beurre, title: "@" + c.username, detail: c.text, action: { openURL(c.postPermalink) })
            }
            return out

        case .terminal, .chat:
            return []
        }
    }

    static func subtitle(_ s: Section, _ m: OliModel) -> String {
        switch s {
        case .home: return Date().formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "fr_FR")))
        case .claude: return m.sessions.isEmpty ? "aucune session" : "\(m.sessions.count) session\(m.sessions.count > 1 ? "s" : "")"
        case .projects: return "\(m.projects.filter { !$0.isDone }.count) en cours"
        case .sites:
            let down = m.sites.filter { $0.status == .down }.count
            return down > 0 ? "\(down) en panne" : "\(m.sites.count) en ligne"
        case .agenda: return m.nextEvent.map { $0.isToday ? "aujourd’hui" : $0.dayLabel } ?? "rien de prévu"
        case .instagram: return m.instagram?.username.isEmpty == false ? "@" + (m.instagram?.username ?? "") : ""
        case .terminal: return OliTerminal.shared.directory
        case .chat: return ""
        }
    }

    static func empty(_ s: Section) -> String {
        switch s {
        case .home: return "Tout est calme. Branche tes services dans les Réglages pour que je te tienne au courant."
        case .claude: return "Aucune session. Lance « claude » dans un terminal."
        case .projects: return "Aucun projet en cours."
        case .sites: return "Première vérification en cours…"
        case .agenda: return "Rien de prévu sur 14 jours."
        case .instagram: return "Lecture d’Instagram…"
        case .terminal, .chat: return ""
        }
    }

    static func when(_ e: AgendaEvent) -> String {
        e.isAllDay ? (e.isToday ? "Aujourd’hui" : e.dayLabel) : e.isToday ? e.timeLabel : e.isTomorrow ? "Demain \(e.timeLabel)" : "\(e.dayLabel) \(e.timeLabel)"
    }
}

extension OliModel {
    /// How each mini Oli looks in the grid.
    func miniMood(_ s: Section) -> Mood {
        switch s {
        case .home: return mood
        case .claude: return !approvals.isEmpty ? .waiting : sessions.contains { $0.phase == .working } ? .busy : .calm
        case .sites: return sites.contains { $0.status == .down } ? .alarm : .calm
        case .projects: return projects.contains(where: \.isLate) ? .waiting : .calm
        case .agenda:
            let soon = agenda.contains { !$0.isAllDay && $0.start > Date() && $0.start.timeIntervalSinceNow < 900 }
            return soon ? .waiting : .calm
        case .instagram: return (instagram?.reminders().isEmpty ?? true) ? .calm : .waiting
        case .terminal, .chat: return .calm
        }
    }

    func badge(_ s: Section) -> Int {
        switch s {
        case .claude: return approvals.count
        case .sites: return sites.filter { $0.status == .down }.count
        case .instagram: return instagram?.unanswered.count ?? 0
        case .projects: return projects.filter(\.isLate).count
        default: return 0
        }
    }
}
