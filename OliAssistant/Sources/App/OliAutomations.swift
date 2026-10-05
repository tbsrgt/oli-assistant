import AppKit
import SwiftUI

// MARK: - Automatisations d'Oli
// Oli est le point central : des actions à lancer d'un clic (bulle d'Oli, Réglages) et des
// routines qui tournent toutes seules. Quand une routine a quelque chose à dire, Oli le dit
// dans une bulle s'il est sur le bureau, sinon par une notification. Rien n'est envoyé ni
// accepté à ta place : une routine montre, c'est toi qui cliques.

enum OliAction: String, CaseIterable, Identifiable {
    case refreshAll, tidyDesktop, checkSites, briefing, askClaude, terminal, agenda, espace, wardrobe

    var id: String { rawValue }

    var title: String {
        switch self {
        case .refreshAll: return "Tout rafraîchir"
        case .tidyDesktop: return "Ranger mon bureau"
        case .checkSites: return "Vérifier mes sites"
        case .briefing:   return "Mon point du jour"
        case .askClaude:  return "Demander à Claude"
        case .terminal:   return "Terminal"
        case .agenda:     return "Ouvrir l’agenda"
        case .espace:     return "Espace client"
        case .wardrobe:   return "Habiller Oli"
        }
    }

    var icon: String {
        switch self {
        case .refreshAll: return "arrow.triangle.2.circlepath"
        case .tidyDesktop: return "sparkles.rectangle.stack.fill"
        case .checkSites: return "globe"
        case .briefing:   return "sun.max.fill"
        case .askClaude:  return "sparkles"
        case .terminal:   return "terminal.fill"
        case .agenda:     return "calendar"
        case .espace:     return "folder.fill"
        case .wardrobe:   return "tshirt.fill"
        }
    }

    var color: String {
        switch self {
        case .refreshAll: return "#3B9EFF"
        case .tidyDesktop: return "#A78BFA"
        case .checkSites: return "#22C55E"
        case .briefing:   return "#FFD65C"
        case .askClaude:  return "#E07950"
        case .terminal:   return "#8E939C"
        case .agenda:     return "#FFB547"
        case .espace:     return "#FF5B37"
        case .wardrobe:   return "#F7C3D4"
        }
    }

    @MainActor
    func run() {
        switch self {
        case .refreshAll:
            OliAutomations.refreshAll()
            DesktopOliController.shared.say("Je rafraîchis tout, deux secondes…", tone: .neutral)
        case .tidyDesktop:
            OliAutomations.tidyDesktop()
        case .checkSites:
            SitesPoller.shared.checkNow()
            DesktopOliController.shared.say("Je passe sur tes sites…", tone: .neutral)
        case .briefing:
            BriefingCenter.shared.post(.morning, remember: false)
            NotificationCenter.default.post(name: .hookExpand, object: IslandView.prompt)
        case .askClaude:
            NotificationCenter.default.post(name: .hookExpand, object: IslandView.prompt)
        case .terminal:
            NotificationCenter.default.post(name: .hookExpand, object: IslandView.terminal)
        case .agenda:
            NSWorkspace.shared.open(AgendaPoller.calendarURL)
        case .espace:
            NSWorkspace.shared.open(EspacePoller.adminURL)
        case .wardrobe:
            NotificationCenter.default.post(name: .openWardrobeFromDesktop, object: nil)
        }
    }
}

enum OliRoutine: String, CaseIterable, Identifiable {
    case morning, alerts, meeting, evening

    var id: String { rawValue }

    var title: String {
        switch self {
        case .morning: return "Point du matin"
        case .alerts:  return "Oli me prévient"
        case .meeting: return "Avant un rendez-vous"
        case .evening: return "Récap du soir"
        }
    }

