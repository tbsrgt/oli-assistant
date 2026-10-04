import Foundation

// MARK: - Instagram Oculot (phase 5a)
// Every 30 minutes (first read 30 s after launch) reads the Instagram account with the token from
// the Keychain ("instagram-token", optional "instagram-user-id"). Fills AppState.social and raises
// the integration_instagram pill once per new reminder (unanswered comments, quiet account).

@MainActor
final class SocialPoller {
    static let shared = SocialPoller()
    static let pillId = "integration_instagram"
    static let interval: TimeInterval = 1800

    private var timer: Timer?
    private var running = false
    /// Reminders already announced (UserDefaults "socialAlerted"), so a relaunch does not repeat them.
    private var alerted: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "socialAlerted") ?? []) {
        didSet { UserDefaults.standard.set(Array(alerted), forKey: "socialAlerted") }
    }

    private init() {}

    static var isConfigured: Bool { KeychainStore.shared.get("instagram-token") != nil }

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: Self.interval, repeats: true) { _ in
            Task { @MainActor in SocialPoller.shared.refreshNow() }
        }
        t.tolerance = 120
        RunLoop.main.add(t, forMode: .common)
        timer = t
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in self?.refreshNow() }
    }

    func refreshNow() {
        guard !running else { return }
        guard let token = KeychainStore.shared.get("instagram-token"), !token.isEmpty else {
            AppState.shared.social = nil
            return
        }
        running = true
        let manual = KeychainStore.shared.get("instagram-user-id")
        Task { @MainActor [weak self] in
            let snap = await SocialFetcher.fetch(token: token, accountId: manual)
            self?.handle(snap)
        }
    }

    private func handle(_ snap: SocialSnapshot) {
        running = false
        let app = AppState.shared
        app.social = snap
        guard let idx = app.tasks.firstIndex(where: { $0.id == Self.pillId }) else { return }

        // Unanswered comments: keyed by comment ids, so only a new comment is announced again.
        // Quiet account: keyed without the number of days, so it is announced once, not every day.
        var keyed: [(key: String, text: String)] = []
        let ids = snap.unanswered.map(\.id).sorted().joined(separator: ",")
        for r in snap.reminders() {
            keyed.append((r.contains("commentaire") ? "comments|\(ids)" : SitesPoller.issueKey(r), r))
        }
        let fresh = keyed.filter { alerted.insert($0.key).inserted }.map(\.text)
        alerted = alerted.filter { k in keyed.contains { $0.key == k } }
        guard !fresh.isEmpty else { return }

        app.tasks[idx].state = .question
        app.tasks[idx].steps = fresh.map { "Instagram : \($0)" }
        if app.focusId != Self.pillId { app.tasks[idx].pillBadge = .approval }
        SoundEngine.shared.play("question")
        NotificationCenter.default.post(name: .hookReveal, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
            guard let i = app.tasks.firstIndex(where: { $0.id == Self.pillId }), app.tasks[i].state == .question else { return }
            app.tasks[i].state = .idle
            app.tasks[i].steps = []
            app.tasks[i].pillBadge = nil
        }
    }
}
