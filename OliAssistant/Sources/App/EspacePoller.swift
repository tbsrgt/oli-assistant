import Foundation

// MARK: - Espace client Oculot
// Polls espace.oculot.studio/api/espace/summary every 5 minutes (team token in the Keychain).
// Fills AppState.espaceClients / espaceAlerts and raises the pill when something needs the team.

struct EspaceStep { let label: String; let state: String }
struct EspaceUpdate { let author: String; let body: String; let createdAt: Date }

enum EspaceUrgency {
    case late, hot, soon, calm, done
    var hex: String {
        switch self {
        case .late: return "#F4505E"
        case .hot:  return "#FF5B37"
        case .soon: return "#FFD65C"
        case .calm: return "#22C55E"
        case .done: return "#8E939C"
        }
    }
}

struct EspaceClient: Identifiable {
    let id: String
    let name: String
    let contact: String
    let kind: String
    let progress: Int
    let dueAt: String?
    let daysLeft: Int?
    let liveUrl: String
    let previewUrl: String
    let repo: String
    let lastActivityAt: Date?
    let createdAt: Date
    let currentStep: EspaceStep?
    let stepsDone: Int
    let stepsTotal: Int
    let lastUpdate: EspaceUpdate?
    let adminUrl: String
    /// Labels of the steps completed in the last 7 days (Friday recap).
    var recentlyDone: [String] = []

    var isDone: Bool { stepsTotal > 0 && stepsDone == stepsTotal }
    var urgency: EspaceUrgency {
        if isDone { return .done }
        guard let d = daysLeft else { return .calm }
        if d < 0 { return .late }
        if d <= 3 { return .hot }
        if d <= 7 { return .soon }
        return .calm
    }
    var daysLabel: String {
        guard let d = daysLeft else { return "sans date" }
        if d < 0 { return "J+\(-d)" }
        if d == 0 { return "aujourd’hui" }
        return "J-\(d)"
    }
    var inactiveDays: Int { Int(Date().timeIntervalSince(lastActivityAt ?? createdAt) / 86400) }
    var kindLabel: String {
        switch kind {
        case "refonte":  return "Refonte"
        case "creation": return "Création"
        default:         return "Sur-mesure"
        }
    }
    var stepLabel: String { currentStep?.label ?? (isDone ? "Terminé" : "Pas d’étape") }
}

struct EspaceAlert: Identifiable {
    enum Kind { case due, inactive, newClient }
    let id: String
    let clientId: String
    let kind: Kind
    let text: String
}

final class EspacePoller: @unchecked Sendable {
    static let shared = EspacePoller()
    static let defaultBaseURL = "https://espace.oculot.studio"

    static var baseURL: String {
        let custom = (KeychainStore.shared.get("espace-url") ?? "").trimmingCharacters(in: .whitespaces)
        let base = custom.isEmpty ? defaultBaseURL : custom
        return base.hasSuffix("/") ? String(base.dropLast()) : base
    }
    static var adminURL: URL { URL(string: baseURL + "/admin")! }

    private var timer: DispatchSourceTimer?
    private var knownIds: Set<String>? = nil     // nil until the first successful poll
    private var alertedKeys: Set<String> = []

    private init() {}