    var detail: String {
        switch self {
        case .morning: return "En semaine à 8 h 30, Oli rafraîchit tout et te résume la journée."
        case .alerts:  return "Site en panne, build cassé, déploiement raté, projet en retard : une bulle tout de suite."
        case .meeting: return "10 minutes avant, une bulle avec le bouton pour rejoindre la visio."
        case .evening: return "En semaine à 18 h, ce qui reste à faire et ton premier rendez-vous de demain."
        }
    }

    var icon: String {
        switch self {
        case .morning: return "sunrise.fill"
        case .alerts:  return "bell.badge.fill"
        case .meeting: return "video.fill"
        case .evening: return "moon.stars.fill"
        }
    }

    var defaultOn: Bool { self != .evening }

    private var key: String { "routine.\(rawValue)" }

    var isOn: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? defaultOn }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

@MainActor
final class OliAutomations {
    static let shared = OliAutomations()
    private init() {}

    static var enabledRoutines: [OliRoutine] { OliRoutine.allCases.filter(\.isOn) }

    private var timer: Timer?
    private let startedAt = Date()
    /// Last tone seen per tile, to speak only when something gets worse.
    private var lastTone: [HomeTileKind: PillTone] = [:]
    private var announcedMeetings: Set<String> = []

    // MARK: « Ranger mon bureau » (DesktopTidy: moves only, never deletes)

    /// `onDone` given: the caller shows the result itself (island button), no bubble.
    static func tidyDesktop(onDone: (@MainActor (DesktopTidy.Report) -> Void)? = nil) {
        if onDone == nil { DesktopOliController.shared.say("Je range ton bureau…", tone: .neutral) }
        Task.detached {
            let report = DesktopTidy.tidy()
            await MainActor.run {
                if let onDone {
                    appendAppLog("oli.log", "Rangement du bureau : \(report.moves.count) déplacés, \(report.errors.count) erreurs")
                    if !report.moves.isEmpty { SoundEngine.shared.play("approve") }
                    onDone(report)
                } else {
                    OliAutomations.tidyDone(report)
                }
            }
        }
    }

    private static func tidyDone(_ report: DesktopTidy.Report) {
        appendAppLog("oli.log", "Rangement du bureau : \(report.moves.count) déplacés, \(report.errors.count) erreurs")
        guard !report.moves.isEmpty else {
            DesktopOliController.shared.say(report.summary, tone: report.errors.isEmpty ? .ok : .warn)
            return
        }
        SoundEngine.shared.play("approve")
        let undo: @MainActor () -> Void = { OliAutomations.undoTidy() }
        DesktopOliController.shared.say(report.summary, tone: .ok, button: ("Annuler", undo))
    }

    static func undoTidy(onDone: (@MainActor (Int) -> Void)? = nil) {
        Task.detached {
            let n = DesktopTidy.undo()
            await MainActor.run {
                if let onDone { onDone(n) } else { OliAutomations.undoDone(n) }
            }
        }
    }

    private static func undoDone(_ n: Int) {
        let files = n > 1 ? "\(n) fichiers remis" : "\(n) fichier remis"
        DesktopOliController.shared.say("C’est comme avant : \(files) à leur place.", tone: .ok)
    }

    static func refreshAll() {
        SitesPoller.shared.checkNow()
        EspacePoller.shared.pollNow()
        AgendaPoller.shared.pollNow()
        SocialPoller.shared.refreshNow()
        GithubPoller.shared.triggerPulseNow()
    }

    func start() {
        guard timer == nil else { return }
        // Every 10 s: routines are to the minute, « Quand… alors… » rules want to catch short states
        // (Claude Code « fini »). Each tick only reads what Oli already knows.
        let t = Timer(timeInterval: 10, repeats: true) { _ in
            Task { @MainActor in OliAutomations.shared.tick() }
        }
        t.tolerance = 5
        RunLoop.main.add(t, forMode: .common)
        timer = t
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { self.tick() }
    }

    func tick(now: Date = Date()) {
        OliRules.shared.tick(now: now)
        let app = AppState.shared
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: now)
        let workday = weekday != 1 && weekday != 7

