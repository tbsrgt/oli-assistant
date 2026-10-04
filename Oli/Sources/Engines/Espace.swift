import Foundation

// MARK: - Espace client Oculot (espace.oculot.studio)
// Reads GET /api/espace/summary with the team token. Pure model + parsing + one fetch.

struct EspaceStep: Sendable, Equatable { let label: String; let state: String; let doneAt: Date? }
struct EspaceNote: Sendable, Equatable { let author: String; let body: String; let at: Date }

struct EspaceProject: Identifiable, Sendable, Equatable {
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
    let steps: [EspaceStep]
    let notes: [EspaceNote]
    let adminURL: URL?

    var currentStep: EspaceStep? { steps.first { $0.state == "doing" } ?? steps.first { $0.state == "todo" } }
    var stepsDone: Int { steps.filter { $0.state == "done" }.count }
    var isDone: Bool { !steps.isEmpty && stepsDone == steps.count }
    var stepLabel: String { currentStep?.label ?? (isDone ? "Terminé" : "Pas d’étape") }
    var inactiveDays: Int { Int(Date().timeIntervalSince(lastActivityAt ?? createdAt) / 86400) }
    var isNew: Bool { Date().timeIntervalSince(createdAt) < 7 * 86400 }
    var isLate: Bool { !isDone && (daysLeft ?? 0) < 0 }
    var doneThisWeek: [String] {
        let since = Date().addingTimeInterval(-7 * 86400)
        return steps.filter { $0.state == "done" && ($0.doneAt ?? .distantPast) >= since }.map(\.label)
    }
    var kindLabel: String {
        switch kind { case "refonte": return "Refonte"; case "creation": return "Création"; default: return "Sur-mesure" }
    }
    var dueLabel: String {
        guard let d = daysLeft else { return "sans date" }
        if d < 0 { return "en retard de \(-d) j" }
        if d == 0 { return "aujourd’hui" }
        if d == 1 { return "demain" }
        return "dans \(d) j"
    }
}

enum EspaceAPI {
    static let defaultBase = "https://espace.oculot.studio"

    static func base(_ custom: String?) -> String {
        let b = (custom ?? "").trimmingCharacters(in: .whitespaces)
        let base = b.isEmpty ? defaultBase : b
        return base.hasSuffix("/") ? String(base.dropLast()) : base
    }

    enum Result: Sendable { case ok([EspaceProject]), failed(String) }

    static func fetch(token: String, base: String) async -> Result {
        guard let url = URL(string: base + "/api/espace/summary") else { return .failed("adresse invalide") }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, resp) = try? await URLSession.shared.data(for: req) else { return .failed("espace injoignable") }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { return .failed("jeton refusé") }
        guard code == 200 else { return .failed("réponse \(code)") }
        return .ok(parse(data, base: base))
    }

    static func parse(_ data: Data, base: String, now: Date = Date()) -> [EspaceProject] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = json["clients"] as? [[String: Any]] else { return [] }
        return raw.compactMap { project($0, base: base, now: now) }
            .sorted { ($0.daysLeft ?? 9999) < ($1.daysLeft ?? 9999) }
    }

    static func project(_ d: [String: Any], base: String, now: Date) -> EspaceProject? {
        guard let id = d["id"] as? String, let name = d["name"] as? String else { return nil }
        if (d["archived"] as? Bool) == true { return nil }
        let steps = ((d["steps"] as? [[String: Any]]) ?? []).compactMap { s -> EspaceStep? in
            guard let label = s["label"] as? String else { return nil }
            return EspaceStep(label: label, state: s["state"] as? String ?? "todo", doneAt: date(s["doneAt"]))
        }
        let notes = ((d["updates"] as? [[String: Any]]) ?? []).compactMap { u -> EspaceNote? in
            guard let body = u["body"] as? String else { return nil }
            return EspaceNote(author: u["author"] as? String ?? "", body: body, at: date(u["createdAt"]) ?? .distantPast)
        }.sorted { $0.at > $1.at }
        let dueAt = d["dueAt"] as? String
        return EspaceProject(
            id: id, name: name,
            contact: d["contact"] as? String ?? "",
            kind: d["kind"] as? String ?? "",
            progress: (d["progress"] as? NSNumber)?.intValue ?? 0,
            dueAt: dueAt, daysLeft: daysLeft(dueAt, now: now),
            liveUrl: d["liveUrl"] as? String ?? "",
            previewUrl: d["previewUrl"] as? String ?? "",
            repo: d["repo"] as? String ?? "",
            lastActivityAt: date(d["lastActivityAt"]),
            createdAt: date(d["createdAt"]) ?? now,
            steps: steps, notes: notes,
            adminURL: URL(string: base + "/admin/" + id))
    }

    /// Whole days from today to a "YYYY-MM-DD" due date (local calendar).
    static func daysLeft(_ due: String?, now: Date) -> Int? {
        guard let due, due.count >= 10 else { return nil }
        let p = due.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, let day = Calendar.current.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12)) else { return nil }
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: day)).day
    }

    static func date(_ v: Any?) -> Date? {
        guard let s = v as? String else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}
