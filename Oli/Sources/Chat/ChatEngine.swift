import SwiftUI

// MARK: - Demander à Oli
// Claude API (Messages) with the studio's live state in the system prompt and a few tools Oli runs
// itself. The key lives in the Keychain (anthropic-api-key).

@MainActor
final class ChatEngine {
    static let shared = ChatEngine()
    static var modelId: String { UserDefaults.standard.string(forKey: "chatModel").flatMap { $0.isEmpty ? nil : $0 } ?? "claude-sonnet-5-5" }

    private var history: [[String: Any]] = []
    private var model: OliModel { .shared }

    func reset() { history = []; model.chat = [] }

    func send(_ text: String) {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !model.chatBusy else { return }
        guard let key = Secrets.shared[.anthropic] else {
            model.chat.append(ChatLine(who: .oli, text: "Il me faut une clé API Anthropic (Réglages → Connexions)."))
            return
        }
        model.chat.append(ChatLine(who: .me, text: q))
        history.append(["role": "user", "content": q])
        model.chatBusy = true
        Task {
            let answer = await self.run(key: key)
            self.model.chatBusy = false
            self.model.chat.append(ChatLine(who: .oli, text: answer))
        }
    }

    private var system: String {
        let name = BriefingDesk.firstName().map { " de \($0)" } ?? ""
        return """
        Tu es Oli, l’assistant d’Oculot Studio\(name), qui vit dans l’encoche du Mac. Oculot est un studio web de trois personnes \
        (Tom, Elliott, Tobias) en région PACA : refontes en un jour, créations en deux, pour des artisans, commerces et PME. \
        Ton : chaleureux, direct, un peu d’humour, zéro jargon ; « on » pour le studio, « vous » pour les clients. Réponds en français, \
        court et concret (l’encoche est petite), en Markdown léger.
        Appuie-toi sur l’état en direct ci-dessous et sur tes outils ; n’invente jamais un projet, un site ou un rendez-vous.

        \(Briefing.chatContext(BriefingDesk.facts()))
        """
    }

    private let tools: [[String: Any]] = [
        ["name": "projets", "description": "Projets de l’espace client : étapes, échéance, dernier mot au client, site, dépôt GitHub.",
         "input_schema": ["type": "object", "properties": [String: Any]()]],
        ["name": "sites", "description": "État détaillé des sites surveillés (HTTP, certificat, PageSpeed, domaine, liens cassés).",
         "input_schema": ["type": "object", "properties": [String: Any]()]],
        ["name": "verifier_sites", "description": "Relance tout de suite la vérification des sites.",
         "input_schema": ["type": "object", "properties": [String: Any]()]],
        ["name": "ouvrir_depot", "description": "Ouvre le dépôt local d’un client dans le terminal d’Oli et y lance Claude Code.",
         "input_schema": ["type": "object", "properties": ["client": ["type": "string"]], "required": ["client"]]],
    ]

    private func tool(_ name: String, _ input: [String: Any]) -> String {
        switch name {
        case "projets":
            if model.projects.isEmpty { return "Aucun projet (ou espace client non branché)." }
            return model.projects.map { p in
                var l = "- \(p.name) (\(p.kindLabel)) : \(p.stepLabel), \(p.stepsDone)/\(p.steps.count) étapes, échéance \(p.dueLabel), inactif depuis \(p.inactiveDays) j"
                if !p.liveUrl.isEmpty { l += ", site \(p.liveUrl)" }
                if !p.repo.isEmpty { l += ", dépôt \(p.repo)" }
                if let n = p.notes.first { l += ", dernier mot : « \(n.body.prefix(140)) »" }
                return l
            }.joined(separator: "\n")
        case "sites":
            if model.sites.isEmpty { return "Aucun site surveillé." }
            return model.sites.map { s in
                var l = "- \(s.name) (\(s.url)) : \(s.status.label), \(s.httpLabel), \(s.latencyLabel), \(s.tlsLabel)"
                if let a = model.siteAudits[s.url] { l += ", \(a.pagespeedLabel), \(a.domainLabel)" + (a.issues.isEmpty ? "" : ", problèmes : " + a.issues.joined(separator: ", ")) }
                return l
            }.joined(separator: "\n")
        case "verifier_sites":
            SitesWatcher.shared.refresh()
            return "Vérification lancée."
        case "ouvrir_depot":
            let q = (input["client"] as? String ?? "").lowercased()
            guard let p = model.projects.first(where: { $0.name.lowercased().contains(q) }), !q.isEmpty else { return "Client introuvable." }
            guard let dir = RepoFinder.localFolder(for: p.repo) else { return "Pas de clone local du dépôt de \(p.name)." }
            TerminalCommands.open(folder: dir, runClaude: true)
            return "Dépôt de \(p.name) ouvert dans le terminal, Claude Code lancé."
        default:
            return "Outil inconnu."
        }
    }

