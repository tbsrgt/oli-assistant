import Foundation

// MARK: - Installation des hooks Claude Code
// Writes the relay script to ~/.claude/oli/oli-hook and adds Oli's entries to
// ~/.claude/settings.json. Never overwrites blindly: dated backup, merge, preview, write on click.

enum HookInstaller {
    static let events = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
                         "Notification", "Stop", "SessionEnd", "PermissionRequest"]

    static var claudeDir: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude") }
    static var scriptURL: URL { claudeDir.appendingPathComponent("oli/oli-hook") }
    static var settingsURL: URL { claudeDir.appendingPathComponent("settings.json") }

    static let script = """
    #!/bin/sh
    # Oli — relais des hooks Claude Code vers l'encoche du Mac (Oli Assistant, Oculot Studio).
    # Ne bloque jamais Claude Code : si Oli n'est pas lancé, le script sort tout de suite.
    CONF="$HOME/Library/Application Support/Oli/bridge"
    if [ ! -r "$CONF" ]; then cat >/dev/null; exit 0; fi
    . "$CONF"
    WAIT=3
    [ "$1" = "PermissionRequest" ] && WAIT=118
    curl -s --max-time "$WAIT" --connect-timeout 1 \\
      -H "X-Oli-Token: $OLI_TOKEN" -H "X-Oli-Term: ${TERM_PROGRAM:-}" -H "Content-Type: application/json" \\
      --data-binary @- "http://127.0.0.1:$OLI_PORT/hook/$1" 2>/dev/null
    exit 0
    """

    /// True for a command that runs Oli's relay script.
    static func isOli(_ command: String?) -> Bool { command?.contains("/.claude/oli/oli-hook") == true }

    static func command(for event: String) -> String { "\"$HOME/.claude/oli/oli-hook\" \(event)" }

    static func readSettings() -> [String: Any] {
        guard let d = try? Data(contentsOf: settingsURL),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [:] }
        return j
    }

    static func isInstalled() -> Bool {
        guard let hooks = readSettings()["hooks"] as? [String: Any] else { return false }
        return events.allSatisfy { ev in
            ((hooks[ev] as? [[String: Any]]) ?? []).contains { group in
                ((group["hooks"] as? [[String: Any]]) ?? []).contains { isOli($0["command"] as? String) }
            }
        }
    }

    /// settings.json with Oli's entries added (install) or removed (uninstall), other hooks untouched.
    static func merged(install: Bool) -> [String: Any] { merged(readSettings(), install: install) }

    /// Pure merge, testable on any settings dictionary.
    static func merged(_ settings: [String: Any], install: Bool) -> [String: Any] {
        var root = settings
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for ev in events {
            var groups = (hooks[ev] as? [[String: Any]]) ?? []
            groups = groups.compactMap { g in
                var g = g
                let inner = ((g["hooks"] as? [[String: Any]]) ?? []).filter { !isOli($0["command"] as? String) }
                if inner.isEmpty && g["hooks"] != nil { return nil }
                g["hooks"] = inner
                return g
            }
            if install {
                var h: [String: Any] = ["type": "command", "command": command(for: ev)]
                if ev == "PermissionRequest" { h["timeout"] = 120 }
                groups.append(["matcher": "", "hooks": [h]])
            }
            if groups.isEmpty { hooks.removeValue(forKey: ev) } else { hooks[ev] = groups }
        }
        if hooks.isEmpty { root.removeValue(forKey: "hooks") } else { root["hooks"] = hooks }
        return root
    }

    static func pretty(_ j: [String: Any]) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: j, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { return "{}" }
        return String(decoding: d, as: UTF8.self)
    }

    /// Lines that change, for the preview (« + » added, « − » removed).
    static func preview(install: Bool) -> String {
        let before = Set(pretty(readSettings()).components(separatedBy: "\n"))
        let afterLines = pretty(merged(install: install)).components(separatedBy: "\n")
        let after = Set(afterLines)
        let added = afterLines.filter { !before.contains($0) }.map { "+ " + $0.trimmingCharacters(in: .whitespaces) }
        let removed = pretty(readSettings()).components(separatedBy: "\n").filter { !after.contains($0) }
            .map { "− " + $0.trimmingCharacters(in: .whitespaces) }
        let lines = removed + added
        return lines.isEmpty ? "Aucun changement." : lines.joined(separator: "\n")
    }

    /// Backup, then write. Returns the backup path.
    @discardableResult
    static func apply(install: Bool) throws -> String {
        let fm = FileManager.default
        try fm.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"
        let backup = claudeDir.appendingPathComponent("settings.json.oli-\(f.string(from: Date())).bak")
        if fm.fileExists(atPath: settingsURL.path) { try fm.copyItem(at: settingsURL, to: backup) }
        if install {
            try fm.createDirectory(at: scriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        }
        let data = try JSONSerialization.data(withJSONObject: merged(install: install),
                                              options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: settingsURL, options: .atomic)
        return backup.path
    }
}