    func start() {
        guard timer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: .global(qos: .background))
        t.schedule(deadline: .now() + 4, repeating: 300)
        t.setEventHandler { [weak self] in self?.poll() }
        t.resume()
        timer = t
    }

    /// Immediate refresh (after the token is saved in Settings).
    func pollNow() {
        DispatchQueue.global(qos: .background).async { [weak self] in self?.poll() }
    }

    // MARK: - Poll

    private func poll() {
        guard let token = KeychainStore.shared.get("espace-token"), !token.isEmpty else { return }
        guard let url = URL(string: Self.baseURL + "/api/espace/summary") else { return }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: req) { [weak self] data, response, _ in
            guard let self else { return }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            DispatchQueue.main.async { AppState.shared.espaceLastStatus = code }
            guard let data, code == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let raw = json["clients"] as? [[String: Any]] else { return }
            let clients = raw.compactMap { Self.parse($0) }
                .sorted { ($0.daysLeft ?? 9999) < ($1.daysLeft ?? 9999) }
            DispatchQueue.main.async { self.handle(clients) }
        }.resume()
    }

    private static func date(_ v: Any?) -> Date? {
        guard let s = v as? String else { return nil }
        let frac = ISO8601DateFormatter(); frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return frac.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
    private static func int(_ v: Any?) -> Int? { (v as? NSNumber)?.intValue }

    private static func parse(_ d: [String: Any]) -> EspaceClient? {
        guard let id = d["id"] as? String, let name = d["name"] as? String else { return nil }
        if (d["archived"] as? Bool) == true { return nil }
        // Steps: the current one is the first "doing", else the first "todo" (server order = position)
        let steps = (d["steps"] as? [[String: Any]]) ?? []
        let doing = steps.first { ($0["state"] as? String) == "doing" }
        let todo  = steps.first { ($0["state"] as? String) == "todo" }
        let cur = doing ?? todo
        let currentStep = cur.flatMap { s in (s["label"] as? String).map { EspaceStep(label: $0, state: s["state"] as? String ?? "todo") } }
        let done = steps.filter { ($0["state"] as? String) == "done" }.count
        let weekAgo = Date().addingTimeInterval(-7 * 86400)
        let recentlyDone = steps.compactMap { s -> String? in
            guard (s["state"] as? String) == "done", let at = date(s["doneAt"]), at >= weekAgo else { return nil }
            return s["label"] as? String
        }
        // Updates: most recent first
        let updates = ((d["updates"] as? [[String: Any]]) ?? [])
            .compactMap { u -> EspaceUpdate? in
                guard let body = u["body"] as? String else { return nil }
                return EspaceUpdate(author: u["author"] as? String ?? "", body: body, createdAt: date(u["createdAt"]) ?? .distantPast)
            }
            .sorted { $0.createdAt > $1.createdAt }
        // Due date → days left (local calendar, noon to dodge DST)
        var daysLeft: Int? = nil
        let dueAt = d["dueAt"] as? String
        if let dueAt, dueAt.count == 10 {
            let parts = dueAt.split(separator: "-").compactMap { Int($0) }
            if parts.count == 3, let due = Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)) {
                let today = Calendar.current.startOfDay(for: Date())
                daysLeft = Calendar.current.dateComponents([.day], from: today, to: Calendar.current.startOfDay(for: due)).day
            }
        }
        return EspaceClient(
            id: id, name: name,
            contact: d["contact"] as? String ?? "",
            kind: d["kind"] as? String ?? "",
            progress: int(d["progress"]) ?? 0,
            dueAt: dueAt,
            daysLeft: daysLeft,
            liveUrl: d["liveUrl"] as? String ?? "",
            previewUrl: d["previewUrl"] as? String ?? "",
            repo: d["repo"] as? String ?? "",
            lastActivityAt: date(d["lastActivityAt"]),
            createdAt: date(d["createdAt"]) ?? Date(),
            currentStep: currentStep,
            stepsDone: done,
            stepsTotal: steps.count,
            lastUpdate: updates.first,
            adminUrl: baseURL + "/admin/" + id,
            recentlyDone: recentlyDone)
    }

    // MARK: - Alerts

    @MainActor
    private func handle(_ clients: [EspaceClient]) {
        // Delivered sites can make the sites pill appear (only connected pills are shown).
        defer { DispatchQueue.main.async { AppState.shared.loadIntegrationTasks() } }
        let app = AppState.shared
        app.espaceClients = clients
        app.espaceLastSync = Date()

        var alerts: [EspaceAlert] = []
        let firstRun = knownIds == nil
        for c in clients where !c.isDone {
            if let d = c.daysLeft, d <= 7 {
                let text = d < 0 ? "\(c.name) : mise en ligne dépassée de \(-d) j"
                         : d == 0 ? "\(c.name) : mise en ligne aujourd’hui"
                         : "\(c.name) : mise en ligne dans \(d) j"
                alerts.append(EspaceAlert(id: "due-\(c.id)-\(c.dueAt ?? "")-\(min(d, 7))", clientId: c.id, kind: .due, text: text))
            }
            if c.inactiveDays >= 7 {
                alerts.append(EspaceAlert(id: "inactive-\(c.id)-\(c.inactiveDays / 7)", clientId: c.id, kind: .inactive,
                                          text: "\(c.name) : rien envoyé au client depuis \(c.inactiveDays) j"))
            }
            if !firstRun, let known = knownIds, !known.contains(c.id) {
                alerts.append(EspaceAlert(id: "new-\(c.id)", clientId: c.id, kind: .newClient, text: "Nouveau client : \(c.name)"))
            }
        }
        knownIds = Set(clients.map(\.id))
        app.espaceAlerts = alerts

        let fresh = alerts.filter { !alertedKeys.contains($0.id) }
        fresh.forEach { alertedKeys.insert($0.id) }
        guard !fresh.isEmpty, let idx = app.tasks.firstIndex(where: { $0.id == "integration_espace" }) else { return }
        let hasNew = fresh.contains { $0.kind == .newClient }
        app.tasks[idx].state = hasNew ? .finished : .question
        app.tasks[idx].steps = [fresh[0].text]
        if app.focusId != "integration_espace" {
            app.tasks[idx].pillBadge = hasNew ? .finished : .approval
        }
        SoundEngine.shared.play(hasNew ? "finish" : "question")
        NotificationCenter.default.post(name: .hookReveal, object: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
            guard let i = app.tasks.firstIndex(where: { $0.id == "integration_espace" }) else { return }
            guard app.tasks[i].state == .question || app.tasks[i].state == .finished else { return }
            app.tasks[i].state = .idle
            app.tasks[i].steps = []
            app.tasks[i].pillBadge = nil
        }
    }
}
