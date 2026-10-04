import Foundation

// MARK: - Briefing du matin / récap du vendredi
// Facts come from the model; texts from Briefing.swift. Shown as a card on « Aujourd’hui »
// the first time Oli opens in the morning (5 h–13 h) and on Friday from 15 h.

@MainActor
enum BriefingDesk {
    static func facts() -> BriefingFacts {
        let m = OliModel.shared
        let weekAgo = Date().addingTimeInterval(-7 * 86400)
        var f = BriefingFacts()
        f.firstName = firstName()
        f.espaceConfigured = Secrets.shared.has(.espaceToken)
        f.projects = m.projects.map {
            .init(name: $0.name, step: $0.stepLabel, progress: $0.progress, daysLeft: $0.daysLeft,
                  inactiveDays: $0.inactiveDays, isDone: $0.isDone, isNew: $0.isNew, doneThisWeek: $0.doneThisWeek)
        }
        f.sites = m.sites.map { s in
            .init(name: s.name, down: s.status == .down, reason: s.reason,
                  issues: (s.status == .warning ? [s.reason].compactMap { $0 } : []) + (m.siteAudits[s.url]?.issues ?? []))
        }
        if m.sites.isEmpty { f.sitesPending = m.siteTargets.count }
        f.incidentsThisWeek = SitesWatcher.incidents(since: weekAgo)
        if Secrets.shared.has(.agendaURL), m.agendaSynced != nil {
            f.agendaToday = m.agenda.filter(\.isToday).map {
                ($0.isAllDay ? "Toute la journée" : $0.timeLabel) + " · " + $0.title + ($0.meetingURL != nil ? " (visio)" : "")
            }
        }
        if let s = m.instagram, s.fetchedAt != nil {
            f.social = .init(username: s.username, followers: s.followers, lastPostDays: s.daysSinceLastPost(),
                             postsThisWeek: s.postsSince(weekAgo).count, reminders: s.reminders(), error: s.error)
        }
        return f
    }

    /// Called each time the notch opens: puts the briefing on the home card when one is due.
    static func checkDue(now: Date = Date()) {
        let ud = UserDefaults.standard
        guard OliModel.shared.briefing == nil,
              let kind = Briefing.due(now: now, lastMorning: ud.string(forKey: "briefingMorningDay"),
                                      lastFriday: ud.string(forKey: "briefingFridayDay")) else { return }
        show(kind, now: now)
        ud.set(Briefing.dayKey(now), forKey: kind == .morning ? "briefingMorningDay" : "briefingFridayDay")
    }

    static func show(_ kind: Briefing.Kind, now: Date = Date()) {
        let f = facts()
        OliModel.shared.briefing = (kind, kind == .morning ? Briefing.morning(f, now: now) : Briefing.fridayRecap(f, now: now))
        OliModel.shared.section = .home
    }

    static func firstName() -> String? {
        let full = NSFullUserName().trimmingCharacters(in: .whitespaces)
        guard let first = full.split(separator: " ").first, first.count > 1 else { return nil }
        return String(first)
    }
}
