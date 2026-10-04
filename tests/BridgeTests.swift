// Pont Claude Code (lecture HTTP, fusion des hooks) et moteur de l'espace client, sans l'app.
//   scripts/test-bridge.sh
import Foundation

@main
struct BridgeTests {
    static func main() {
        var failures = 0
        func expect(_ c: Bool, _ m: String) { print((c ? "  ✓ " : "  ✗ ") + m); if !c { failures += 1 } }

        print("Lecture HTTP")
        let body = #"{"session_id":"s1","tool_name":"Bash"}"#
        let raw = "POST /hook/PreToolUse HTTP/1.1\r\nHost: 127.0.0.1\r\nX-Oli-Token: abc\r\nContent-Length: \(body.utf8.count)\r\n\r\n" + body
        let r = HTTPRequest(Data(raw.utf8))
        expect(r?.method == "POST" && r?.path == "/hook/PreToolUse", "ligne de requête lue")
        expect(r?.headers["x-oli-token"] == "abc", "en-têtes en minuscules")
        expect(r.map { String(decoding: $0.body, as: UTF8.self) } == body, "corps lu selon Content-Length")
        expect(HTTPRequest(Data(raw.dropLast(5).utf8)) == nil, "corps incomplet : on attend la suite")
        expect(HTTPRequest(Data("POST /x HTTP/1.1\r\nContent-Le".utf8)) == nil, "en-têtes incomplets : on attend la suite")

        print("Hooks Claude Code")
        let other: [String: Any] = ["type": "command", "command": "~/bin/mon-hook.sh"]
        let settings: [String: Any] = ["model": "opus", "hooks": ["PreToolUse": [["matcher": "Bash", "hooks": [other]]]]]
        let installed = HookInstaller.merged(settings, install: true)
        let hooks = installed["hooks"] as? [String: Any] ?? [:]
        expect(installed["model"] as? String == "opus", "réglages sans rapport conservés")
        expect(HookInstaller.events.allSatisfy { hooks[$0] != nil }, "une entrée Oli pour chacun des \(HookInstaller.events.count) événements")
        let pre = hooks["PreToolUse"] as? [[String: Any]] ?? []
        expect(pre.count == 2 && (pre[0]["hooks"] as? [[String: Any]])?.first?["command"] as? String == "~/bin/mon-hook.sh", "hook d’un autre outil gardé tel quel")
        let perm = ((hooks["PermissionRequest"] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]])?.first
        expect(perm?["timeout"] as? Int == 120 && HookInstaller.isOli(perm?["command"] as? String), "autorisation : relais Oli, délai 120 s")
        let twice = HookInstaller.merged(installed, install: true)
        expect(((twice["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]])?.count == 1, "réinstaller ne duplique pas")
        let removed = HookInstaller.merged(installed, install: false)
        let rh = removed["hooks"] as? [String: Any] ?? [:]
        expect(rh.keys.sorted() == ["PreToolUse"] && (rh["PreToolUse"] as? [[String: Any]])?.count == 1, "désinstaller ne laisse que l’autre hook")
        expect(!HookInstaller.isOli("policy-check.sh") && HookInstaller.isOli("\"$HOME/.claude/oli/oli-hook\" Stop"), "détection précise du relais")
        expect(HookInstaller.script.contains("exit 0") && HookInstaller.script.contains("--max-time"), "le relais sort toujours et ne bloque pas")

        print("Espace client")
        let json = #"""
        {"clients":[
          {"id":"a","name":"Garage","kind":"refonte","progress":50,"dueAt":"2020-01-01","archived":false,"liveUrl":"https://g.test",
           "steps":[{"label":"Brief","state":"done","doneAt":"2020-01-01T10:00:00.000Z"},{"label":"Maquette","state":"doing"}],
           "updates":[{"author":"Tom","body":"Hello","createdAt":"2020-01-02T10:00:00Z"}],"createdAt":"2019-12-01T10:00:00Z"},
          {"id":"b","name":"Archivé","archived":true},
          {"id":"c","name":"Atelier","kind":"creation","steps":[]}
        ]}
        """#
        let ps = EspaceAPI.parse(Data(json.utf8), base: "https://espace.test")
        expect(ps.count == 2 && ps[0].name == "Garage", "projets lus, archivés écartés, retard en tête")
        expect(ps[0].isLate && ps[0].stepLabel == "Maquette" && ps[0].stepsDone == 1, "étape en cours et retard")
        expect(ps[0].notes.first?.author == "Tom" && ps[0].adminURL?.absoluteString == "https://espace.test/admin/a", "dernier mot et lien de fiche")
        expect(EspaceAPI.base("https://x.test/") == "https://x.test" && EspaceAPI.base(nil) == EspaceAPI.defaultBase, "adresse de l’espace")

        print(failures == 0 ? "\nOK" : "\n\(failures) échec(s)")
        exit(failures == 0 ? 0 : 1)
    }
}
