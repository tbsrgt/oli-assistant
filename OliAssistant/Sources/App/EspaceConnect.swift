import AppKit

// MARK: - Espace client : connexion en un clic
// « Se connecter » ouvre espace.oculot.studio/admin/oli dans le navigateur. Une fois l'équipe
// connectée à l'admin, la page renvoie vers `oli://connect?service=espace&url=…&token=…` :
// Oli vérifie le jeton, le range dans le Trousseau et se met à jour. Rien à copier-coller.
//
// Un lien oli:// peut venir de n'importe quelle page web : on n'accepte que l'espace par défaut,
// celui déjà configuré, ou localhost en Debug, et le jeton doit être accepté par l'espace.

@MainActor
enum EspaceConnect {
    /// Page de l'admin qui renvoie vers Oli avec le jeton d'équipe.
    static var startURL: URL { URL(string: EspacePoller.defaultBaseURL + "/admin/oli")! }

    static func start() {
        NSWorkspace.shared.open(startURL)
    }

    /// Hôtes dont Oli accepte un lien de connexion.
    static func allowed(_ base: URL) -> Bool {
        guard let host = base.host?.lowercased() else { return false }
        #if DEBUG
        if base.scheme == "http" && (host == "localhost" || host == "127.0.0.1") { return true }
        #endif
        guard base.scheme == "https" else { return false }
        let known = [EspacePoller.defaultBaseURL, EspacePoller.baseURL].compactMap { URL(string: $0)?.host?.lowercased() }
        return known.contains(host)
    }

    /// `oli://connect?service=espace&url=https://espace.oculot.studio&token=…`
    static func handle(_ link: URL) {
        let items = URLComponents(url: link, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let q = { (name: String) in items.first { $0.name == name }?.value ?? "" }
        guard q("service") == "espace" else { return }
        let token = q("token").trimmingCharacters(in: .whitespacesAndNewlines)
        var raw = q("url").trimmingCharacters(in: .whitespacesAndNewlines)
        while raw.hasSuffix("/") { raw.removeLast() }
        guard !token.isEmpty, let base = URL(string: raw), allowed(base) else {
            fail("Ce lien de connexion ne vient pas de l’espace Oculot.")
            return
        }
        Task {
            guard let url = URL(string: raw + "/api/espace/summary") else { return }
            var req = URLRequest(url: url, timeoutInterval: 15)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let code = (try? await URLSession.shared.data(for: req)).flatMap { ($0.1 as? HTTPURLResponse)?.statusCode }
            guard code == 200 else {
                fail(code == 401 ? "L’espace a refusé le jeton. Réessaie depuis Oli → Connexions." : "L’espace ne répond pas. Réessaie dans un instant.")
                return
            }
            let k = KeychainStore.shared
            k.set("espace-token", value: token)
            if raw == EspacePoller.defaultBaseURL { k.remove("espace-url") } else { k.set("espace-url", value: raw) }
            EspacePoller.shared.pollNow()
            AppState.shared.activatePill("integration_espace")
            SoundEngine.shared.play("approve")
            show(.finished, "Connecté à l’espace client")
            NotificationCenter.default.post(name: .oliConnectionsChanged, object: nil)
            appendAppLog("oli.log", "Espace client connecté en un clic (\(base.host ?? raw))")
            SystemNotify.post(title: "Oli est connecté à l’espace client", body: "Projets, échéances et suivi des sites arrivent dans l’encoche.", id: "espace-connect")
        }
    }

    /// Oli confirms in the notch itself: system notifications may be turned off.
    private static func show(_ state: BotState, _ text: String) {
        let app = AppState.shared
        guard let i = app.tasks.firstIndex(where: { $0.id == "integration_espace" }) else { return }
        app.tasks[i].state = state
        app.tasks[i].steps = [text]
        NotificationCenter.default.post(name: .hookReveal, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            guard let j = app.tasks.firstIndex(where: { $0.id == "integration_espace" }), app.tasks[j].steps == [text] else { return }
            app.tasks[j].state = .idle
            app.tasks[j].steps = []
        }
    }

    private static func fail(_ text: String) {
        SoundEngine.shared.play("error")
        show(.error, text)
        appendAppLog("oli.log", "Connexion à l’espace refusée : \(text)")
        SystemNotify.post(title: "Connexion à l’espace impossible", body: text, id: "espace-connect-error")
    }
}

extension Notification.Name {
    /// A service was connected from outside the Settings sheet (oli:// link): refresh the rows.
    static let oliConnectionsChanged = Notification.Name("studio.oculot.oli.connectionsChanged")
}
