import Foundation

// MARK: - Agenda Oculot
// Relit toutes les 5 min l'adresse iCal secrète d'un agenda Google (clé "agenda-ics-url" du Trousseau),
// remplit AppState.agendaEvents et prévient 10 min avant chaque rendez-vous (une seule fois).
// Lecture seule, sans OAuth. Le parseur est dans AgendaICS.swift.

final class AgendaPoller: @unchecked Sendable {
    static let shared = AgendaPoller()
    /// Where a click goes: agenda.oculot.studio, or Google Agenda when the feed comes from Google.
    static var calendarURL: URL {
        let feed = KeychainStore.shared.get("agenda-ics-url") ?? ""
        return URL(string: feed.contains("google.com") ? "https://calendar.google.com" : "https://agenda.oculot.studio")!
    }

    private var timer: DispatchSourceTimer?
    private var alertTimer: DispatchSourceTimer?
    private var alertedIds: Set<String> = []     // événements déjà annoncés (touché sur le main thread)

    private init() {}

    func start() {
        guard timer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: .global(qos: .background))
        t.schedule(deadline: .now() + 6, repeating: 300)
        t.setEventHandler { [weak self] in self?.poll() }
        t.resume()
        timer = t

        // Vérification des alertes toutes les 60 s (simple parcours d'un petit tableau).
        let a = DispatchSource.makeTimerSource(queue: .main)
        a.schedule(deadline: .now() + 30, repeating: 60)
        a.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.checkAlerts() }
        }
        a.resume()
        alertTimer = a
    }

    /// Rafraîchissement immédiat (après l'enregistrement de l'adresse dans les Réglages).
    func pollNow() {
        DispatchQueue.global(qos: .background).async { [weak self] in self?.poll() }
    }

    // MARK: - Poll

    private func poll() {
        let raw = (KeychainStore.shared.get("agenda-ics-url") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        // Google donne parfois l'adresse en webcal:// ; on la lit en https.
        let fixed = raw.hasPrefix("webcal://") ? "https://" + raw.dropFirst("webcal://".count) : raw
        guard let url = URL(string: fixed), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            DispatchQueue.main.async { AppState.shared.agendaLastStatus = -1 }
            return
        }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue("text/calendar", forHTTPHeaderField: "Accept")
        req.cachePolicy = .reloadIgnoringLocalCacheData

        URLSession.shared.dataTask(with: req) { [weak self] data, response, _ in
            guard let self else { return }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            DispatchQueue.main.async { AppState.shared.agendaLastStatus = code }
            guard let data, code == 200,
                  let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
                  text.contains("BEGIN:VCALENDAR") else { return }
            let events = AgendaICS.parse(text)
            DispatchQueue.main.async { self.handle(events) }
        }.resume()
    }

    @MainActor
    private func handle(_ events: [AgendaEvent]) {
        let app = AppState.shared
        app.agendaEvents = events
        app.agendaLastSync = Date()
        // Oublie les alertes d'événements qui ne sont plus dans la fenêtre.
        let ids = Set(events.map(\.id))
        alertedIds = alertedIds.intersection(ids)
        checkAlerts()
    }

    // MARK: - Alertes (10 min avant, une seule fois par événement)

    @MainActor
    private func checkAlerts() {
        let app = AppState.shared
        let now = Date()
        let due = app.agendaEvents.filter { e in
            !e.isAllDay && !alertedIds.contains(e.id) && e.start > now && e.start.timeIntervalSince(now) <= 600
        }
        guard let next = due.first else { return }
        due.forEach { alertedIds.insert($0.id) }
        guard let idx = app.tasks.firstIndex(where: { $0.id == "integration_agenda" }) else {
            // No Agenda mini Oli on screen: never drop the reminder, send it to the Notification Center.
            SystemNotify.post(title: "Dans 10 min : \(next.title)", body: next.timeLabel, id: "agenda-\(next.id)")
            return
        }

        app.tasks[idx].state = .question
        app.tasks[idx].steps = ["\(next.timeLabel) · \(next.title)"]
        if app.focusId != "integration_agenda" {
            app.tasks[idx].pillBadge = .approval
        }
        SoundEngine.shared.play("question")
        NotificationCenter.default.post(name: .hookReveal, object: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
            guard let i = app.tasks.firstIndex(where: { $0.id == "integration_agenda" }) else { return }
            guard app.tasks[i].state == .question else { return }
            app.tasks[i].state = .idle
            app.tasks[i].steps = []
            app.tasks[i].pillBadge = nil
        }
    }
}
