import SwiftUI
import AppKit

// MARK: - Connexions (Réglages)
// One row per service with its state and a « Se connecter » button. The sheet asks for the bare
// minimum (address + password, or one link / token), checks that it works, saves it in the
// Keychain and refreshes Oli. GitHub and Vercel can reuse the login already on this Mac.

enum ConnectionKind: String, CaseIterable, Identifiable {
    case email, espace, agenda, sites, phone, instagram, github, vercel, pagespeed
    var id: String { rawValue }

    var title: String {
        switch self {
        case .email: return "Email"
        case .espace: return "Espace client"
        case .agenda: return "Agenda"
        case .sites: return "Sites surveillés"
        case .phone: return "Téléphone"
        case .instagram: return "Instagram"
        case .github: return "GitHub"
        case .vercel: return "Vercel"
        case .pagespeed: return "PageSpeed"
        }
    }
    var why: String {
        switch self {
        case .email: return "Envoyer les fichiers déposés sur l’encoche"
        case .espace: return "espace.oculot.studio : projets, étapes, échéances"
        case .agenda: return "agenda.oculot.studio : rendez-vous, rappel 10 min avant"
        case .sites: return "Pannes, certificats, liens cassés"
        case .phone: return "Oli Android : Claude depuis ton téléphone, via ce Mac"
        case .instagram: return "Abonnés, posts, commentaires sans réponse"
        case .github: return "Pull requests et état des builds"
        case .vercel: return "Déploiements des sites"
        case .pagespeed: return "Score de vitesse quotidien des sites"
        }
    }
    var icon: String {
        switch self {
        case .email: return "envelope.fill"
        case .espace: return "folder.fill"
        case .agenda: return "calendar"
        case .sites: return "globe"
        case .phone: return "iphone.gen3"
        case .instagram: return "camera.fill"
        case .github: return "chevron.left.forwardslash.chevron.right"
        case .vercel: return "triangle.fill"
        case .pagespeed: return "gauge.with.dots.needle.67percent"
        }
    }
    var color: String {
        switch self {
        case .email: return "#FF8A52"
        case .espace: return "#FF5B37"
        case .agenda: return "#FFD65C"
        case .sites: return "#F7C3D4"
        case .phone: return "#3B9EFF"
        case .instagram: return "#E1306C"
        case .github: return "#F4505E"
        case .vercel: return "#7C5CFF"
        case .pagespeed: return "#22C55E"
        }
    }
    /// Keychain keys owned by this connection (removed on « Déconnecter »).
    var keys: [String] {
        switch self {
        case .email: return EmailSender.keys
        case .espace: return ["espace-token", "espace-url"]
        case .agenda: return ["agenda-ics-url"]
        case .sites, .phone: return []
        case .instagram: return ["instagram-token", "instagram-user-id"]
        case .github: return ["github-token"]
        case .vercel: return ["vercel-token"]
        case .pagespeed: return ["pagespeed-api-key"]
        }
    }

    @MainActor var isConnected: Bool {
        let k = KeychainStore.shared
        switch self {
        case .email: return EmailSender.account != nil
        case .espace: return k.get("espace-token") != nil
        case .agenda: return k.get("agenda-ics-url") != nil
        case .sites: return !AppState.shared.sitesManual.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .phone: return PhoneBridge.enabled
        case .instagram: return k.get("instagram-token") != nil
        case .github: return k.get("github-token") != nil
        case .vercel: return k.get("vercel-token") != nil
        case .pagespeed: return k.get("pagespeed-api-key") != nil
        }
    }

    @MainActor var detail: String {
        let k = KeychainStore.shared
        switch self {
        case .email: return k.get("mail-address") ?? ""
        case .sites:
            let n = AppState.shared.sitesManual.split(whereSeparator: \.isNewline).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
            return n == 1 ? "1 site" : "\(n) sites"
        case .instagram: return AppState.shared.social.map { $0.username.isEmpty ? "" : "@\($0.username)" } ?? ""
        case .phone: return "jumelage activé"
        default: return "connecté"
        }
    }
}

