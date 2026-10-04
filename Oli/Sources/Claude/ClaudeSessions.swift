import SwiftUI

// MARK: - Sessions Claude Code
// Turns hook events into the sessions list and the approvals queue of the model.

@MainActor
final class ClaudeSessions {
    static let shared = ClaudeSessions()
    private var model: OliModel { .shared }
    private init() {}

    func event(_ e: HookEvent) {
        let p = e.payload
        let sid = p["session_id"] as? String ?? "?"
        var s = model.sessions.first { $0.id == sid } ?? newSession(sid, p, e.terminal)
        s.updatedAt = Date()
        switch e.name {
        case "SessionStart":
            s.phase = .idle; s.activity = "Prêt"
        case "UserPromptSubmit":
            s.phase = .working; s.activity = "Réfléchit…"
        case "PreToolUse":
            s.phase = .working; s.activity = Self.describe(tool: p["tool_name"] as? String, input: p["tool_input"])
        case "PostToolUse":
            s.phase = .working
        case "Notification":
            s.phase = .waiting
            s.activity = (p["message"] as? String).map { Self.short($0, 70) } ?? "Attend ta réponse"
            Chimes.shared.play(.attention)
            if !model.expanded { model.say("\(s.project) attend ta réponse", tint: Palette.lilas) }
        case "Stop":
            s.phase = .done; s.activity = "Terminé"
            Chimes.shared.play(.done)
            model.celebrate()
            if !model.expanded { model.say("Claude a fini · \(s.project)", tint: Palette.menthe) }
        case "SessionEnd":
            model.sessions.removeAll { $0.id == sid }
            model.approvals.removeAll { $0.sessionId == sid }
            return
        default:
            break
        }
        upsert(s)
    }

    func permission(_ e: HookEvent, approvalId: String) {
        let p = e.payload
        let sid = p["session_id"] as? String ?? "?"
        var s = model.sessions.first { $0.id == sid } ?? newSession(sid, p, e.terminal)
        let tool = p["tool_name"] as? String ?? "Outil"
        s.phase = .waiting
        s.activity = "Demande : " + Self.describe(tool: tool, input: p["tool_input"])
        s.updatedAt = Date()
        upsert(s)
        model.approvals.append(Approval(id: approvalId, sessionId: sid, project: s.project, tool: tool,
                                        summary: Self.describe(tool: tool, input: p["tool_input"]),
                                        detail: Self.detail(tool: tool, input: p["tool_input"]), createdAt: Date()))
        Chimes.shared.play(.attention)
        model.open(.claude)
    }

    func answer(_ a: Approval, allow: Bool?) {
        ClaudeBridge.shared.decide(a.id, allow: allow)
        dropApproval(a.id)
        if let i = model.sessions.firstIndex(where: { $0.id == a.sessionId }) {
            model.sessions[i].phase = allow == false ? .idle : .working
            model.sessions[i].activity = allow == true ? "Autorisé · \(a.summary)" : allow == false ? "Refusé" : "Réponse dans le terminal"
        }
        Chimes.shared.play(.tick)
    }

    func dropApproval(_ id: String) { model.approvals.removeAll { $0.id == id } }

    // MARK: Helpers

    private func upsert(_ s: ClaudeSession) {
        if let i = model.sessions.firstIndex(where: { $0.id == s.id }) { model.sessions[i] = s }
        else { model.sessions.insert(s, at: 0) }
        // Forget sessions silent for 6 h (closed terminals that never sent SessionEnd)
        model.sessions.removeAll { Date().timeIntervalSince($0.updatedAt) > 6 * 3600 }
    }

    private func newSession(_ id: String, _ p: [String: Any], _ term: String) -> ClaudeSession {
        let cwd = p["cwd"] as? String ?? ""
        let project = cwd.isEmpty ? "Session" : URL(fileURLWithPath: cwd).lastPathComponent
        return ClaudeSession(id: id, project: project, cwd: cwd, terminal: Self.terminalName(term),
                             phase: .idle, activity: "Prêt", updatedAt: Date())
    }

    static func terminalName(_ t: String) -> String {
        switch t.lowercased() {
        case "oli": return "Oli"
        case "apple_terminal": return "Terminal"
        case "iterm.app": return "iTerm"
        case "vscode": return "VS Code"
        case "ghostty": return "Ghostty"
        case "warpterminal": return "Warp"
        case "": return "Terminal"
        default: return t
        }
    }

    static func describe(tool: String?, input: Any?) -> String {
        let tool = tool ?? "Outil"
        let i = input as? [String: Any] ?? [:]
        if let cmd = i["command"] as? String { return "\(tool) · " + short(cmd, 60) }
        if let f = i["file_path"] as? String { return "\(tool) · " + URL(fileURLWithPath: f).lastPathComponent }
        if let u = i["url"] as? String { return "\(tool) · " + short(u, 50) }
        if let d = i["description"] as? String { return "\(tool) · " + short(d, 50) }
        if let q = i["pattern"] as? String { return "\(tool) · " + short(q, 50) }
        return tool
    }

    static func detail(tool: String, input: Any?) -> String {
        let i = input as? [String: Any] ?? [:]
        if let cmd = i["command"] as? String { return cmd }
        if let f = i["file_path"] as? String {
            if let n = i["new_string"] as? String { return f + "\n\n" + short(n, 600) }
            if let c = i["content"] as? String { return f + "\n\n" + short(c, 600) }
            return f
        }
        guard let d = try? JSONSerialization.data(withJSONObject: i, options: [.prettyPrinted, .sortedKeys]) else { return tool }
        return short(String(decoding: d, as: UTF8.self), 600)
    }

    static func short(_ s: String, _ n: Int) -> String {
        let one = s.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        return one.count > n ? String(one.prefix(n - 1)) + "…" : one
    }
}