    /// Request loop: answers tool calls until the model writes text (4 rounds max).
    private func run(key: String) async -> String {
        let start = history.count
        for _ in 0..<5 {
            let body: [String: Any] = ["model": Self.modelId, "max_tokens": 1500, "system": system,
                                       "tools": tools, "messages": history]
            guard let data = try? JSONSerialization.data(withJSONObject: body) else { return "Erreur interne." }
            var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!, timeoutInterval: 60)
            req.httpMethod = "POST"
            req.setValue(key, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            req.setValue("application/json", forHTTPHeaderField: "content-type")
            req.httpBody = data
            guard let (out, resp) = try? await URLSession.shared.data(for: req),
                  let json = try? JSONSerialization.jsonObject(with: out) as? [String: Any] else {
                history.removeSubrange(start...)
                return "Je n’arrive pas à joindre Claude. Réessaie dans un instant."
            }
            if (resp as? HTTPURLResponse)?.statusCode != 200 {
                history.removeSubrange(start...)
                let msg = ((json["error"] as? [String: Any])?["message"] as? String) ?? "erreur"
                return "Claude a répondu : \(msg)"
            }
            let content = json["content"] as? [[String: Any]] ?? []
            let calls = content.filter { $0["type"] as? String == "tool_use" }
            if (json["stop_reason"] as? String) == "tool_use", !calls.isEmpty {
                history.append(["role": "assistant", "content": content])
                history.append(["role": "user", "content": calls.map { c in
                    ["type": "tool_result", "tool_use_id": c["id"] as? String ?? "",
                     "content": tool(c["name"] as? String ?? "", c["input"] as? [String: Any] ?? [:])] as [String: Any]
                }])
                continue
            }
            let text = content.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
            history.append(["role": "assistant", "content": text.isEmpty ? "…" : text])
            return text.isEmpty ? "…" : text
        }
        history.removeSubrange(start...)
        return "Je me suis perdu dans mes outils, reformule ta question ?"
    }
}

struct ChatSection: View {
    @EnvironmentObject var model: OliModel
    @State private var input = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 8) {
                        if model.chat.isEmpty {
                            EmptyNote(icon: "bubble.left.and.text.bubble.right", text: "Demande-moi où en est un projet, quel site pose problème, ce qu’il y a demain…")
                        }
                        ForEach(model.chat) { line in
                            HStack {
                                if line.who == .me { Spacer(minLength: 60) }
                                Text(markdown(line.text))
                                    .font(Typo.text(12.5)).foregroundStyle(line.who == .me ? Palette.night : Palette.cream)
                                    .textSelection(.enabled)
                                    .padding(.horizontal, 11).padding(.vertical, 7)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(line.who == .me ? Palette.beurre : Palette.card))
                                if line.who == .oli { Spacer(minLength: 40) }
                            }
                            .id(line.id)
                        }
                        if model.chatBusy { Text("Oli réfléchit…").font(Typo.text(11.5)).foregroundStyle(Palette.sand).id("busy") }
                    }
                }
                .onChange(of: model.chat.count) { _, _ in withAnimation { proxy.scrollTo(model.chat.last?.id, anchor: .bottom) } }
            }
            HStack(spacing: 8) {
                TextField("Écris à Oli…", text: $input)
                    .textFieldStyle(.plain).font(Typo.text(13)).foregroundStyle(Palette.cream)
                    .focused($focused)
                    .onSubmit { ChatEngine.shared.send(input); input = "" }
                Button { ChatEngine.shared.reset() } label: { Image(systemName: "arrow.counterclockwise") }
                    .buttonStyle(.plain).foregroundStyle(Palette.dust).help("Nouvelle conversation")
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 12).fill(Palette.card))
        }
        .onAppear { model.holdOpen = true; focused = true }
        .onDisappear { model.holdOpen = false }
    }
}

func markdown(_ s: String) -> AttributedString {
    (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
}