struct ConnectionsPanel: View {
    @State private var open: ConnectionKind? = nil
    @State private var version = 0          // bumps after a sheet closes, to refresh the rows

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Connecte tes services en un clic. Oli vérifie que tout marche et garde tout dans le Trousseau.")
                .font(.system(size: 11.5)).foregroundColor(.secondary)
                .padding(.bottom, 4)
            ForEach(ConnectionKind.allCases) { kind in
                ConnectionRow(kind: kind) { open = kind }
                    .id("\(kind.rawValue)-\(version)")
            }
        }
        .sheet(item: $open, onDismiss: { version += 1 }) { kind in
            ConnectSheet(kind: kind) { open = nil }
        }
    }
}

private struct ConnectionRow: View {
    let kind: ConnectionKind
    let action: () -> Void

    var body: some View {
        let on = kind.isConnected
        HStack(spacing: 10) {
            Image(systemName: kind.icon)
                .font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color(hex: kind.color)))
            VStack(alignment: .leading, spacing: 1) {
                Text(kind.title).font(.system(size: 12.5, weight: .semibold))
                Text(on ? kind.detail : kind.why).font(.system(size: 11))
                    .foregroundColor(on ? .green : .secondary).lineLimit(1)
            }
            Spacer()
            if on {
                Button("Gérer", action: action).buttonStyle(.bordered)
            } else {
                Button("Se connecter", action: action).buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 5).padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.04)))
    }
}

// MARK: - The sheet

private struct ConnectSheet: View {
    let kind: ConnectionKind
    let close: () -> Void