        if OliRoutine.morning.isOn, workday, isTime(8, 30, now), once("morning", now) {
            Self.refreshAll()
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { self.speakSummary(morning: true) }
        }
        if OliRoutine.evening.isOn, workday, isTime(18, 0, now), once("evening", now) {
            speakSummary(morning: false)
        }
        if OliRoutine.meeting.isOn, let e = app.nextEvent, !e.isAllDay {
            let left = e.start.timeIntervalSince(now)
            if left > 0, left <= 10 * 60, !announcedMeetings.contains(e.id) {
                announcedMeetings.insert(e.id)
                let link = e.meetingURL
                DesktopOliController.shared.say("Dans \(max(1, Int(left / 60))) min : \(e.title)", tone: .warn,
                                                button: link.map { url in ("Rejoindre", { NSWorkspace.shared.open(url) }) })
            }
        }
        watchAlerts(app, now: now)
    }

    // MARK: Alerts: speak when a tile gets worse

    private func watchAlerts(_ app: AppState, now: Date) {
        let watched: [HomeTileKind] = [.sites, .projects, .github, .vercel, .instagram, .claude]
        let first = lastTone.isEmpty
        for kind in watched {
            if let c = kind.connection, !c.isConnected { continue }
            let d = kind.data(app, now: now)
            let before = lastTone[kind]
            lastTone[kind] = d.tone
            // The first minutes are the pollers loading (« Vérification… » → real state): not news.
            guard !first, now.timeIntervalSince(startedAt) > 120, OliRoutine.alerts.isOn, let before else { continue }
            if rank(d.tone) > rank(before), d.tone == .alert || d.tone == .warn {
                DesktopOliController.shared.say("\(kind.title) : \(d.detail)", tone: d.tone,
                                                button: ("Voir", { kind.open(AppState.shared) }))
            }
        }
    }

    private func rank(_ t: PillTone) -> Int {
        switch t { case .ok, .neutral: return 0; case .warn: return 1; case .alert: return 2 }
    }

    // MARK: Morning / evening summary

    func speakSummary(morning: Bool) {
        let app = AppState.shared
        var parts: [String] = []
        let sites = PillStatus.sites(app)
        if !app.siteChecks.isEmpty { parts.append("sites : \(sites.text)") }
        let active = app.espaceClients.filter { !$0.isDone }
        if !active.isEmpty { parts.append("\(active.count) projet\(active.count > 1 ? "s" : "") en cours") }
        if morning {
            let today = app.agendaEvents.filter(\.isToday)
            parts.append(today.isEmpty ? "aucun rendez-vous" : "\(today.count) rendez-vous, le premier à \(today[0].timeLabel)")
        } else if let e = app.agendaEvents.first(where: \.isTomorrow) {
            parts.append("demain \(e.timeLabel) · \(e.title)")
        }
        let hello = morning ? "Bonjour\(resolveUserFirstName().map { " \($0)" } ?? "") ! " : "Fin de journée. "
        let worst: PillTone = sites.tone == .alert ? .alert : .neutral
        DesktopOliController.shared.say(hello + parts.joined(separator: ", ").capitalizedFirst + ".", tone: worst,
                                        button: ("Mon point", { OliAction.briefing.run() }))
    }

    // MARK: Helpers

    private func isTime(_ h: Int, _ m: Int, _ now: Date) -> Bool {
        let c = Calendar.current.dateComponents([.hour, .minute], from: now)
        guard let hh = c.hour, let mm = c.minute else { return false }
        let mins = hh * 60 + mm, target = h * 60 + m
        return mins >= target && mins < target + 30   // a sleeping Mac still gets it when it wakes up
    }

    /// True once per day per routine.
    private func once(_ id: String, _ now: Date) -> Bool {
        let day = now.formatted(.iso8601.year().month().day())
        let key = "routine.\(id).last"
        guard UserDefaults.standard.string(forKey: key) != day else { return false }
        UserDefaults.standard.set(day, forKey: key)
        return true
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
