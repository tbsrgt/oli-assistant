import Foundation

// MARK: - Briefing du matin / récap du vendredi : déclenchement (phase 6)
// On the first hover of the morning (and of Friday afternoon) the island opens on the chat with
// Oli's briefing instead of the overview. Texts come from Briefing.swift, facts from AppState.

@MainActor
final class BriefingCenter {
    static let shared = BriefingCenter()
    private init() {}

    #if DEBUG
    /// Dev only: `scripts/briefing-demo.sh [morning|friday]` shows a briefing now, without using up today's.
    func installDebugTrigger() {
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("studio.oculot.oli.briefingDemo"),
                                                            object: nil, queue: .main) { note in
            let kind: Briefing.Kind = (note.object as? String) == "friday" ? .friday : .morning
            Task { @MainActor in
                BriefingCenter.shared.post(kind, remember: false)
                NotificationCenter.default.post(name: .hookExpand, object: IslandView.prompt)
            }
        }
    }
    #endif

    /// Facts from what Oli knows right now.
    func facts() -> BriefingFacts {
        let app = AppState.shared
        let weekAgo = Date().addingTimeInterval(-7 * 86400)
        var f = BriefingFacts()
        f.firstName = resolveUserFirstName()
        f.espaceConfigured = KeychainStore.shared.get("espace-token") != nil
        f.projects = app.espaceClients.map { c in
            BriefingFacts.Project(name: c.name, step: c.stepLabel, progress: c.progress, daysLeft: c.daysLeft,
                                  inactiveDays: c.inactiveDays, isDone: c.isDone, isNew: c.createdAt >= weekAgo,
                                  doneThisWeek: c.recentlyDone)
        }
        f.sites = app.siteChecks.map { s in
            BriefingFacts.Site(name: s.name, down: s.status == .down, reason: s.reason,
                               issues: (s.status == .warning ? [s.reason].compactMap { $0 } : []) + (app.siteAudits[s.url]?.issues ?? []))
        }
        f.incidentsThisWeek = SitesPoller.incidents(since: weekAgo)
        if app.siteChecks.isEmpty { f.sitesPending = SitesPoller.targets.count }
        if KeychainStore.shared.get("agenda-ics-url") != nil, app.agendaLastSync != nil {
            f.agendaToday = app.agendaEvents.filter(\.isToday).map { e in
                (e.isAllDay ? "Toute la journée" : e.timeLabel) + " · " + e.title + (e.meetingURL != nil ? " (visio)" : "")
            }
        }
        if let s = app.social, s.fetchedAt != nil {
            f.social = BriefingFacts.Social(username: s.username, followers: s.followers, lastPostDays: s.daysSinceLastPost(),
                                            postsThisWeek: s.postsSince(weekAgo).count, reminders: s.reminders(), error: s.error)
        }
        return f
    }

    /// Called when a hover opens the island. Returns `.prompt` (the chat) when a briefing was
    /// just posted there, nil to keep the usual view. Alerts always win over a briefing.
    func viewForHover(now: Date = Date()) -> IslandView? {
        let app = AppState.shared
        guard app.pendingApproval == nil, app.pendingQuestion == nil, !app.sitesPanic else { return nil }
        let ud = UserDefaults.standard
        guard let kind = Briefing.due(now: now, lastMorning: ud.string(forKey: "briefingMorningDay"),
                                      lastFriday: ud.string(forKey: "briefingFridayDay")) else { return nil }
        post(kind, now: now)
        return .prompt
    }

    /// Writes the text in the chat and remembers the day. Also used by the debug trigger.
    func post(_ kind: Briefing.Kind, now: Date = Date(), remember: Bool = true) {
        let f = facts()
        let text = kind == .morning ? Briefing.morning(f, now: now) : Briefing.fridayRecap(f, now: now)
        if remember {
            UserDefaults.standard.set(Briefing.dayKey(now), forKey: kind == .morning ? "briefingMorningDay" : "briefingFridayDay")
        }
        AppState.shared.chatHistory.append(ChatMessage(role: .assistant, content: text))
        SoundEngine.shared.play("greet")
    }
}