    @State private var id = ""          // address / token / link
    @State private var secret = ""      // password
    @State private var extra = ""       // name, espace URL, host…
    @State private var port = ""
    @State private var sites = AppState.shared.sitesManual
    @State private var busy = false
    @State private var error: String? = nil
    @State private var done = false
    @State private var showMore = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: kind.icon)
                    .font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: kind.color)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.isConnected ? kind.title : "Se connecter à \(kind.title)").font(.system(size: 15, weight: .semibold))
                    Text(kind.why).font(.system(size: 11.5)).foregroundColor(.secondary)
                }
            }
            fields
            if let error { Text(error).font(.system(size: 11.5)).foregroundColor(.red).fixedSize(horizontal: false, vertical: true) }
            if done { Label("Connecté", systemImage: "checkmark.circle.fill").foregroundColor(.green).font(.system(size: 12.5, weight: .semibold)) }
            HStack {
                if kind.isConnected && kind != .sites && kind != .phone {
                    Button("Déconnecter", role: .destructive) { disconnect() }
                }
                Spacer()
                Button("Annuler", action: close).keyboardShortcut(.cancelAction)
                Button(busy ? "Vérification…" : (kind == .sites ? "Enregistrer" : kind == .phone ? "Terminé" : "Se connecter")) { connect() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(busy || !canSubmit)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear(perform: prefill)
    }

    // MARK: Fields per service

    @ViewBuilder private var fields: some View {
        switch kind {
        case .email:
            TextField("Adresse email", text: $id).textFieldStyle(.roundedBorder)
            SecureField("Mot de passe", text: $secret).textFieldStyle(.roundedBorder)
            if let help = appPasswordHelp {
                Link(destination: help.url) {
                    Text("\(help.text) — créer un mot de passe d’application").font(.system(size: 11))
                }
            }
            DisclosureGroup("Plus d’options", isExpanded: $showMore) {
                TextField("Nom affiché (facultatif)", text: $extra).textFieldStyle(.roundedBorder)
                HStack {
                    TextField("Serveur (trouvé tout seul)", text: $hostField).textFieldStyle(.roundedBorder)
                    TextField("Port", text: $port).textFieldStyle(.roundedBorder).frame(width: 64)
                }
            }
            .font(.system(size: 11.5))
        case .espace:
            SecureField("Code d’équipe", text: $id).textFieldStyle(.roundedBorder)
            DisclosureGroup("Plus d’options", isExpanded: $showMore) {
                TextField("Adresse de l’espace (par défaut espace.oculot.studio)", text: $extra).textFieldStyle(.roundedBorder)
            }
            .font(.system(size: 11.5))
        case .agenda:
            SecureField("Mot de passe de l’agenda", text: $secret).textFieldStyle(.roundedBorder)
            if !agendaMembers.isEmpty {
                Picker("Je suis", selection: $agendaMember) {
                    Text("Choisis ton prénom").tag(AgendaLogin.Member?.none)
                    ForEach(agendaMembers) { m in Text(m.name).tag(Optional(m)) }
                }
            }
            DisclosureGroup("Plus d’options", isExpanded: $showMore) {
                TextField("ou colle un lien iCal (https://… ou webcal://…)", text: $id).textFieldStyle(.roundedBorder)
            }
            .font(.system(size: 11.5))
        case .sites:
            Text("Une adresse par ligne. Les sites livrés de l’espace client sont ajoutés tout seuls.")
                .font(.system(size: 11)).foregroundColor(.secondary)
            TextEditor(text: $sites).font(.system(size: 12, design: .monospaced)).frame(height: 110)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
        case .phone:
            Toggle("Autoriser Oli Android à utiliser Claude via ce Mac", isOn: $phoneOn)
                .onChange(of: phoneOn) { _, on in PhoneBridge.enabled = on }
            if phoneOn {
                if let link = PhoneBridge.pairingLink(), let img = PhoneBridge.qrImage(link) {
                    HStack(alignment: .top, spacing: 14) {
                        Image(nsImage: img).interpolation(.none).resizable().frame(width: 150, height: 150)
                            .padding(6).background(Color.white).clipShape(RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Sur le téléphone : Oli → Connexions → Claude → « Se connecter », puis scanne ce code.")
                                .font(.system(size: 11.5)).fixedSize(horizontal: false, vertical: true)
                            Text("Téléphone et Mac sur le même Wi-Fi, Oli lancé.").font(.system(size: 11)).foregroundColor(.secondary)
                            Button("Copier le lien") {
                                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(link, forType: .string)
                            }
                            Button("Nouveau code (déjumeler)") { PhoneBridge.newToken(); phoneRefresh += 1 }
                        }
                    }
                    .id(phoneRefresh)
                    Toggle("Répondre aux autorisations de Claude Code depuis le téléphone", isOn: $phoneApprovals)
                        .onChange(of: phoneApprovals) { _, on in PhoneBridge.approvalsEnabled = on }
                    Text("Désactivé, le téléphone voit seulement tes sessions. Activé, il peut autoriser une commande sur ce Mac : n’utilise-le que sur un Wi-Fi de confiance.")
                        .font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Pas de réseau local détecté : connecte le Mac au Wi-Fi.").font(.system(size: 11.5)).foregroundColor(.red)
                }
            }
        case .instagram:
            SecureField("Jeton Instagram (IGAA…)", text: $id).textFieldStyle(.roundedBorder)
            Link("Où trouver mon jeton ?", destination: URL(string: "https://developers.facebook.com/docs/instagram-platform/instagram-api-with-instagram-login/get-started")!)
                .font(.system(size: 11))
        case .github:
            if ConnectSheet.ghPath != nil {
                Button { importGitHub() } label: { Label("Utiliser mon compte GitHub de ce Mac", systemImage: "bolt.fill") }
            }
            SecureField("ou colle un jeton GitHub", text: $id).textFieldStyle(.roundedBorder)
        case .vercel:
            if ConnectSheet.vercelAuthFile != nil {
                Button { importVercel() } label: { Label("Utiliser ma connexion Vercel de ce Mac", systemImage: "bolt.fill") }
            }
            SecureField("ou colle un jeton Vercel", text: $id).textFieldStyle(.roundedBorder)
        case .pagespeed:
            SecureField("Clé API Google (gratuite)", text: $id).textFieldStyle(.roundedBorder)
            Link("Créer une clé gratuite", destination: URL(string: "https://developers.google.com/speed/docs/insights/v5/get-started")!)
                .font(.system(size: 11))
        }
    }

    @State private var hostField = ""
    @State private var agendaMembers: [AgendaLogin.Member] = []
    @State private var phoneOn = PhoneBridge.enabled
    @State private var phoneRefresh = 0
    @State private var phoneApprovals = PhoneBridge.approvalsEnabled
    @State private var agendaMember: AgendaLogin.Member? = nil

    private var canSubmit: Bool {
        switch kind {
        case .email: return id.contains("@") && !secret.isEmpty
        case .sites, .phone: return true
        case .agenda: return !secret.isEmpty || !id.trimmingCharacters(in: .whitespaces).isEmpty
        default: return !id.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private var appPasswordHelp: (text: String, url: URL)? {
        let d = id.split(separator: "@").last.map { $0.lowercased() } ?? ""
        if ["gmail.com", "googlemail.com"].contains(d) { return ("Gmail", URL(string: "https://myaccount.google.com/apppasswords")!) }
        if ["icloud.com", "me.com", "mac.com"].contains(d) { return ("iCloud", URL(string: "https://account.apple.com/account/manage")!) }
        return nil
    }

    private func prefill() {
        let k = KeychainStore.shared
        switch kind {
        case .email:
            id = k.get("mail-address") ?? ""; secret = k.get("mail-password") ?? ""; extra = k.get("mail-name") ?? ""
            hostField = k.get("mail-host") ?? ""; port = k.get("mail-port") ?? ""
        case .espace: id = k.get("espace-token") ?? ""; extra = k.get("espace-url") ?? ""
        case .agenda: id = ""
        case .instagram: id = k.get("instagram-token") ?? ""
        case .github: id = k.get("github-token") ?? ""
        case .vercel: id = k.get("vercel-token") ?? ""
        case .pagespeed: id = k.get("pagespeed-api-key") ?? ""
        case .sites, .phone: break
        }
    }

    // MARK: Connect / disconnect

    private func connect() {
        error = nil; busy = true
        let value = id.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            let problem = await verify(value)
            busy = false
            if let problem { error = problem; return }
            save(value)
            done = true
            SoundEngine.shared.play("approve")
            try? await Task.sleep(nanoseconds: 700_000_000)
            close()
        }
    }

    /// nil when it works, else a short French explanation.
    private func verify(_ value: String) async -> String? {
        switch kind {
        case .email:
            let preset = EmailSender.preset(for: value)
            let host = hostField.trimmingCharacters(in: .whitespaces).isEmpty ? preset.host : hostField
            let p = Int(port) ?? preset.port
            let account = EmailAccount(address: value, name: extra, password: secret, host: host, port: p)
            do { try await EmailSender.test(account); return nil } catch { return error.localizedDescription }
        case .espace:
            let base = extra.trimmingCharacters(in: .whitespaces).isEmpty ? "https://espace.oculot.studio" : extra
            return await check(url: base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/espace/summary",
                               bearer: value, refused: "Jeton refusé par l’espace client.")
        case .agenda where !secret.isEmpty:
            do {
                if agendaMembers.isEmpty {
                    let team = try await AgendaLogin.team(password: secret)
                    agendaMembers = team.members
                    agendaMember = team.me.flatMap { me in team.members.first { $0.id == me } } ?? AgendaLogin.guess(team.members)
                }
                guard let member = agendaMember else { return "Choisis ton prénom, puis « Se connecter »." }
                let link = try await AgendaLogin.calendarLink(password: secret, member: member.id)
                id = link
                return nil
            } catch { return error.localizedDescription }
        case .agenda:
            let fixed = value.hasPrefix("webcal://") ? "https://" + value.dropFirst(9) : Substring(value)
            guard let url = URL(string: String(fixed)),
                  let (data, resp) = try? await URLSession.shared.data(from: url) else { return "Lien injoignable." }
            let ok = (resp as? HTTPURLResponse)?.statusCode == 200 && (String(data: data, encoding: .utf8) ?? "").contains("BEGIN:VCALENDAR")
            return ok ? nil : "Ce lien ne donne pas de calendrier."
        case .instagram:
            let snap = await SocialFetcher.fetch(token: value, accountId: nil)
            return snap.error
        case .github:
            return await check(url: "https://api.github.com/user", bearer: value, refused: "Jeton GitHub refusé.")
        case .vercel:
            return await check(url: "https://api.vercel.com/v2/user", bearer: value,
                               refused: "Jeton Vercel refusé (la connexion de la CLI a peut-être expiré : relance « vercel login »).")
        case .pagespeed, .sites, .phone:
            return nil
        }
    }

    private func check(url: String, bearer: String, refused: String) async -> String? {
        guard let u = URL(string: url) else { return "Adresse invalide." }
        var req = URLRequest(url: u, timeoutInterval: 15)
        req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        guard let (_, resp) = try? await URLSession.shared.data(for: req) else { return "Service injoignable." }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 || code == 403 { return refused }
        return code == 200 ? nil : "Réponse \(code) du service."
    }

    private func save(_ value: String) {
        let k = KeychainStore.shared
        func put(_ key: String, _ v: String) { v.isEmpty ? k.remove(key) : k.set(key, value: v) }
        switch kind {
        case .email:
            put("mail-address", value); put("mail-password", secret); put("mail-name", extra.trimmingCharacters(in: .whitespaces))
            put("mail-host", hostField.trimmingCharacters(in: .whitespaces)); put("mail-port", port.trimmingCharacters(in: .whitespaces))
        case .espace:
            put("espace-token", value); put("espace-url", extra.trimmingCharacters(in: .whitespaces))
            EspacePoller.shared.pollNow(); AppState.shared.activatePill("integration_espace")
        case .agenda:
            put("agenda-ics-url", id.trimmingCharacters(in: .whitespacesAndNewlines)); AgendaPoller.shared.pollNow()
            AppState.shared.activatePill("integration_agenda")
        case .sites:
            AppState.shared.sitesManual = sites; SitesPoller.shared.checkNow()
            if !sites.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { AppState.shared.activatePill("integration_sites") }
        case .instagram:
            put("instagram-token", value); SocialPoller.shared.refreshNow()
            AppState.shared.activatePill("integration_instagram")
        case .github:
            put("github-token", value); GithubPoller.shared.triggerPulseNow()
            AppState.shared.activatePill("integration_github")
        case .vercel:
            put("vercel-token", value)
            AppState.shared.activatePill("integration_vercel")
        case .pagespeed:
            put("pagespeed-api-key", value)
        case .phone:
            break
        }
    }

    private func disconnect() {
        kind.keys.forEach { KeychainStore.shared.remove($0) }
        // Forget what the service had shown, so nothing stale stays on screen or in the widget.
        let app = AppState.shared
        switch kind {
        case .instagram: app.social = nil
        case .agenda: app.agendaEvents = []
        case .espace: app.espaceClients = []
        case .github: app.githubPulse = nil; app.githubActivity = nil; app.githubStats = nil
        case .vercel: app.vercelDeployments = []
        default: break
        }
        close()
    }

    // MARK: Reuse the logins already on this Mac

    static var ghPath: String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [home + "/.local/bin/gh", "/opt/homebrew/bin/gh", "/usr/local/bin/gh"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var vercelAuthFile: URL? {
        let u = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/com.vercel.cli/auth.json")
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    private func importGitHub() {
        guard let gh = Self.ghPath else { return }
        let p = Process(); p.executableURL = URL(fileURLWithPath: gh); p.arguments = ["auth", "token"]
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        do { try p.run() } catch { self.error = "GitHub CLI introuvable."; return }
        let token = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        p.waitUntilExit()
        if token.isEmpty { error = "Aucun compte GitHub connecté sur ce Mac (« gh auth login »)."; return }
        id = token
        connect()
    }

    private func importVercel() {
        guard let f = Self.vercelAuthFile, let d = try? Data(contentsOf: f),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let token = j["token"] as? String, !token.isEmpty else { error = "Connexion Vercel introuvable (« vercel login »)."; return }
        id = token
        connect()
    }
}
